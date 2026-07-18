module Diff
  # Annotates a unified-diff patch (as returned by GitHub's pulls/:number/files
  # API) with each retained/added line's actual line number in the NEW (head)
  # version of the file — GitHub's patch format only gives hunk-header ranges,
  # not per-line numbers. This lets the model cite line_start/line_end that
  # line up exactly with what `read_file` would return for the same file.
  class HunkFormatter
    HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.freeze

    def self.number(patch)
      new(patch).call
    end

    def initialize(patch)
      @patch = patch.to_s
    end

    def call
      new_line = nil
      @patch.each_line.map { |line| format_line(line.chomp, new_line) { |n| new_line = n } }.join("\n")
    rescue StandardError
      @patch # malformed patch — fall back to the raw text rather than raising
    end

    private

    def format_line(line, current_new_line)
      if (match = line.match(HUNK_HEADER))
        yield match[1].to_i
        return line
      end

      case line[0]
      when '+'
        numbered = "#{format('%4d', current_new_line)}| #{line}"
        yield current_new_line + 1
        numbered
      when '-'
        "    -| #{line}" # removed line — no line number in the new file
      when '\\'
        line # "\ No newline at end of file" marker — not a real code line
      else
        numbered = "#{format('%4d', current_new_line)}| #{line}"
        yield current_new_line + 1
        numbered
      end
    end
  end
end
