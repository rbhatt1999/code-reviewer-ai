module LLM
  class PromptBuilder
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a meticulous senior code reviewer. You perform READ-ONLY review: never
      suggest rewriting the whole file, never invent code that is not shown. Review ONLY
      the file provided. Report concrete, actionable issues anchored to specific line
      numbers that exist in the provided file. Prefer correctness, security, and
      maintainability issues over trivial style nits (a linter already covers style).
      Do not duplicate issues already reported by the linter (they are listed for context).

      You MUST respond with a single JSON object that exactly matches this schema:
      {
        "issues": [
          {
            "line_start": <integer, 1-based, within the file>,
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
      If you find no issues, respond with {"issues": []}. Output JSON only — no prose.
    PROMPT

    # Builds the user-turn prompt for a single source file.
    # @param file_rel_path [String] relative path to the file (e.g. 'app/models/user.rb')
    # @param language [String] detected language (e.g. 'ruby')
    # @param code [String] full file content
    # @param linter_issues [Array<Issue>] already-persisted linter issues for this file
    def build(file_rel_path:, language:, code:, linter_issues:)
      linter_section = if linter_issues.empty?
                         '(none)'
                       else
                         linter_issues
                           .map { |i| "L#{i.line_start}-#{i.line_end} [#{i.rule_id}] #{i.message}" }
                           .join("\n")
                       end

      numbered_code = code.lines.each_with_index.map do |line, idx|
        "#{format('%4d', idx + 1)}| #{line.chomp}"
      end.join("\n")

      <<~PROMPT
        ## File
        path: #{file_rel_path}
        language: #{language}

        ## Linter findings already reported for this file (do NOT repeat these)
        #{linter_section}

        ## Source (line-numbered)
        #{numbered_code}

        ## Task
        Return the strict-JSON object described in the system message for THIS file only.
      PROMPT
    end
  end
end
