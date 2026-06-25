require 'rails_helper'

RSpec.describe Project, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:submissions).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:project) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:language) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id) }
    it {
      is_expected.to validate_inclusion_of(:language)
        .in_array(%w[ruby python javascript typescript java])
    }
  end

  describe 'defaults' do
    it 'sets default_branch to main' do
      project = build(:project, default_branch: nil)
      project.valid?
      expect(project.default_branch).to eq('main')
    end
  end

  describe '#submissions_count' do
    it 'returns the number of submissions' do
      project = create(:project)
      create_list(:submission, 2, project: project, user: project.user)
      expect(project.submissions_count).to eq(2)
    end
  end
end
