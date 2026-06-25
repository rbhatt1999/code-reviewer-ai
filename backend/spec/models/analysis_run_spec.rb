require 'rails_helper'

RSpec.describe AnalysisRun, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:submission) }
  end

  describe 'enums' do
    it {
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, running: 1, succeeded: 2, failed: 3, skipped: 4)
    }
  end

  describe 'validations' do
    subject { build(:analysis_run) }

    it { is_expected.to validate_presence_of(:runner) }
    it { is_expected.to validate_uniqueness_of(:runner).scoped_to(:submission_id) }
  end
end
