require 'rails_helper'
require 'digest'
require 'tmpdir'

RSpec.describe LLM::ReviewService, type: :service do
  let(:base_url)  { ENV.fetch('DEEPSEEK_BASE_URL', 'https://api.deepseek.com') }
  let(:chat_url)  { "#{base_url}/chat/completions" }

  # Shared factory objects — created per-example inside a Dir.mktmpdir block
  # so each example gets its own tmp directory that is cleaned up after.

  def build_service(tmpdir, language: 'ruby')
    user       = create(:user)
    project    = create(:project, user: user, language: language)
    submission = create(:submission,
                        user: user,
                        project: project,
                        blob_path: tmpdir,
                        language: language,
                        kind: :zip)
    described_class.new(submission: submission)
  end

  def stub_deepseek(body)
    stub_request(:post, chat_url)
      .to_return(
        status: 200,
        body: body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#call' do
    context 'valid JSON with one issue' do
      it 'returns one mapped issue_attr, degraded: false, attempts: 1' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo\n  nil\nend\n")

          stub_deepseek(
            choices: [{ message: {
              content: {
                issues: [
                  {
                    line_start: 1, line_end: 1,
                    severity: 'high', category: 'bug',
                    rule: 'nil-check',
                    message: 'Possible nil',
                    suggestion: nil,
                    confidence: 0.9
                  }
                ]
              }.to_json
            } }]
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs.size).to eq(1)
          attr = result.issues_attrs.first
          expect(attr[:source]).to eq(:llm)
          expect(attr[:rule_id]).to eq('LLM/nil-check')
          expect(attr[:confidence]).to eq(0.9)
          expect(result.degraded).to be(false)
          expect(result.attempts).to eq(1)
        end
      end
    end

    context 'dedup_key formula' do
      it 'uses SHA1 of "rel_path|line_start|rule_id"' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo\n  nil\nend\n")

          stub_deepseek(
            choices: [{ message: {
              content: {
                issues: [
                  {
                    line_start: 1, line_end: 1,
                    severity: 'high', category: 'bug',
                    rule: 'nil-check',
                    message: 'Possible nil',
                    suggestion: nil,
                    confidence: 0.9
                  }
                ]
              }.to_json
            } }]
          )

          result = build_service(tmpdir).call

          expected_key = Digest::SHA1.hexdigest('app.rb|1|LLM/nil-check')
          expect(result.issues_attrs.first[:dedup_key]).to eq(expected_key)
        end
      end
    end

    context 'malformed JSON on every attempt (3 retries)' do
      it 'returns empty issues_attrs, attempts == 3, degraded: true, raises nothing' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_request(:post, chat_url)
            .to_return(
              status: 200,
              body: { choices: [{ message: { content: 'not json' } }] }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
          expect(result.attempts).to eq(3)
          expect(result.degraded).to be(true)
        end
      end
    end

    context 'transport error (Faraday::ConnectionFailed)' do
      it 'returns degraded: true, attempts: 1, raises nothing' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_request(:post, chat_url)
            .to_raise(Faraday::ConnectionFailed.new('refused'))

          result = build_service(tmpdir).call

          expect(result.degraded).to be(true)
          expect(result.attempts).to eq(1)
        end
      end
    end

    context 'file over MAX_BYTES_PER_FILE' do
      it 'skips the file, returns no issues and makes no HTTP call' do
        Dir.mktmpdir do |tmpdir|
          big_file = File.join(tmpdir, 'big.rb')
          File.write(big_file, 'x' * (LLM::ReviewService::MAX_BYTES_PER_FILE + 1))

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
          expect(WebMock).not_to have_requested(:post, chat_url)
        end
      end
    end

    context 'out-of-range line_start (beyond file length)' do
      it 'drops the issue' do
        Dir.mktmpdir do |tmpdir|
          # 3-line file
          File.write(File.join(tmpdir, 'app.rb'), "line1\nline2\nline3\n")

          stub_deepseek(
            choices: [{ message: {
              content: {
                issues: [
                  {
                    line_start: 9999, line_end: 9999,
                    severity: 'high', category: 'bug',
                    rule: 'nil-check',
                    message: 'Out of range',
                    suggestion: nil,
                    confidence: 0.5
                  }
                ]
              }.to_json
            } }]
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
        end
      end
    end

    context 'confidence value > 1.0 (clamping)' do
      it 'clamps confidence to 1.0' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek(
            choices: [{ message: {
              content: {
                issues: [
                  {
                    line_start: 1, line_end: 1,
                    severity: 'low', category: 'code_quality',
                    rule: 'test-rule',
                    message: 'Test issue',
                    suggestion: nil,
                    confidence: 1.5
                  }
                ]
              }.to_json
            } }]
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs.first[:confidence]).to eq(1.0)
        end
      end
    end

    context 'non-numeric confidence (string)' do
      it 'sets confidence to nil' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek(
            choices: [{ message: {
              content: {
                issues: [
                  {
                    line_start: 1, line_end: 1,
                    severity: 'low', category: 'code_quality',
                    rule: 'test-rule',
                    message: 'Test issue',
                    suggestion: nil,
                    confidence: 'high'
                  }
                ]
              }.to_json
            } }]
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs.first[:confidence]).to be_nil
        end
      end
    end
  end
end
