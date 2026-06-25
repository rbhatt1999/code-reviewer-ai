require 'rails_helper'

# End-to-end pipeline test: HTTP POST → IngestJob → StaticAnalysisJob →
# LLMReviewJob (Ollama stubbed via WebMock) → AggregateReportJob → completed.
# Sidekiq::Testing.inline! makes perform_later run synchronously so the whole
# chain executes inside the request.
#
# WebMock note: rails_helper sets allow_localhost: true, which means an
# unstubbed call to localhost SUCCEEDS (hits real Ollama if running). We
# therefore add an EXPLICIT stub pinned to the Ollama chat endpoint so tests
# are deterministic whether or not a real Ollama server is present.
RSpec.describe 'Submissions async pipeline (inline)', type: :request do
  include ActiveJob::TestHelper

  let!(:user) { create(:user) }
  let!(:project) { create(:project, user: user) }
  let(:headers) { auth_headers_for(user) }

  let(:rubocop_one_offense_json) do
    {
      'files' => [
        {
          'path' => 'test_file.rb',
          'offenses' => [
            {
              'severity' => 'convention',
              'message' => "Prefer single-quoted strings when you don't need interpolation.",
              'cop_name' => 'Style/StringLiterals',
              'location' => { 'start_line' => 1, 'last_line' => 1, 'column' => 1, 'last_column' => 10 }
            }
          ]
        }
      ],
      'summary' => { 'offense_count' => 1 }
    }.to_json
  end

  let(:ollama_url) { "#{ENV.fetch('OLLAMA_BASE_URL', 'http://localhost:11434')}/api/chat" }

  # ── linter_only context (LLM returns zero issues) ─────────────────────────
  context 'when LLM returns no issues (linter_only path)' do
    before do
      status_double = instance_double(Process::Status, exitstatus: 1)
      allow(Open3).to receive(:capture3).and_return([rubocop_one_offense_json, '', status_double])

      # Stub Ollama so tests are deterministic without a real server.
      # Body matches OllamaClient#chat: JSON.parse(resp.body).dig('message','content')
      # → '{"issues":[]}' → valid_shape? true → zero LLM issues persisted.
      stub_request(:post, ollama_url)
        .to_return(
          status: 200,
          body: { message: { content: '{"issues":[]}' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'drives the full 4-job chain to completed with one Issue and a linter_only Review' do
      ruby_content = "x = \"hello\"\nputs x\n"
      file = Rack::Test::UploadedFile.new(
        StringIO.new(ruby_content), 'text/plain', original_filename: 'test_file.rb'
      )

      # Run all jobs inline — the chain fires as perform_later calls execute immediately.
      perform_enqueued_jobs do
        post "/api/v1/projects/#{project.id}/submissions",
             params: { submission: { kind: 'single_file', file: file } },
             headers: headers

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        # The response is captured before inline jobs run; the initial status is pending.
        expect(body['submission']['status']).to eq('pending')
      end

      submission = Submission.last
      expect(submission.status).to eq('completed')
      expect(submission.finished_at).to be_present

      expect(submission.issues.count).to eq(1)
      issue = submission.issues.first
      expect(issue.rule_id).to eq('RuboCop/Style/StringLiterals')
      expect(issue.source).to eq('linter')

      review = submission.review
      expect(review).to be_present
      expect(review.mode).to eq('linter_only')
      expect(review.total_issues).to eq(1)
    end
  end

  # ── hybrid context (LLM returns one issue overlapping the linter offense) ──
  # AggregateReportJob merges issues that share [canon_path, category] and have
  # overlapping line ranges.  The linter issue is:
  #   file_path: 'test_file.rb', category: 'style' (Style/* → 'style'), line 1.
  # The LLM issue below matches all three criteria so the merge collapses 2→1
  # and the surviving issue gets source: 'hybrid'.
  context 'when LLM returns one issue overlapping the linter offense (hybrid path)' do
    let(:llm_issue_json) do
      {
        'issues' => [
          {
            'line_start' => 1,
            'line_end' => 1,
            'severity' => 'medium',
            'category' => 'style',
            'rule' => 'PreferSingleQuotes',
            'message' => 'Use single-quoted strings to avoid unnecessary escape overhead.',
            'suggestion' => "x = 'hello'",
            'confidence' => 0.9
          }
        ]
      }.to_json
    end

    before do
      status_double = instance_double(Process::Status, exitstatus: 1)
      allow(Open3).to receive(:capture3).and_return([rubocop_one_offense_json, '', status_double])

      stub_request(:post, ollama_url)
        .to_return(
          status: 200,
          body: { message: { content: llm_issue_json } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'merges overlapping linter + LLM issues into one hybrid Issue and a hybrid Review' do
      ruby_content = "x = \"hello\"\nputs x\n"
      file = Rack::Test::UploadedFile.new(
        StringIO.new(ruby_content), 'text/plain', original_filename: 'test_file.rb'
      )

      perform_enqueued_jobs do
        post "/api/v1/projects/#{project.id}/submissions",
             params: { submission: { kind: 'single_file', file: file } },
             headers: headers

        expect(response).to have_http_status(:created)
      end

      submission = Submission.last
      expect(submission.status).to eq('completed')

      # Two issues entered → merge collapses them to one hybrid issue.
      expect(submission.issues.count).to eq(1)
      merged = submission.issues.first
      expect(merged.source).to eq('hybrid')

      review = submission.review
      expect(review).to be_present
      expect(review.mode).to eq('hybrid')
      expect(review.total_issues).to eq(1)
    end
  end
end
