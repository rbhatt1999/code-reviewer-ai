require 'rails_helper'

RSpec.describe Runners::Bandit, type: :service do
  let(:file_path)    { '/tmp/test_script.py' }
  let(:submission_id) { 1 }
  let(:runner)        { described_class.new(file_path: file_path, submission_id: submission_id) }

  let(:one_result_json) do
    {
      'results' => [
        {
          'test_id'        => 'B105',
          'test_name'      => 'hardcoded_password_string',
          'issue_text'     => 'Possible hardcoded password: "password"',
          'filename'       => '/tmp/test_script.py',
          'line_number'    => 7,
          'line_range'     => [7, 8],
          'issue_severity' => 'HIGH',
          'issue_confidence' => 'MEDIUM'
        }
      ],
      'errors' => []
    }.to_json
  end

  let(:low_severity_json) do
    {
      'results' => [
        {
          'test_id'        => 'B311',
          'test_name'      => 'standard_pseudo_random_generators',
          'issue_text'     => 'Standard pseudo-random generators are not suitable for security purposes.',
          'filename'       => '/tmp/test_script.py',
          'line_number'    => 3,
          'line_range'     => [3],
          'issue_severity' => 'LOW',
          'issue_confidence' => 'HIGH'
        }
      ],
      'errors' => []
    }.to_json
  end

  describe '#call' do
    context 'when Bandit finds issues (exit code 1)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_result_json, '', double(exitstatus: 1)])
      end

      it 'returns a Result with issues_attrs' do
        result = runner.call
        expect(result.issues_attrs.size).to eq(1)
        issue = result.issues_attrs.first
        expect(issue[:rule_id]).to eq('Bandit/B105')
        expect(issue[:severity]).to eq('high')
        expect(issue[:category]).to eq('security')
        expect(issue[:line_start]).to eq(7)
        expect(issue[:line_end]).to eq(8)
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

    context 'when Bandit finds no issues (exit code 0)' do
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

    context 'when Bandit returns invalid JSON' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['not json', '', double(exitstatus: 1)])
      end

      it 'returns empty issues without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
      end
    end

    context 'when Bandit binary is missing (Errno::ENOENT)' do
      before do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'bandit')
      end

      it 'returns an empty Result without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to be_nil
        expect(result.stderr).to include('bandit binary not found')
      end
    end

    context 'severity mapping' do
      it 'maps LOW to low' do
        allow(Open3).to receive(:capture3).and_return([low_severity_json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('low')
      end

      it 'maps MEDIUM to medium' do
        json = { 'results' => [
          { 'test_id' => 'B201', 'issue_text' => 'msg', 'filename' => 'f.py',
            'line_number' => 1, 'line_range' => [1], 'issue_severity' => 'MEDIUM' }
        ] }.to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('medium')
      end

      it 'maps HIGH to high' do
        allow(Open3).to receive(:capture3).and_return([one_result_json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('high')
      end
    end

    context 'all results use category security' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_result_json, '', double(exitstatus: 1)])
      end

      it 'always sets category to security' do
        result = runner.call
        expect(result.issues_attrs.first[:category]).to eq('security')
      end
    end

    context 'dedup_key is stable' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_result_json, '', double(exitstatus: 1)])
      end

      it 'computes dedup_key as SHA1 of file|line|rule_id' do
        result = runner.call
        issue = result.issues_attrs.first
        expected = Digest::SHA1.hexdigest("#{issue[:file_path]}|#{issue[:line_start]}|#{issue[:rule_id]}")
        expect(issue[:dedup_key]).to eq(expected)
      end
    end
  end
end
