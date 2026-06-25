require 'digest'

module LLM
  class ReviewService
    Result = Struct.new(:issues_attrs, :attempts, :duration_ms, :degraded, keyword_init: true)

    # Mirror Ast::Extractor::EXTENSION_MAP exactly (same keys/values)
    EXTENSION_MAP      = Ast::Extractor::EXTENSION_MAP
    MAX_LLM_FILES      = ENV.fetch('LLM_MAX_FILES', 20).to_i
    MAX_BYTES_PER_FILE = ENV.fetch('LLM_MAX_BYTES_PER_FILE', 24_000).to_i
    MAX_JSON_ATTEMPTS  = 3
    SEV_ALLOWED        = %w[info low medium high critical].freeze
    CAT_ALLOWED        = %w[code_quality bug style security refactor].freeze

    def initialize(submission:, client: LLM::OllamaClient.new, prompt_builder: LLM::PromptBuilder.new)
      @submission     = submission
      @client         = client
      @prompt_builder = prompt_builder
    end

    def call
      t0_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      all_attrs = []
      total_attempts = 0
      any_degraded = false

      source_files.first(MAX_LLM_FILES).each do |abs_path|
        next if File.size(abs_path) > MAX_BYTES_PER_FILE

        rel  = relative_path(abs_path)
        code = File.read(abs_path, encoding: 'UTF-8')
        attrs, file_attempts, file_degraded = review_one_file(rel, code)
        all_attrs.concat(attrs)
        total_attempts += file_attempts
        any_degraded ||= file_degraded
      rescue StandardError => e
        Rails.logger.warn("[LLM::ReviewService] file error (non-fatal): #{e.class} — #{e.message}")
        any_degraded = true
      end

      Result.new(
        issues_attrs: all_attrs,
        attempts: total_attempts,
        duration_ms: ms_since(t0_mono),
        degraded: any_degraded
      )
    end

    private

    def review_one_file(rel, code)
      system_prompt = LLM::PromptBuilder::SYSTEM_PROMPT
      user_prompt   = @prompt_builder.build(
        file_rel_path: rel,
        language: @submission.language,
        code: code,
        linter_issues: linter_issues_for(rel)
      )

      attempts = 0

      loop do
        attempts += 1
        begin
          raw    = @client.chat(system: system_prompt, user: user_prompt)
          parsed = JSON.parse(raw)
          return [map_issues(parsed, rel, code), attempts, false] if valid_shape?(parsed)
        rescue LLM::Errors::TransportError => e
          Rails.logger.warn("[LLM::ReviewService] transport error (non-fatal): #{e.message}")
          return [[], attempts, true]
        rescue JSON::ParserError
          # fall through to retry
        end

        return [[], attempts, true] if attempts >= MAX_JSON_ATTEMPTS
      end
    end

    def valid_shape?(parsed)
      parsed.is_a?(Hash) && parsed['issues'].is_a?(Array)
    end

    def map_issues(parsed, rel, code)
      line_count = code.lines.size
      parsed['issues'].filter_map { |raw| build_issue_attr(raw, rel, line_count) }
    end

    def build_issue_attr(raw, rel, line_count)
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

    # Mirror Ast::Extractor#collect_source_files
    def source_files
      root = @submission.blob_path
      return [root] unless File.directory?(root)

      exts = Array(EXTENSION_MAP[@submission.language])
      Dir.glob('**/*', base: root).filter_map do |rel|
        abs = File.join(root, rel)
        abs if File.file?(abs) && exts.include?(File.extname(rel).downcase)
      end.sort
    end

    # Mirror Ast::Extractor#relative_path
    def relative_path(abs_path)
      root = @submission.blob_path
      return File.basename(abs_path) unless File.directory?(root)

      Pathname.new(abs_path).relative_path_from(Pathname.new(root)).to_s
    end

    def linter_issues_for(rel)
      @submission.issues.where(source: :linter).select { |i| canon_path(i.file_path) == rel }
    end

    def canon_path(path)
      return File.basename(path) unless File.directory?(@submission.blob_path)

      root = File.expand_path(@submission.blob_path)
      abs  = File.expand_path(path, root)
      abs.start_with?(root + File::SEPARATOR) ? abs[(root.size + 1)..] : File.basename(path)
    end

    def ms_since(t0_mono)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0_mono) * 1000).round
    end
  end
end
