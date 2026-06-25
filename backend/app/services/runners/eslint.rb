require 'digest'

module Runners
  class Eslint < Base
    RUNNER_NAME = 'eslint'

    SEVERITY_MAP = {
      1 => 'low',
      2 => 'medium'
    }.freeze

    # Absolute path to the bundled flat config placed alongside this runner.
    CONFIG_PATH = File.expand_path('eslint.config.mjs', __dir__)

    def initialize(file_path:, submission_id:)
      @file_path     = file_path
      @submission_id = submission_id
    end

    def call
      stdout, stderr, exit_code, duration_ms = subprocess_run(
        ['eslint', '--config', CONFIG_PATH, '--no-config-lookup', '--format', 'json', @file_path]
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
        stderr: 'eslint binary not found — install ESLint on the host to enable JS/TS linting',
        exit_code: nil,
        duration_ms: 0
      )
    end

    private

    def parse_output(stdout)
      data = JSON.parse(stdout)
      issues = []

      Array(data).each do |file_entry|
        file_path = file_entry['filePath'] || @file_path

        Array(file_entry['messages']).each do |msg|
          rule_id   = "ESLint/#{msg['ruleId']}"
          line_start = msg['line'] || 1
          dedup_key  = Digest::SHA1.hexdigest("#{file_path}|#{line_start}|#{rule_id}")

          issues << {
            source: :linter,
            rule_id: rule_id,
            severity: map_severity(msg['severity']),
            category: map_category(msg['ruleId'].to_s),
            file_path: file_path,
            line_start: line_start,
            line_end: msg['endLine'] || line_start,
            column_start: msg['column'],
            column_end: msg['endColumn'],
            message: msg['message'].to_s,
            suggestion: nil,
            confidence: nil,
            dedup_key: dedup_key
          }
        end
      end

      issues
    rescue JSON::ParserError
      []
    end

    def map_severity(raw)
      SEVERITY_MAP.fetch(raw.to_i, 'low')
    end

    def map_category(rule_id)
      return 'security' if rule_id.start_with?('security')

      case rule_id
      when /\Ano-/, /undefined/, /eqeqeq/, /no-undef/
        'bug'
      when /style/, /prefer-/, /spacing/, /indent/, /quotes/, /semi/
        'style'
      else
        'code_quality'
      end
    end
  end
end
