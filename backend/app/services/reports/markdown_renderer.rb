module Reports
  class MarkdownRenderer
    def initialize(payload:)
      @payload = payload
    end

    def call
      sub = @payload[:submission]
      title = sub[:source_ref].presence || "Submission ##{sub[:id]}"
      lines = ["# Code Review — #{title}", '']
      lines.concat(summary_section)
      lines.concat(issues_section)
      lines.join("\n")
    end

    private

    def summary_section
      rev = @payload[:review]
      lines = ['## Summary', '']
      if rev
        lines << "- **Mode:** #{rev[:mode]}"
        lines << "- **Total issues:** #{rev[:total_issues]}"
        lines << ''
        lines.concat(scores_table(rev[:scores])) if rev[:scores].present?
      else
        lines << '_No review data available._'
        lines << ''
      end
      lines
    end

    def scores_table(scores)
      rows = scores.map { |k, v| "| #{k} | #{v} |" }
      ['| Severity | Count |', '|---|---|'] + rows + ['']
    end

    def issues_section
      lines = ['## Issues', '']
      grouped = @payload[:issues].group_by { |i| i[:file_path] }
      if grouped.empty?
        lines << '_No issues found._'
        lines << ''
        return lines
      end
      grouped.each do |file, file_issues|
        lines.concat(file_issues_block(file, file_issues))
      end
      lines
    end

    def file_issues_block(file, file_issues)
      lines = ["### #{file}", '']
      file_issues.each { |i| lines.concat(issue_lines(i)) }
      lines
    end

    def issue_lines(issue)
      range = "#{issue[:line_start]}–#{issue[:line_end]}"
      header = "- [#{issue[:severity].to_s.upcase}] #{issue[:rule_id]} (#{range}): #{issue[:message]}"
      lines = [header]
      lines << "  > #{issue[:suggestion]}" if issue[:suggestion].present?
      lines << ''
      lines
    end
  end
end
