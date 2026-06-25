require 'rails_helper'

RSpec.describe Runners::Eslint, type: :service do
  let(:file_path)    { '/tmp/test_file.js' }
  let(:submission_id) { 1 }
  let(:runner)        { described_class.new(file_path: file_path, submission_id: submission_id) }

  let(:one_message_json) do
    [
      {
        'filePath' => '/tmp/test_file.js',
        'messages' => [
          {
            'ruleId'     => 'no-unused-vars',
            'severity'   => 2,
            'message'    => "'x' is defined but never used.",
            'line'       => 5,
            'endLine'    => 5,
            'column'     => 7,
            'endColumn'  => 8
          }
        ],
        'errorCount'   => 1,
        'warningCount' => 0
      }
    ].to_json
  end

  let(:warning_style_json) do
    [
      {
        'filePath' => '/tmp/test_file.js',
        'messages' => [
          {
            'ruleId'    => 'prefer-const',
            'severity'  => 1,
            'message'   => "Use 'const' instead of 'let'.",
            'line'      => 2,
            'endLine'   => 2,
            'column'    => 1,
            'endColumn' => 4
          }
        ],
        'errorCount'   => 0,
        'warningCount' => 1
      }
    ].to_json
  end

  describe '#call' do
    context 'when ESLint finds errors (exit code 1)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_message_json, '', double(exitstatus: 1)])
      end

      it 'returns a Result with issues_attrs' do
        result = runner.call
        expect(result.issues_attrs.size).to eq(1)
        issue = result.issues_attrs.first
        expect(issue[:rule_id]).to eq('ESLint/no-unused-vars')
        expect(issue[:severity]).to eq('medium')
        expect(issue[:category]).to eq('bug')
        expect(issue[:line_start]).to eq(5)
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

    context 'when ESLint finds warnings only (exit code 0)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([warning_style_json, '', double(exitstatus: 0)])
      end

      it 'returns issues with severity low and category style' do
        result = runner.call
        expect(result.issues_attrs.size).to eq(1)
        issue = result.issues_attrs.first
        expect(issue[:severity]).to eq('low')
        expect(issue[:category]).to eq('style')
        expect(issue[:rule_id]).to eq('ESLint/prefer-const')
      end
    end

    context 'when ESLint finds no issues (exit code 0)' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['[]', '', double(exitstatus: 0)])
      end

      it 'returns a Result with empty issues_attrs' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to eq(0)
      end
    end

    context 'when ESLint returns invalid JSON' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['not json', '', double(exitstatus: 1)])
      end

      it 'returns empty issues without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
      end
    end

    context 'when ESLint binary is missing (Errno::ENOENT)' do
      before do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'eslint')
      end

      it 'returns an empty Result without raising' do
        result = runner.call
        expect(result.issues_attrs).to be_empty
        expect(result.exit_code).to be_nil
        expect(result.stderr).to include('eslint binary not found')
      end
    end

    context 'severity mapping' do
      it 'maps severity 1 to low' do
        json = [{ 'filePath' => '/f.js', 'messages' => [
          { 'ruleId' => 'no-console', 'severity' => 1, 'message' => 'msg', 'line' => 1 }
        ] }].to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 0)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('low')
      end

      it 'maps severity 2 to medium' do
        json = [{ 'filePath' => '/f.js', 'messages' => [
          { 'ruleId' => 'eqeqeq', 'severity' => 2, 'message' => 'msg', 'line' => 1 }
        ] }].to_json
        allow(Open3).to receive(:capture3).and_return([json, '', double(exitstatus: 1)])
        result = runner.call
        expect(result.issues_attrs.first[:severity]).to eq('medium')
      end
    end

    context 'dedup_key is stable' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return([one_message_json, '', double(exitstatus: 1)])
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
