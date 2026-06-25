require 'digest'

module Runners
  class Bandit < Base
    RUNNER_NAME = 'bandit'

    SEVERITY_MAP = {
      'LOW'    => 'low',
      'MEDIUM' => 'medium',
      'HIGH'   => 'high'
    }.freeze

    def initialize(file_path:, submission_id:)
      @file_path     = file_path
      @submission_id = submission_id
    end

    def call
      stdout, stderr, exit_code, duration_ms = subprocess_run(
        ['bandit', '-r', @file_path, '-f', 'json', '-q']
      )

      issues_attrs = parse_output(stdout)
      Result.new(
        issues_attrs: issues_attrs,
        stdout: stdout,
        stderr: stderr,
        exit_code: exit_code,
        duration_ms: duration_ms
      )
    rescue Errno::ENOENT
      Result.new(
        issues_attrs: [],
        stdout: '',
        stderr: 'bandit binary not found — install Bandit on the host to enable Python security scanning',
        exit_code: nil,
        duration_ms: 0
      )
    end

    private

    def parse_output(stdout)
      data = JSON.parse(stdout)
      issues = []

      Array(data.fetch('results', [])).each do |finding|
        test_id    = finding['test_id'].to_s
        rule_id    = "Bandit/#{test_id}"
        file_path  = finding['filename'].to_s
        line_start = finding['line_number'].to_i
        line_start = 1 if line_start < 1
        line_range = Array(finding['line_range'])
        line_end   = line_range.last.to_i
        line_end   = line_start if line_end < line_start
        dedup_key  = Digest::SHA1.hexdigest("#{file_path}|#{line_start}|#{rule_id}")

        issues << {
          source: :linter,
          rule_id: rule_id,
          severity: map_severity(finding['issue_severity']),
          category: 'security',
          file_path: file_path,
          line_start: line_start,
          line_end: line_end,
          column_start: nil,
          column_end: nil,
          message: finding['issue_text'].to_s,
          suggestion: nil,
          confidence: nil,
          dedup_key: dedup_key
        }
      end

      issues
    rescue JSON::ParserError
      []
    end

    def map_severity(raw)
      SEVERITY_MAP.fetch(raw.to_s.upcase, 'low')
    end
  end
end
