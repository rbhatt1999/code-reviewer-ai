require 'rails_helper'

RSpec.describe Submission, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:analysis_runs).dependent(:destroy) }
    it { is_expected.to have_many(:issues).dependent(:destroy) }
    it { is_expected.to have_one(:review).dependent(:destroy) }
  end

  describe 'enums' do
    it {
      is_expected.to define_enum_for(:kind)
        .with_values(paste: 0, single_file: 1, zip: 2, git_url: 3, github_webhook: 4)
        .with_prefix(:kind)
    }
    it {
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, ingesting: 1, analyzing: 2, reviewing: 3,
                     aggregating: 4, completed: 5, failed: 6)
    }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:blob_path) }
    it { is_expected.to validate_presence_of(:language) }
    it { is_expected.to validate_numericality_of(:size_bytes).is_greater_than_or_equal_to(0) }
  end

  describe '#issues_count' do
    it 'returns the count of associated issues' do
      submission = create(:submission)
      create_list(:issue, 3, :linter, submission: submission)
      expect(submission.issues_count).to eq(3)
    end
  end

  describe 'AASM state machine' do
    let(:submission) { create(:submission, status: :pending) }

    it 'starts in :pending' do
      expect(submission).to be_pending
      expect(Submission.aasm.states.map(&:name)).to include(
        :pending, :ingesting, :analyzing, :reviewing, :aggregating, :completed, :failed
      )
    end

    it 'walks the happy path through every stage' do
      expect { submission.start_ingest! }.to change { submission.reload.status }.from('pending').to('ingesting')
      expect { submission.finish_ingest! }.to change { submission.reload.status }.from('ingesting').to('analyzing')
      expect { submission.finish_analysis! }.to change { submission.reload.status }.from('analyzing').to('reviewing')
      expect { submission.finish_review! }.to change { submission.reload.status }.from('reviewing').to('aggregating')
      expect { submission.complete! }.to change { submission.reload.status }.from('aggregating').to('completed')
    end

    it 'stamps finished_at when the submission completes' do
      submission.update!(status: :aggregating)
      expect { submission.complete! }.to change { submission.reload.finished_at }.from(nil)
    end

    it 'can fail from any non-terminal state and records the error message' do
      submission.update!(status: :analyzing)
      expect { submission.fail!('boom') }.to change { submission.reload.status }.from('analyzing').to('failed')
      expect(submission.error_message).to eq('boom')
      expect(submission.finished_at).to be_present
    end

    it 'refuses an illegal transition' do
      expect { submission.finish_analysis! }.to raise_error(AASM::InvalidTransition)
    end

    it 'refuses to leave a terminal state' do
      submission.update!(status: :completed)
      expect { submission.start_ingest! }.to raise_error(AASM::InvalidTransition)
    end
  end
end
