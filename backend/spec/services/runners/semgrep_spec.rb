require 'rails_helper'

RSpec.describe Runners::Semgrep, type: :service do
  let(:file_path)    { '/tmp/test_code.py' }
  let(:submission_id) { 1 }
  let(:runner)        { described_class.new(file_path: file_path, submission_id: submission_id) }

  let(:one_result_json) do
    {
      'results' => [
        {
          'check_id' => 'python.security.audit.exec-detected',
          'path'     => '/tmp/test_code.py',
          'start'    => { 'line' => 12, 'col' => 1 },
          'end'      => { 'line' => 12, 'col' => 30 },
          'extra'    => {
            'message'  => 'Use of exec() detected',
            'severity' => 'ERROR',
            'metadata' => { 'category' => 'security' }
          }
        }
      ],
      'errors' => []
    }.to_json
  end

  let(:warning_result_json) do
    {
      'results' => [
        {
          'check_id' => 'python.lang.best-practice.string-concat',
          'path'     => '/tmp/test_code.py',
          'start'    => { 'line' => 4, 'col' => 5 },
          'end'      => { 'line' => 4, 'col' => 20 },
          'extra'    => {
            'message'  => 'Avoid string concatenation in loops',
            'severity' => 'WARNING',
            'metadata' => { 'category' => 'performance' }
          }
        }
      ],
      'errors' => []
    }.to_json
  end

  describe '#call' do
    context 'when Semgrep finds results (exit code 1)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_result_json, '', double(exitstatus: 1)])
      end

      it 'returns a Result with issues_attrs' do
        result = runner.call
        expect(result.issues_attrs.size).to eq(1)
        issue = result.issues_attrs.first
        expect(issue[:rule_id]).to eq('python.security.audit.exec-detected')
        expect(issue[:severity]).to eq('high')
        expect(issue[:category]).to eq('security')
        expect(issue[:line_start]).to eq(12)
        expect(issue[:line_end]).to eq(12)
        expect(issue[:source]).to eq(:linter)
        expect(issue[:suggestion]).to be_nil
        expect(issue[:confidence]).to be_nil
        expect(issue[:dedup_key]).to be_present
      end

      it 'sets the correct exit_code' do
        result = runner.call
        expect(result.exit_code).to eq(1)
      end
    end

    context 'when Semgrep finds no results (exit code 0)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([{ 'results' => [], 'errors' => [] }.to_json, '', double(exitstatus: 0)])
      end

      it 'returns empty issues_attrs' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to eq(0)
      end
    end

    context 'when Semgrep returns invalid JSON' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['not json', '', double(exitstatus: 1)])
      end

      it 'returns empty issues without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
      end
    end

    context 'when Semgrep binary is missing (Errno::ENOENT)' do
      before do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'semgrep')
      end

      it 'returns an empty Result without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to be_nil
        expect(result.stderr).to include('semgrep binary not found')
      end
    end

    context 'severity mapping' do
      it 'maps INFO to info' do
        json = { 'results' => [
          { 'check_id' => 'rule', 'path' => '/f.py',
            'start' => { 'line' => 1, 'col' => 1 }, 'end' => { 'line' => 1, 'col' => 5 },
            'extra' => { 'message' => 'msg', 'severity' => 'INFO', 'metadata' => {} } }
        ] }.to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 0)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('info')
      end

      it 'maps WARNING to medium' do
        allow(Open3).to receive(:capture3).and_return([warning_result_json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('medium')
      end

      it 'maps ERROR to high' do
        allow(Open3).to receive(:capture3).and_return([one_result_json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('high')
      end
    end

    context 'category mapping' do
      it 'maps security metadata category to security' do
        allow(Open3).to receive(:capture3).and_return([one_result_json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:category]).to eq('security')
      end

      it 'maps performance metadata category to code_quality' do
        allow(Open3).to receive(:capture3).and_return([warning_result_json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:category]).to eq('code_quality')
      end

      it 'maps security in check_id path to security' do
        json = { 'results' => [
          { 'check_id' => 'ruby.security.brakeman.check-xss',
            'path' => '/f.rb',
            'start' => { 'line' => 1, 'col' => 1 }, 'end' => { 'line' => 1, 'col' => 5 },
            'extra' => { 'message' => 'XSS', 'severity' => 'ERROR', 'metadata' => {} } }
        ] }.to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:category]).to eq('security')
      end
    end

    context 'dedup_key is stable' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_result_json, '', double(exitstatus: 1)])
      end

      it 'computes dedup_key as SHA1 of file|line|check_id' do
        result = runner.call
        issue = result.issues_attrs.first
        expected = Digest::SHA1.hexdigest("#{issue[:file_path]}|#{issue[:line_start]}|#{issue[:rule_id]}")
        expect(issue[:dedup_key]).to eq(expected)
      end
    end
  end
end
