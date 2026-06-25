require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:projects).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:email) }

    it 'validates uniqueness of email (case-insensitive)' do
      create(:user, email: 'unique@example.com')
      duplicate = build(:user, email: 'UNIQUE@example.com')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(reviewer: 0, admin: 1) }
  end

  describe 'defaults' do
    it 'defaults to reviewer role' do
      user = build(:user)
      expect(user.role).to eq('reviewer')
    end
  end

  describe 'admin trait' do
    it 'creates an admin user' do
      user = create(:user, :admin)
      expect(user.admin?).to be true
    end
  end

  describe 'JWT' do
    it 'generates a jti on create' do
      user = create(:user)
      expect(user.jti).to be_present
    end
  end
end
