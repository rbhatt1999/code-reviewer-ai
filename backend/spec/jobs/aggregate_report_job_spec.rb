require 'rails_helper'

RSpec.describe AggregateReportJob, type: :job do
  include ActiveJob::TestHelper

  let!(:submission) { create(:submission, status: :aggregating) }

  describe 'guard clause' do
    it 'returns early when submission is missing' do
      expect { described_class.perform_now(0) }.not_to raise_error
    end

    it 'returns early when submission is not aggregating' do
      submission.update!(status: :reviewing)
      expect { described_class.perform_now(submission.id) }.not_to(change do
        submission.reload.status
      end)
    end
  end

  describe 'happy path — no issues' do
    it 'creates a linter_only Review with total_issues 0 and transitions to completed' do
      described_class.perform_now(submission.id)

      submission.reload
      expect(submission.status).to eq('completed')
      expect(submission.review).to be_present
      expect(submission.review.mode).to eq('linter_only')
      expect(submission.review.total_issues).to eq(0)
    end

    it 'broadcasts a completed status event on SubmissionChannel' do
      expect do
        described_class.perform_now(submission.id)
      end.to have_broadcasted_to(submission).from_channel(SubmissionChannel)
                                            .with(hash_including(status: 'completed', submission_id: submission.id,
                                                                 progress: 100))
    end
  end

  describe 'happy path — with linter issues' do
    before { create_list(:issue, 3, :linter, submission: submission) }

    it 'counts persisted issues into total_issues' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.total_issues).to eq(3)
    end

    it 'sets mode to linter_only when all issues are linter source' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.mode).to eq('linter_only')
    end
  end

  describe 'idempotency — review already exists' do
    before { create(:review, submission: submission, mode: :linter_only, total_issues: 0) }

    it 'does not raise RecordInvalid and still completes' do
      expect { described_class.perform_now(submission.id) }.not_to raise_error
      expect(submission.reload.status).to eq('completed')
    end
  end

  describe 'exception path' do
    before do
      allow(submission).to receive(:complete!).and_raise(RuntimeError, 'complete exploded')
      allow(Submission).to receive(:find_by).and_return(submission)
    end

    it 'lands the submission in failed and re-raises' do
      expect { described_class.perform_now(submission.id) }.to raise_error(RuntimeError, 'complete exploded')

      submission.reload
      expect(submission.status).to eq('failed')
      expect(submission.error_message).to eq('complete exploded')
    end

    it 'broadcasts a failed status event' do
      expect do
        described_class.perform_now(submission.id)
      end.to raise_error(RuntimeError).and have_broadcasted_to(submission).from_channel(SubmissionChannel)
                                                                          .with(hash_including(status: 'failed'))
    end
  end

  describe 'mode → hybrid when LLM issue exists' do
    before do
      create(:issue, :linter, submission: submission,
                              file_path: 'app/models/user.rb', line_start: 1, line_end: 1,
                              category: :style, dedup_key: 'linter-style-user')
      create(:issue, :llm, submission: submission,
                           file_path: 'app/models/post.rb', line_start: 10, line_end: 12,
                           category: :bug, dedup_key: 'llm-bug-post')
    end

    it 'sets mode to hybrid when an LLM issue is present' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.mode).to eq('hybrid')
    end
  end

  describe 'cross-source merge' do
    before do
      create(:issue, source: :linter, file_path: 'a.rb', line_start: 5, line_end: 5,
                     category: :bug, submission: submission, dedup_key: 'key-linter',
                     rule_id: 'Lint/Bug', message: 'linter bug message', severity: :medium)
      create(:issue, source: :llm, file_path: 'a.rb', line_start: 5, line_end: 6,
                     category: :bug, submission: submission, dedup_key: 'key-llm',
                     rule_id: 'LLM/Bug', message: 'llm bug message with more detail here', severity: :high)
    end

    it 'collapses linter + LLM issues at same file/line/category into one hybrid issue' do
      described_class.perform_now(submission.id)
      expect(submission.reload.issues.count).to eq(1)
    end

    it 'marks the surviving issue as hybrid source' do
      described_class.perform_now(submission.id)
      expect(submission.reload.issues.first.source).to eq('hybrid')
    end

    it 'sets total_issues to 1 after merge' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.total_issues).to eq(1)
    end
  end

  describe 'scores — per-severity counts in Review.scores' do
    before do
      create(:issue, :linter, submission: submission,
                              file_path: 'app/models/user.rb', line_start: 1, line_end: 1,
                              category: :style, severity: :medium, dedup_key: 'linter-medium-user')
      create(:issue, :llm, submission: submission,
                           file_path: 'app/models/post.rb', line_start: 20, line_end: 21,
                           category: :bug, severity: :high, dedup_key: 'llm-high-post')
    end

    it 'stores a Hash in Review.scores' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.scores).to be_a(Hash)
    end

    it 'records a count of 1 for medium severity' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.scores['medium']).to eq(1)
    end

    it 'records a count of 1 for high severity' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.scores['high']).to eq(1)
    end

    it 'records a total of 2' do
      described_class.perform_now(submission.id)
      expect(submission.reload.review.scores['total']).to eq(2)
    end
  end
end
