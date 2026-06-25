require 'digest'

module Runners
  class Rubocop < Base
    SEVERITY_MAP = {
      'convention' => 'info',
      'refactor' => 'info',
      'warning' => 'low',
      'error' => 'medium',
      'fatal' => 'critical'
    }.freeze

    def initialize(file_path:, submission_id:)
      @file_path     = file_path
      @submission_id = submission_id
    end

    def call
      targets = resolve_targets(@file_path)
      if targets.empty?
        return Result.new(issues_attrs: [], stdout: '', stderr: 'no Ruby files to inspect',
                          exit_code: 0, duration_ms: 0)
      end

      # We pass each file explicitly rather than handing rubocop a directory.
      # The project's .rubocop.yml excludes storage/**/* (where submission
      # blobs live), and that exclusion applies during directory walking but
      # not to explicit file arguments — so enumerating bypasses it without
      # needing a runner-specific config.
      stdout, stderr, exit_code, duration_ms = subprocess_run(
        ['rubocop', '--format', 'json', '--no-color', *targets]
      )

      # Exit code 2 = fatal error (bad args, crash) — treat as failure.
      # Exit code 0 = no offenses, 1 = offenses found (both are normal).
      if exit_code == 2
        return Result.new(
          issues_attrs: [],
          stdout: stdout,
          stderr: stderr,
          exit_code: exit_code,
          duration_ms: duration_ms
        )
      end

      issues_attrs = parse_output(stdout)
      Result.new(
        issues_attrs: issues_attrs,
        stdout: stdout,
        stderr: stderr,
        exit_code: exit_code,
        duration_ms: duration_ms
      )
    end

    private

    def resolve_targets(path)
      # For a directory, enumerate Ruby files so rubocop runs on each as an
      # explicit argument (sidestepping the project .rubocop.yml Exclude).
      # For anything else, pass through — rubocop will error sensibly if the
      # file is missing, and the existing exit-code 2 handling absorbs that.
      return Dir.glob(File.join(path, '**/*.rb')).sort if File.directory?(path)

      [path]
    end

    def parse_output(stdout)
      data = JSON.parse(stdout)
      issues = []

      data.fetch('files', []).each do |file_entry|
        relative_path = file_entry.fetch('path', @file_path)

        file_entry.fetch('offenses', []).each do |offense|
          cop_name   = offense['cop_name'].to_s
          location   = offense.fetch('location', {})
          line_start = location['start_line'] || location['line'] || 1
          line_end   = location['last_line'] || line_start
          rule_id    = "RuboCop/#{cop_name}"
          dedup_key  = Digest::SHA1.hexdigest("#{relative_path}|#{line_start}|#{rule_id}")

          issues << {
            source: :linter,
            rule_id: rule_id,
            severity: map_severity(offense['severity']),
            category: map_category(cop_name),
            file_path: relative_path,
            line_start: line_start,
            line_end: line_end,
            column_start: location['column'],
            column_end: location['last_column'],
            message: offense['message'].to_s,
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
      SEVERITY_MAP.fetch(raw.to_s, 'info')
    end

    def map_category(cop_name)
      namespace = cop_name.to_s.split('/').first.to_s
      case namespace
      when 'Style', 'Layout' then 'style'
      when 'Lint'            then 'bug'
      when 'Performance'     then 'code_quality'
      when 'Security'        then 'security'
      else                        'code_quality'
      end
    end
  end
end
