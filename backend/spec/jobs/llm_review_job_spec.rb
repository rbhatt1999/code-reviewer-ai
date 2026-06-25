require 'rails_helper'

RSpec.describe LLMReviewJob, type: :job do
  include ActiveJob::TestHelper

  let(:ollama_url) { "#{ENV.fetch('OLLAMA_BASE_URL', 'http://localhost:11434')}/api/chat" }
  let(:user)    { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:submission) do
    create(:submission, project: project, user: user,
                        status: :reviewing, blob_path: tmpdir, language: 'ruby')
  end

  # Build a real tmpdir with one .rb file so ReviewService can enumerate it.
  let(:tmpdir) do
    dir = Dir.mktmpdir('llm_review_job_spec')
    File.write(File.join(dir, 'sample.rb'), <<~RUBY)
      # frozen_string_literal: true

      def hello
        puts 'hello world'
      end
    RUBY
    dir
  end

  after { FileUtils.rm_rf(tmpdir) }

  # Builds a valid Ollama HTTP response body for one issue.
  def ollama_body_with_one_issue
    content = {
      'issues' => [
        {
          'line_start' => 1,
          'line_end' => 1,
          'severity' => 'low',
          'category' => 'style',
          'rule' => 'MagicComment',
          'message' => 'Consider adding a magic comment.',
          'suggestion' => nil,
          'confidence' => 0.8
        }
      ]
    }.to_json
    # OllamaClient does: JSON.parse(body).dig('message', 'content').to_s
    # ReviewService does: JSON.parse(that_string)
    # So content must be a JSON *string*, not a Hash.
    { message: { content: content } }.to_json
  end

  # Builds a body whose content is not valid JSON (triggers MAX_JSON_ATTEMPTS retries).
  def ollama_body_malformed
    { message: { content: 'not-json' } }.to_json
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------
  describe 'guard — submission not found' do
    it 'returns early without raising' do
      allow(LLM::ReviewService).to receive(:new)
      expect { described_class.perform_now(999_999) }.not_to raise_error
      expect(LLM::ReviewService).not_to have_received(:new)
    end
  end

  describe 'guard — wrong state' do
    it 'returns early when submission is not reviewing' do
      submission.update!(status: :aggregating)
      allow(LLM::ReviewService).to receive(:new)
      expect { described_class.perform_now(submission.id) }.not_to(change do
        submission.reload.status
      end)
      expect(LLM::ReviewService).not_to have_received(:new)
    end
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------
  describe 'happy path — LLM returns one issue' do
    before do
      stub_request(:post, ollama_url)
        .to_return(status: 200, body: ollama_body_with_one_issue,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'transitions submission to aggregating' do
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq('aggregating')
    end

    it 'persists one llm-sourced issue' do
      described_class.perform_now(submission.id)
      expect(submission.issues.where(source: :llm).count).to eq(1)
    end

    it 'stores llm_attempts on the review record' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.llm_attempts).to be >= 1
    end

    it 'enqueues AggregateReportJob' do
      expect do
        described_class.perform_now(submission.id)
      end.to have_enqueued_job(AggregateReportJob).with(submission.id)
    end
  end

  # -------------------------------------------------------------------------
  # Graceful degradation — malformed JSON (all 3 attempts exhaust)
  # -------------------------------------------------------------------------
  describe 'graceful degradation — malformed JSON response' do
    before do
      stub_request(:post, ollama_url)
        .to_return(status: 200, body: ollama_body_malformed,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'still transitions to aggregating (not failed)' do
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq('aggregating')
    end

    it 'creates zero llm issues' do
      described_class.perform_now(submission.id)
      expect(submission.issues.where(source: :llm).count).to eq(0)
    end

    it 'does not mark submission failed' do
      described_class.perform_now(submission.id)
      expect(submission.reload.failed?).to be false
    end

    it 'records 3 llm_attempts (MAX_JSON_ATTEMPTS exhausted)' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.llm_attempts).to eq(3)
    end
  end

  # -------------------------------------------------------------------------
  # Graceful degradation — transport error (503)
  # -------------------------------------------------------------------------
  describe 'graceful degradation — transport error (503)' do
    before do
      stub_request(:post, ollama_url)
        .to_return(status: 503, body: 'Service Unavailable',
                   headers: { 'Content-Type' => 'text/plain' })
    end

    it 'still transitions to aggregating' do
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq('aggregating')
    end

    it 'does not mark submission failed' do
      described_class.perform_now(submission.id)
      expect(submission.reload.failed?).to be false
    end
  end

  # -------------------------------------------------------------------------
  # Exception path — finish_review! raises
  # -------------------------------------------------------------------------
  describe 'exception path — finish_review! raises' do
    before do
      stub_request(:post, ollama_url)
        .to_return(status: 200, body: ollama_body_with_one_issue,
                   headers: { 'Content-Type' => 'application/json' })

      # Ensure the job retrieves our submission instance so we can stub it.
      allow(Submission).to receive(:find_by).and_call_original
      allow(Submission).to receive(:find_by).with(id: submission.id).and_return(submission)
      allow(submission).to receive(:finish_review!).and_raise(StandardError, 'state error')
    end

    it 're-raises the error' do
      expect { described_class.perform_now(submission.id) }.to raise_error(StandardError, 'state error')
    end

    it 'transitions submission to failed' do
      begin
        described_class.perform_now(submission.id)
      rescue StandardError
        nil
      end
      expect(submission.reload.status).to eq('failed')
    end
  end
end
