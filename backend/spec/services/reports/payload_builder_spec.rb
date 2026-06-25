require 'rails_helper'

RSpec.describe Reports::PayloadBuilder do
  let(:sub)    { create(:submission, :completed) }
  let(:review) { create(:review, submission: sub) }
  let(:issue)  { create(:issue, :linter, submission: sub) }

  before { review; issue }

  subject(:payload) { described_class.new(submission: sub).call }

  it 'returns a hash with required keys' do
    expect(payload.keys).to include(:submission, :review, :issues, :generated_at)
  end

  it 'includes the issue' do
    expect(payload[:issues].length).to eq(1)
    expect(payload[:issues].first[:message]).to eq(issue.message)
  end

  it 'returns nil review when no review exists' do
    sub2 = create(:submission, :completed)
    payload2 = described_class.new(submission: sub2).call
    expect(payload2[:review]).to be_nil
  end
end
