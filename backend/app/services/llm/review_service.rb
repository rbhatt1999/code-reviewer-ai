require 'digest'
require 'set'

module LLM
  # Agentic review: instead of dumping every file's full content into the
  # prompt up front, the model is given a file TREE (paths + sizes + which
  # files the static analyzer already flagged) and a `read_file` tool. It
  # decides which files are worth a closer look and pulls them one at a time,
  # the same way an agent like Claude Code or Codex explores a codebase,
  # before producing its final list of issues. This bounds both prompt size
  # and cost regardless of repo size, and lets the model prioritize
  # linter-flagged files over blindly reading everything.
  class ReviewService
    Result = Struct.new(:issues_attrs, :attempts, :duration_ms, :degraded, :review_log, keyword_init: true)

    EXTENSION_MAP      = Ast::Extractor::EXTENSION_MAP
    MAX_LLM_FILES       = ENV.fetch('LLM_MAX_FILES', 20).to_i        # cap on read_file calls per submission
    MAX_BYTES_PER_FILE  = ENV.fetch('LLM_MAX_BYTES_PER_FILE', 24_000).to_i
    MAX_JSON_ATTEMPTS   = 3                                          # final-answer JSON-parse retries
    MAX_ROUNDS          = MAX_LLM_FILES + MAX_JSON_ATTEMPTS + 4      # hard cap on total round-trips
    SEV_ALLOWED         = %w[info low medium high critical].freeze
    CAT_ALLOWED         = %w[code_quality bug style security refactor].freeze

    # Build-artifact / dependency directories are never worth putting in the
    # tree at all — excluding them keeps the tree itself small regardless of
    # what the model decides to read.
    IGNORED_DIR_PATTERN = %r{(^|/)(vendor|node_modules|dist|build|coverage|tmp|log|\.git)(/|$)}i.freeze

    def initialize(submission:, client: LLM::DeepseekClient.new, prompt_builder: LLM::PromptBuilder.new,
                   on_progress: ->(_message) {})
      @submission     = submission
      @client         = client
      @prompt_builder = prompt_builder
      @on_progress    = on_progress
    end

    def call
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tree = file_tree
      return empty_result(t0) if tree.empty?

      known_rels = tree.map { |f| f[:rel] }.to_set
      log = []
      messages = [
        { role: 'system', content: LLM::PromptBuilder::SYSTEM_PROMPT },
        { role: 'user', content: build_initial_prompt(tree, log) }
      ]

      run_agent_loop(messages, known_rels, t0, log)
    rescue StandardError => e
      Rails.logger.warn("[LLM::ReviewService] unexpected error (non-fatal): #{e.class} — #{e.message}")
      Result.new(issues_attrs: [], attempts: 1, duration_ms: ms_since(t0), degraded: true, review_log: [])
    end

    private

    def empty_result(t0)
      Result.new(issues_attrs: [], attempts: 0, duration_ms: ms_since(t0), degraded: false, review_log: [])
    end

    # PR-based submissions (github_webhook) get a diff-first prompt — the
    # changed files come first, full tree second — seeded from pr_diff.json
    # that IngestJob stashed alongside the cloned repo. Everything else
    # (git_url, zip, single_file, paste — or a PR whose diff fetch failed)
    # falls back to the plain file-tree prompt. Every diff file that seeds the
    # prompt is recorded in `log` up front, before the model has done anything,
    # since those are "reviewed" from the very first round-trip.
    def build_initial_prompt(tree, log)
      diff_files = load_pr_diff
      if diff_files.present?
        diff_files.each do |f|
          log << { type: 'diff', file: f['filename'], status: f['status'],
                    additions: f['additions'], deletions: f['deletions'] }
        end
        @prompt_builder.build_pr_initial(
          language: @submission.language, diff_files: diff_files, file_tree: tree,
          linter_summary: linter_summary_lines
        )
      else
        @prompt_builder.build_initial(
          language: @submission.language, file_tree: tree, linter_summary: linter_summary_lines
        )
      end
    end

    def load_pr_diff
      # blob_path always points one level inside the submission's own storage
      # directory (".../<id>/cloned", ".../<id>/extracted", ".../<id>/app.rb",
      # etc.) — pr_diff.json, when it exists, is a sibling of that directory.
      dir  = File.dirname(@submission.blob_path)
      path = File.join(dir, 'pr_diff.json')
      return [] unless File.file?(path)

      JSON.parse(File.read(path))
    rescue StandardError => e
      Rails.logger.warn("[LLM::ReviewService] could not load pr_diff.json (non-fatal): #{e.message}")
      []
    end

    # rubocop:disable Metrics/MethodLength
    def run_agent_loop(messages, known_rels, t0, log)
      attempts    = 0
      files_read  = 0
      degraded    = false
      final_attrs = []

      MAX_ROUNDS.times do
        offer_tools = files_read < MAX_LLM_FILES
        message = @client.complete(messages: messages, tools: offer_tools ? LLM::PromptBuilder::TOOLS : nil)

        tool_calls = message['tool_calls']
        if tool_calls.present?
          messages << { role: 'assistant', content: message['content'], tool_calls: tool_calls }
          tool_calls.each do |tool_call|
            text, files_read = execute_tool_call(tool_call, known_rels, files_read, log)
            messages << { role: 'tool', tool_call_id: tool_call['id'], content: text }
          end
          next
        end

        attempts += 1
        parsed = safe_parse(message['content'])
        if parsed
          final_attrs = map_issues(parsed, known_rels)
          log << { type: 'final_answer', issues_found: final_attrs.size }
          break
        end

        if attempts >= MAX_JSON_ATTEMPTS
          degraded = true
          log << { type: 'degraded', reason: 'invalid_json' }
          break
        end

        messages << { role: 'assistant', content: message['content'].to_s }
        messages << { role: 'user',
                      content: 'That was not valid JSON matching the schema. Respond with ONLY the JSON object.' }
      rescue LLM::Errors::TransportError => e
        Rails.logger.warn("[LLM::ReviewService] transport error (non-fatal): #{e.message}")
        attempts += 1
        degraded = true
        log << { type: 'degraded', reason: 'transport_error' }
        break
      end

      Result.new(
        issues_attrs: final_attrs,
        attempts: [attempts, 1].max,
        duration_ms: ms_since(t0),
        degraded: degraded || (final_attrs.empty? && attempts.zero?),
        review_log: log
      )
    end
    # rubocop:enable Metrics/MethodLength

    # --- file tree (paths + sizes only — NOT contents) --------------------

    def file_tree
      root = @submission.blob_path
      return single_file_tree(root) unless File.directory?(root)

      exts = Array(EXTENSION_MAP[@submission.language])
      Dir.glob('**/*', base: root).filter_map do |rel|
        next if rel.match?(IGNORED_DIR_PATTERN)

        abs = File.join(root, rel)
        next unless File.file?(abs) && exts.include?(File.extname(rel).downcase)

        { rel: rel, bytes: File.size(abs), linter_issue_count: linter_issue_count_for(rel) }
      end.sort_by { |f| f[:rel] }
    end

    def single_file_tree(root)
      return [] unless File.file?(root)

      rel = File.basename(root)
      [{ rel: rel, bytes: File.size(root), linter_issue_count: linter_issue_count_for(rel) }]
    end

    def linter_issue_count_for(rel)
      @linter_counts ||= @submission.issues.where(source: :linter).each_with_object(Hash.new(0)) do |issue, counts|
        counts[canon_path(issue.file_path)] += 1
      end
      @linter_counts[rel] || 0
    end

    def linter_summary_lines
      @submission.issues.where(source: :linter).map do |i|
        "#{canon_path(i.file_path)}:L#{i.line_start}-#{i.line_end} [#{i.rule_id}] #{i.message}"
      end
    end

    # --- tool execution ------------------------------------------------------

    def execute_tool_call(tool_call, known_rels, files_read, log)
      path_arg = extract_path_arg(tool_call)
      @on_progress.call("Reading #{path_arg}…")

      if files_read >= MAX_LLM_FILES
        log << { type: 'read_file_error', file: path_arg, error: 'limit_reached' }
        return ["Error: no more files can be read (limit of #{MAX_LLM_FILES} reached).", files_read]
      end

      rel = known_rels.include?(path_arg) ? path_arg : nil
      unless rel
        log << { type: 'read_file_error', file: path_arg, error: 'not_in_tree' }
        return ["Error: '#{path_arg}' is not a file in the file tree.", files_read]
      end

      abs = resolve_abs(rel)
      unless abs && File.file?(abs)
        log << { type: 'read_file_error', file: rel, error: 'not_found' }
        return ["Error: file not found.", files_read]
      end

      size = File.size(abs)
      if size > MAX_BYTES_PER_FILE
        log << { type: 'read_file_error', file: rel, error: 'too_large', bytes: size }
        return ["Error: file is #{size} bytes, exceeds the #{MAX_BYTES_PER_FILE}-byte review limit.", files_read]
      end

      code = File.read(abs, encoding: 'UTF-8')
      numbered = code.lines.each_with_index.map { |line, idx| "#{format('%4d', idx + 1)}| #{line.chomp}" }.join("\n")
      log << { type: 'read_file', file: rel, bytes: size }
      ["## #{rel}\n#{numbered}", files_read + 1]
    rescue StandardError => e
      Rails.logger.warn("[LLM::ReviewService] read_file error (non-fatal): #{e.message}")
      log << { type: 'read_file_error', file: path_arg, error: 'read_error' }
      ['Error: could not read file.', files_read]
    end

    def extract_path_arg(tool_call)
      raw = tool_call.dig('function', 'arguments')
      JSON.parse(raw.to_s)['path'].to_s.strip.sub(%r{\A\./}, '')
    rescue JSON::ParserError
      raw.to_s
    end

    def resolve_abs(rel)
      root = @submission.blob_path
      return root if !File.directory?(root) && File.basename(root) == rel

      File.join(root, rel)
    end

    # --- final answer parsing/mapping ---------------------------------------

    def safe_parse(content)
      parsed = JSON.parse(content.to_s)
      parsed.is_a?(Hash) && parsed['issues'].is_a?(Array) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    def map_issues(parsed, known_rels)
      parsed['issues'].filter_map { |raw| build_issue_attr(raw, known_rels) }
    end

    def build_issue_attr(raw, known_rels)
      rel = raw['file'].to_s.strip
      return nil unless known_rels.include?(rel)

      abs = resolve_abs(rel)
      return nil unless abs && File.file?(abs)

      line_count = File.read(abs, encoding: 'UTF-8').lines.size
      line_start = raw['line_start'].to_i
      return nil if line_start < 1 || line_start > line_count

      severity  = SEV_ALLOWED.include?(raw['severity']) ? raw['severity'] : 'low'
      category  = CAT_ALLOWED.include?(raw['category']) ? raw['category'] : 'code_quality'
      rule_id   = "LLM/#{raw['rule'].to_s.strip.presence || 'General'}"
      line_end  = [raw['line_end'].to_i, line_start].max
      conf      = parse_confidence(raw['confidence'])
      dedup_key = Digest::SHA1.hexdigest("#{rel}|#{line_start}|#{rule_id}")

      {
        source: :llm,
        analysis_run: nil, # no AnalysisRun for LLM issues
        rule_id: rule_id,
        severity: severity,
        category: category,
        file_path: rel,
        line_start: line_start,
        line_end: line_end,
        column_start: nil,
        column_end: nil,
        message: raw['message'].to_s.presence || 'LLM-reported issue',
        suggestion: raw['suggestion'].presence,
        confidence: conf,
        dedup_key: dedup_key
      }
    end

    def parse_confidence(val)
      val.is_a?(Numeric) ? val.to_f.clamp(0.0, 1.0) : nil
    end

    # Mirror Ast::Extractor#relative_path's rooting logic
    def canon_path(path)
      return File.basename(path) unless File.directory?(@submission.blob_path)

      root = File.expand_path(@submission.blob_path)
      abs  = File.expand_path(path, root)
      abs.start_with?(root + File::SEPARATOR) ? abs[(root.size + 1)..] : File.basename(path)
    end

    def ms_since(t0)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
    end
  end
end
