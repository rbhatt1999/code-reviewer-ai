require 'rails_helper'

RSpec.describe Review, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:submission) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:mode).with_values(hybrid: 0, linter_only: 1) }
  end

  describe 'validations' do
    it {
      is_expected.to validate_numericality_of(:total_issues)
        .only_integer.is_greater_than_or_equal_to(0)
    }
  end
end
