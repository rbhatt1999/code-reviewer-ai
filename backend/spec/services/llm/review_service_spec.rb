require 'rails_helper'
require 'digest'
require 'tmpdir'

RSpec.describe LLM::ReviewService, type: :service do
  let(:base_url) { ENV.fetch('DEEPSEEK_BASE_URL', 'https://api.deepseek.com') }
  let(:chat_url) { "#{base_url}/chat/completions" }

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

  # A "final answer" DeepSeek response — no tool_calls, just the strict-JSON
  # issues payload as the message content.
  def final_answer(issues)
    {
      choices: [{ message: { content: { issues: issues }.to_json } }]
    }.to_json
  end

  # A "the model wants to read a file" DeepSeek response.
  def tool_call_response(path, call_id: 'call_1')
    {
      choices: [{
        message: {
          content: nil,
          tool_calls: [
            { id: call_id, type: 'function', function: { name: 'read_file', arguments: { path: path }.to_json } }
          ]
        }
      }]
    }.to_json
  end

  def stub_deepseek_sequence(*bodies)
    stub_request(:post, chat_url).to_return(bodies.map { |b| { status: 200, body: b,
                                                                headers: { 'Content-Type' => 'application/json' } } })
  end

  describe '#call' do
    context 'no eligible files in the tree' do
      it 'returns immediately with no issues and makes no HTTP call' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'README.txt'), 'not a ruby file')

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
          expect(result.attempts).to eq(0)
          expect(result.degraded).to be(false)
          expect(WebMock).not_to have_requested(:post, chat_url)
        end
      end
    end

    context 'model answers directly with one issue (no tool call)' do
      it 'returns one mapped issue_attr, degraded: false, attempts: 1' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo\n  nil\nend\n")

          stub_deepseek_sequence(final_answer([
            { file: 'app.rb', line_start: 1, line_end: 1, severity: 'high', category: 'bug',
              rule: 'nil-check', message: 'Possible nil', suggestion: nil, confidence: 0.9 }
          ]))

          result = build_service(tmpdir).call

          expect(result.issues_attrs.size).to eq(1)
          attr = result.issues_attrs.first
          expect(attr[:source]).to eq(:llm)
          expect(attr[:file_path]).to eq('app.rb')
          expect(attr[:rule_id]).to eq('LLM/nil-check')
          expect(attr[:confidence]).to eq(0.9)
          expect(result.degraded).to be(false)
          expect(result.attempts).to eq(1)
          expect(WebMock).to have_requested(:post, chat_url).times(1)
        end
      end
    end

    context 'dedup_key formula' do
      it 'uses SHA1 of "rel_path|line_start|rule_id"' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo\n  nil\nend\n")

          stub_deepseek_sequence(final_answer([
            { file: 'app.rb', line_start: 1, line_end: 1, severity: 'high', category: 'bug',
              rule: 'nil-check', message: 'Possible nil', suggestion: nil, confidence: 0.9 }
          ]))

          result = build_service(tmpdir).call

          expected_key = Digest::SHA1.hexdigest('app.rb|1|LLM/nil-check')
          expect(result.issues_attrs.first[:dedup_key]).to eq(expected_key)
        end
      end
    end

    context 'model requests a file via read_file before answering' do
      it 'executes the tool call and maps the resulting issue' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo\n  nil\nend\n")

          stub_deepseek_sequence(
            tool_call_response('app.rb'),
            final_answer([
              { file: 'app.rb', line_start: 2, line_end: 2, severity: 'medium', category: 'bug',
                rule: 'nil-return', message: 'Returns nil implicitly', suggestion: nil, confidence: 0.7 }
            ])
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs.size).to eq(1)
          expect(result.issues_attrs.first[:file_path]).to eq('app.rb')
          expect(result.degraded).to be(false)
          expect(WebMock).to have_requested(:post, chat_url).times(2)
        end
      end
    end

    context 'model requests a file over MAX_BYTES_PER_FILE via read_file' do
      it 'returns an error to the model instead of the content, and produces no issue for it' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'big.rb'), 'x' * (LLM::ReviewService::MAX_BYTES_PER_FILE + 1))

          stub_deepseek_sequence(
            tool_call_response('big.rb'),
            final_answer([])
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
          expect(result.degraded).to be(false)
          expect(WebMock).to have_requested(:post, chat_url).times(2)
        end
      end
    end

    context 'model requests a file not in the tree' do
      it 'returns an error to the model and does not raise' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek_sequence(
            tool_call_response('../../etc/passwd'),
            final_answer([])
          )

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
          expect(WebMock).to have_requested(:post, chat_url).times(2)
        end
      end
    end

    context 'final answer references a file never in the tree (hallucinated)' do
      it 'drops the issue' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek_sequence(final_answer([
            { file: 'nonexistent.rb', line_start: 1, line_end: 1, severity: 'high', category: 'bug',
              rule: 'nil-check', message: 'Possible nil', suggestion: nil, confidence: 0.9 }
          ]))

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
        end
      end
    end

    context 'malformed JSON on every final-answer attempt (3 retries)' do
      it 'returns empty issues_attrs, attempts == 3, degraded: true, raises nothing' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_request(:post, chat_url)
            .to_return(status: 200, body: { choices: [{ message: { content: 'not json' } }] }.to_json,
                       headers: { 'Content-Type' => 'application/json' })

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

          stub_request(:post, chat_url).to_raise(Faraday::ConnectionFailed.new('refused'))

          result = build_service(tmpdir).call

          expect(result.degraded).to be(true)
          expect(result.attempts).to eq(1)
        end
      end
    end

    context 'out-of-range line_start (beyond file length)' do
      it 'drops the issue' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "line1\nline2\nline3\n")

          stub_deepseek_sequence(final_answer([
            { file: 'app.rb', line_start: 9999, line_end: 9999, severity: 'high', category: 'bug',
              rule: 'nil-check', message: 'Out of range', suggestion: nil, confidence: 0.5 }
          ]))

          result = build_service(tmpdir).call

          expect(result.issues_attrs).to eq([])
        end
      end
    end

    context 'confidence value > 1.0 (clamping)' do
      it 'clamps confidence to 1.0' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek_sequence(final_answer([
            { file: 'app.rb', line_start: 1, line_end: 1, severity: 'low', category: 'code_quality',
              rule: 'test-rule', message: 'Test issue', suggestion: nil, confidence: 1.5 }
          ]))

          result = build_service(tmpdir).call

          expect(result.issues_attrs.first[:confidence]).to eq(1.0)
        end
      end
    end

    context 'non-numeric confidence (string)' do
      it 'sets confidence to nil' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek_sequence(final_answer([
            { file: 'app.rb', line_start: 1, line_end: 1, severity: 'low', category: 'code_quality',
              rule: 'test-rule', message: 'Test issue', suggestion: nil, confidence: 'high' }
          ]))

          result = build_service(tmpdir).call

          expect(result.issues_attrs.first[:confidence]).to be_nil
        end
      end
    end

    context 'pr_diff.json present as a sibling of blob_path (PR webhook submission)' do
      it 'seeds the diff-first prompt and still maps the final answer correctly' do
        Dir.mktmpdir do |parent|
          cloned_dir = File.join(parent, 'cloned')
          FileUtils.mkdir_p(cloned_dir)
          File.write(File.join(cloned_dir, 'app.rb'), "def foo\n  nil\nend\n")
          File.write(File.join(parent, 'pr_diff.json'), [
            { filename: 'app.rb', status: 'modified', additions: 1, deletions: 0,
              patch_numbered: "@@ -1,1 +1,1 @@\n   1| def foo" }
          ].to_json)

          stub_deepseek_sequence(final_answer([
            { file: 'app.rb', line_start: 1, line_end: 1, severity: 'low', category: 'style',
              rule: 'from-diff', message: 'Found via diff-first prompt', suggestion: nil, confidence: 0.5 }
          ]))

          result = build_service(cloned_dir).call

          expect(result.issues_attrs.size).to eq(1)
          expect(WebMock).to have_requested(:post, chat_url)
            .with(body: /Changed files in this pull request/)
        end
      end
    end

    context 'no pr_diff.json (non-PR submission)' do
      it 'seeds the plain file-tree prompt, not the diff-first one' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'app.rb'), "def foo; end\n")

          stub_deepseek_sequence(final_answer([]))

          build_service(tmpdir).call

          expect(WebMock).to have_requested(:post, chat_url)
            .with(body: /File tree/)
          expect(WebMock).not_to have_requested(:post, chat_url)
            .with(body: /Changed files in this pull request/)
        end
      end
    end
  end
end
