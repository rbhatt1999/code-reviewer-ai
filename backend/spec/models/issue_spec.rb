require 'rails_helper'

RSpec.describe Issue, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:submission) }
    it { is_expected.to belong_to(:analysis_run).optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:source).with_values(linter: 0, llm: 1, hybrid: 2) }
    it { is_expected.to define_enum_for(:severity).with_values(info: 0, low: 1, medium: 2, high: 3, critical: 4) }
    it {
      is_expected.to define_enum_for(:category)
        .with_values(code_quality: 0, bug: 1, style: 2, security: 3, refactor: 4)
    }
  end

  describe 'validations' do
    subject { build(:issue) }

    it { is_expected.to validate_presence_of(:rule_id) }
    it { is_expected.to validate_presence_of(:file_path) }
    it { is_expected.to validate_presence_of(:message) }
    it { is_expected.to validate_presence_of(:dedup_key) }
    it { is_expected.to validate_uniqueness_of(:dedup_key).scoped_to(:submission_id) }
  end
end
