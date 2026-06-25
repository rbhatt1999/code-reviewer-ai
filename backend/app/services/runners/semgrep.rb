require 'digest'

module Runners
  class Semgrep < Base
    RUNNER_NAME = 'semgrep'

    SEVERITY_MAP = {
      'INFO'    => 'info',
      'WARNING' => 'medium',
      'ERROR'   => 'high'
    }.freeze

    def initialize(file_path:, submission_id:)
      @file_path     = file_path
      @submission_id = submission_id
    end

    def call
      stdout, stderr, exit_code, duration_ms = subprocess_run(
        ['semgrep', '--json', '--quiet', '--config', 'auto', @file_path]
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
        stderr: 'semgrep binary not found — install Semgrep on the host to enable multi-language scanning',
        exit_code: nil,
        duration_ms: 0
      )
    end

    private

    def parse_output(stdout)
      data = JSON.parse(stdout)
      issues = []

      Array(data.fetch('results', [])).each do |finding|
        check_id   = finding['check_id'].to_s
        file_path  = finding['path'].to_s
        start_info = finding.fetch('start', {})
        end_info   = finding.fetch('end', {})
        extra      = finding.fetch('extra', {})
        line_start = start_info['line'].to_i
        line_start = 1 if line_start < 1
        dedup_key  = Digest::SHA1.hexdigest("#{file_path}|#{line_start}|#{check_id}")

        issues << {
          source: :linter,
          rule_id: check_id,
          severity: map_severity(extra['severity']),
          category: map_category(check_id, extra.fetch('metadata', {})),
          file_path: file_path,
          line_start: line_start,
          line_end: end_info['line'].to_i.then { |l| l < line_start ? line_start : l },
          column_start: start_info['col'],
          column_end: end_info['col'],
          message: extra['message'].to_s,
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
      SEVERITY_MAP.fetch(raw.to_s.upcase, 'info')
    end

    def map_category(check_id, metadata)
      meta_category = metadata['category'].to_s
      return 'security' if meta_category == 'security' || check_id.include?('security')
      return 'code_quality' if meta_category == 'performance'

      'code_quality'
    end
  end
end
