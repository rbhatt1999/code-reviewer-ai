require 'digest'

module Runners
  class Brakeman < Base
    RUNNER_NAME = 'brakeman'

    SEVERITY_MAP = {
      'Weak'   => 'low',
      'Medium' => 'medium',
      'High'   => 'high'
    }.freeze

    def initialize(file_path:, submission_id:)
      @file_path     = file_path
      @submission_id = submission_id
    end

    def call
      # Brakeman takes a directory target; pass the directory of the file or the
      # path itself when it is already a directory.
      target = File.directory?(@file_path) ? @file_path : File.dirname(@file_path)

      stdout, stderr, exit_code, duration_ms = subprocess_run(
        ['brakeman', '-f', 'json', '-q', '--no-pager', target]
      )

      # Brakeman exits with a count clamped 0–10 (number of warnings found).
      # Only stderr-based crashes are treated as failures; any numerical exit
      # code is a normal "found issues" result.
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
        stderr: 'brakeman binary not found — install Brakeman on the host to enable security scanning',
        exit_code: nil,
        duration_ms: 0
      )
    end

    private

    def parse_output(stdout)
      data = JSON.parse(stdout)
      issues = []

      Array(data.fetch('warnings', [])).each do |warning|
        # Prefer warning_code (numeric); fall back to warning_type (string).
        short_id  = warning['warning_code'] || warning['warning_type'].to_s.gsub(' ', '')
        rule_id   = "Brakeman/#{short_id}"
        file_path = warning['file'].to_s
        line_start = warning['line'].to_i
        line_start = 1 if line_start < 1
        dedup_key  = Digest::SHA1.hexdigest("#{file_path}|#{line_start}|#{rule_id}")

        issues << {
          source: :linter,
          rule_id: rule_id,
          severity: map_severity(warning['confidence']),
          category: 'security',
          file_path: file_path,
          line_start: line_start,
          line_end: line_start,
          column_start: nil,
          column_end: nil,
          message: warning['message'].to_s,
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
      SEVERITY_MAP.fetch(raw.to_s, 'low')
    end
  end
end
