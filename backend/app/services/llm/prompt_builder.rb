module LLM
  class PromptBuilder
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a meticulous senior code reviewer with tool access to the submitted
      codebase. You do NOT start with full file contents. Depending on what this
      submission is, your first message is either:
        (a) a pull request's changed-file diffs (your primary focus — review
            these first), plus a full repository file tree for extra context, or
        (b) just a file tree, when there is no pull request to diff against.
      In both cases, a static analyzer's findings are included for context.
      Call the `read_file` tool with a path exactly as shown in the file tree to
      read a file's full content before reporting any issue in it — including
      files shown in a diff, since the patch alone may not have enough context.
      Call it as many times as you need, but only for files you genuinely judge
      worth a closer look — files the static analyzer already flagged are a
      strong signal, but you may read others too, e.g. to see a full function
      definition, a caller, or a related test. Do not guess at code you have not
      read via the tool, and do not report an issue in a file you never read.

      Perform READ-ONLY review: never suggest rewriting a whole file, never invent
      code that isn't in a file you read. Prefer correctness, security, and
      maintainability issues over trivial style nits (a linter already covers
      style). Do not duplicate issues already reported by the static analyzer.

      When you are done gathering context (call tools first — do not call a tool
      and give your final answer in the same turn), respond with ONLY a single
      JSON object, no other text, matching this schema:
      {
        "issues": [
          {
            "file":       "<relative path, exactly as shown in the file tree>",
            "line_start": <integer, 1-based, within that file>,
            "line_end":   <integer, >= line_start>,
            "severity":   "info" | "low" | "medium" | "high" | "critical",
            "category":   "code_quality" | "bug" | "style" | "security" | "refactor",
            "rule":       "<short kebab-or-pascal identifier, e.g. n-plus-one-query>",
            "message":    "<one or two sentences describing the problem>",
            "suggestion": "<optional: how to fix, or null>",
            "confidence": <number between 0 and 1>
          }
        ]
      }
      If you read files and found no issues, respond with {"issues": []}.
    PROMPT

    # OpenAI-compatible function-calling schema, offered to the model on every
    # round until it has used up its read_file budget (see
    # LLM::ReviewService::MAX_LLM_FILES) — this is what lets the model pull only
    # the files it decides matter instead of every file being loaded up front.
    TOOLS = [
      {
        type: 'function',
        function: {
          name: 'read_file',
          description: 'Read the full contents of one source file from this submission, ' \
                       'by its relative path exactly as shown in the file tree.',
          parameters: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'Relative path, exactly as shown in the file tree' }
            },
            required: ['path']
          }
        }
      }
    ].freeze

    # Builds the initial user-turn prompt: a file tree + static analyzer summary —
    # deliberately WITHOUT file contents, so the model requests only what it
    # needs via the read_file tool instead of every file being loaded up front.
    # @param language [String] detected language (e.g. 'ruby')
    # @param file_tree [Array<Hash>] [{rel:, bytes:, linter_issue_count:}, ...]
    # @param linter_summary [Array<String>] pre-formatted linter finding lines
    def build_initial(language:, file_tree:, linter_summary:)
      tree_lines = file_tree.map do |f|
        flag = f[:linter_issue_count].to_i.positive? ? " [flagged: #{f[:linter_issue_count]} issue(s)]" : ''
        "- #{f[:rel]} (#{f[:bytes]} bytes)#{flag}"
      end.join("\n")

      linter_section = linter_summary.empty? ? '(none)' : linter_summary.join("\n")

      <<~PROMPT
        ## Project language
        #{language}

        ## File tree (#{file_tree.size} file(s) eligible for review)
        #{tree_lines}

        ## Static analyzer findings (do NOT repeat these as your own issues)
        #{linter_section}

        ## Task
        Decide which of the files above are worth reading, call read_file for each
        one, then respond with the strict-JSON object described in the system
        message.
      PROMPT
    end

    # Builds the initial user-turn prompt for a PR-based submission: the
    # changed files' diffs come FIRST (the actual review focus), the full file
    # tree is included as secondary context the model can pull from via
    # read_file if a diff alone doesn't give it enough to judge a change.
    # @param language [String] detected language (e.g. 'ruby')
    # @param diff_files [Array<Hash>] [{filename:, status:, additions:, deletions:, patch_numbered:}, ...]
    # @param file_tree [Array<Hash>] [{rel:, bytes:, linter_issue_count:}, ...]
    # @param linter_summary [Array<String>] pre-formatted linter finding lines
    def build_pr_initial(language:, diff_files:, file_tree:, linter_summary:)
      diff_section = diff_files.map do |f|
        "### #{f['filename']} (#{f['status']}, +#{f['additions']}/-#{f['deletions']})\n#{f['patch_numbered']}"
      end.join("\n\n")

      tree_lines = file_tree.map do |f|
        flag = f[:linter_issue_count].to_i.positive? ? " [flagged: #{f[:linter_issue_count]} issue(s)]" : ''
        "- #{f[:rel]} (#{f[:bytes]} bytes)#{flag}"
      end.join("\n")

      linter_section = linter_summary.empty? ? '(none)' : linter_summary.join("\n")

      <<~PROMPT
        ## Project language
        #{language}

        ## Changed files in this pull request — review these first
        #{diff_section}

        ## Full repository tree (#{file_tree.size} file(s) — read_file any of
        ## these if you need more context than the diff alone gives you)
        #{tree_lines}

        ## Static analyzer findings (do NOT repeat these as your own issues)
        #{linter_section}

        ## Task
        Focus your review on the changed files above. Read additional files via
        read_file only if you genuinely need more context to judge a change —
        e.g. a full function definition, a caller, or a related test. Then
        respond with the strict-JSON object described in the system message.
      PROMPT
    end
  end
end
