require 'rails_helper'

RSpec.describe Runners::Rubocop, type: :service do
  let(:file_path) { '/tmp/test_file.rb' }
  let(:submission_id) { 1 }
  let(:runner) { described_class.new(file_path: file_path, submission_id: submission_id) }

  let(:one_offense_json) do
    {
      'files' => [
        {
          'path' => 'test_file.rb',
          'offenses' => [
            {
              'severity' => 'convention',
              'message' => 'Prefer single-quoted strings.',
              'cop_name' => 'Style/StringLiterals',
              'location' => {
                'start_line' => 3,
                'last_line' => 3,
                'column' => 5,
                'last_column' => 20
              }
            }
          ]
        }
      ],
      'summary' => { 'offense_count' => 1 }
    }.to_json
  end

  let(:fatal_stderr) { 'rubocop: command not found' }

  describe 'target resolution' do
    it 'enumerates Ruby files when given a directory (sidesteps storage Exclude)' do
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, 'a.rb'), '')
        File.write(File.join(tmp, 'b.rb'), '')
        File.write(File.join(tmp, 'README.md'), 'not Ruby')

        captured_cmd = nil
        allow(Open3).to receive(:capture3) do |*cmd, **_opts|
          captured_cmd = cmd
          ['{"files":[],"summary":{"offense_count":0}}', '', instance_double(Process::Status, exitstatus: 0)]
        end

        described_class.new(file_path: tmp, submission_id: 1).call

        rb_files = captured_cmd.select { |s| s.is_a?(String) && s.end_with?('.rb') }
        expect(rb_files.map { |p| File.basename(p) }).to contain_exactly('a.rb', 'b.rb')
      end
    end

    it 'short-circuits when a directory has no Ruby files' do
      Dir.mktmpdir do |tmp|
        File.write(File.join(tmp, 'README.md'), 'not Ruby')
        expect(Open3).not_to receive(:capture3)

        result = described_class.new(file_path: tmp, submission_id: 1).call
        expect(result.issues_attrs).to be_empty
        expect(result.stderr).to match(/no Ruby files/)
      end
    end
  end

  describe '#call' do
    context 'when rubocop finds offenses (exit code 1)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_offense_json, '', double(exitstatus: 1)])
      end

      it 'returns a Result with issues_attrs' do
        result = runner.call
        expect(result.issues_attrs.size).to eq(1)
        issue = result.issues_attrs.first
        expect(issue[:rule_id]).to eq('RuboCop/Style/StringLiterals')
        expect(issue[:severity]).to eq('info')
        expect(issue[:category]).to eq('style')
        expect(issue[:line_start]).to eq(3)
        expect(issue[:source]).to eq(:linter)
        expect(issue[:dedup_key]).to be_present
      end

      it 'sets the correct exit_code' do
        result = runner.call
        expect(result.exit_code).to eq(1)
      end
    end

    context 'when rubocop finds no offenses (exit code 0)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['{"files":[],"summary":{"offense_count":0}}', '', double(exitstatus: 0)])
      end

      it 'returns a Result with empty issues_attrs' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to eq(0)
      end
    end

    context 'when rubocop crashes (exit code 2)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['', fatal_stderr, double(exitstatus: 2)])
      end

      it 'returns an empty result without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to eq(2)
      end
    end

    context 'when rubocop returns invalid JSON' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['not json at all', '', double(exitstatus: 1)])
      end

      it 'returns empty issues without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
      end
    end

    context 'severity and category mapping' do
      {
        'convention' => ['info', 'Style/StringLiterals', 'style'],
        'refactor' => ['info', 'Refactor/SomeCop', 'code_quality'],
        'warning' => ['low', 'Lint/UnusedVariable', 'bug'],
        'error' => ['medium',   'Performance/Count',      'code_quality'],
        'fatal' => ['critical', 'Security/Open',          'security']
      }.each do |sev, (expected_sev, cop_name, expected_cat)|
        it "maps severity #{sev.inspect} to #{expected_sev.inspect} with category #{expected_cat.inspect}" do
          json = {
            'files' => [{
              'path' => 'file.rb',
              'offenses' => [{
                'severity' => sev,
                'message' => 'msg',
                'cop_name' => cop_name,
                'location' => { 'start_line' => 1, 'last_line' => 1, 'column' => 1 }
              }]
            }],
            'summary' => { 'offense_count' => 1 }
          }.to_json

          allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 1)])

          result = runner.call
          issue  = result.issues_attrs.first
          expect(issue[:severity]).to eq(expected_sev)
          expect(issue[:category]).to eq(expected_cat)
        end
      end
    end
  end
end
