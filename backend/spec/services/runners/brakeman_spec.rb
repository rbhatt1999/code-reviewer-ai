require 'rails_helper'

RSpec.describe Runners::Brakeman, type: :service do
  let(:file_path)    { '/tmp/test_app' }
  let(:submission_id) { 1 }
  let(:runner)        { described_class.new(file_path: file_path, submission_id: submission_id) }

  let(:one_warning_json) do
    {
      'warnings' => [
        {
          'warning_type' => 'SQL Injection',
          'warning_code' => 0,
          'message'      => 'Possible SQL injection',
          'file'         => 'app/models/user.rb',
          'line'         => 10,
          'confidence'   => 'High'
        }
      ],
      'ignored_warnings' => [],
      'errors' => []
    }.to_json
  end

  let(:medium_warning_json) do
    {
      'warnings' => [
        {
          'warning_type' => 'CrossSiteScripting',
          'warning_code' => 2,
          'message'      => 'Unescaped user input in view',
          'file'         => 'app/views/index.html.erb',
          'line'         => 5,
          'confidence'   => 'Medium'
        }
      ],
      'ignored_warnings' => [],
      'errors' => []
    }.to_json
  end

  describe '#call' do
    context 'when Brakeman finds warnings (exit code 3)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_warning_json, '', double(exitstatus: 3)])
      end

      it 'returns a Result with issues_attrs' do
        result = runner.call
        expect(result.issues_attrs.size).to eq(1)
        issue = result.issues_attrs.first
        expect(issue[:rule_id]).to eq('Brakeman/0')
        expect(issue[:severity]).to eq('high')
        expect(issue[:category]).to eq('security')
        expect(issue[:line_start]).to eq(10)
        expect(issue[:source]).to eq(:linter)
        expect(issue[:suggestion]).to be_nil
        expect(issue[:confidence]).to be_nil
        expect(issue[:dedup_key]).to be_present
      end

      it 'sets the correct exit_code' do
        result = runner.call
        expect(result.exit_code).to eq(3)
      end
    end

    context 'when Brakeman finds warnings (exit code 0 — zero issues found path)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([{ 'warnings' => [], 'ignored_warnings' => [], 'errors' => [] }.to_json,
                       '', double(exitstatus: 0)])
      end

      it 'returns empty issues_attrs' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to eq(0)
      end
    end

    context 'when Brakeman returns invalid JSON' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['not json', '', double(exitstatus: 1)])
      end

      it 'returns empty issues without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
      end
    end

    context 'when Brakeman binary is missing (Errno::ENOENT)' do
      before do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'brakeman')
      end

      it 'returns an empty Result without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to be_nil
        expect(result.stderr).to include('brakeman binary not found')
      end
    end

    context 'severity mapping' do
      it 'maps Weak to low' do
        json = { 'warnings' => [
          { 'warning_code' => 1, 'message' => 'msg', 'file' => 'f.rb',
            'line' => 1, 'confidence' => 'Weak' }
        ] }.to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('low')
      end

      it 'maps Medium to medium' do
        json = { 'warnings' => [
          { 'warning_code' => 2, 'message' => 'msg', 'file' => 'f.rb',
            'line' => 1, 'confidence' => 'Medium' }
        ] }.to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('medium')
      end

      it 'maps High to high' do
        allow(Open3).to receive(:capture3)
          .and_return([one_warning_json, '', double(exitstatus: 3)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('high')
      end
    end

    context 'all warnings use category security' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_warning_json, '', double(exitstatus: 3)])
      end

      it 'always sets category to security' do
        result = runner.call
        expect(result.issues_attrs.first[:category]).to eq('security')
      end
    end

    context 'dedup_key is stable' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_warning_json, '', double(exitstatus: 3)])
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
