require 'rails_helper'

RSpec.describe SubmissionChannel, type: :channel do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let!(:submission) { create(:submission, user: owner) }

  describe 'when the subscribing user owns the submission' do
    before { stub_connection current_user: owner }

    it 'confirms the subscription' do
      subscribe(submission_id: submission.id)
      expect(subscription).to be_confirmed
    end

    it 'streams for the submission' do
      subscribe(submission_id: submission.id)
      expect(subscription).to have_stream_for(submission)
    end
  end

  describe 'when the submission does not belong to the user' do
    before { stub_connection current_user: other }

    it 'rejects the subscription' do
      subscribe(submission_id: submission.id)
      expect(subscription).to be_rejected
    end
  end

  describe 'when submission_id does not exist' do
    before { stub_connection current_user: owner }

    it 'rejects the subscription' do
      subscribe(submission_id: 0)
      expect(subscription).to be_rejected
    end
  end
end
