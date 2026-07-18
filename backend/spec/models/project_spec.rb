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

  describe 'webhook_secret generation' do
    it 'auto-generates a secret on create when none is given' do
      project = create(:project)
      expect(project.webhook_secret).to be_present
      expect(project.webhook_secret.length).to be >= 32
    end

    it 'does not overwrite an explicitly provided secret' do
      project = create(:project, webhook_secret: 'my-fixed-secret')
      expect(project.webhook_secret).to eq('my-fixed-secret')
    end

    it 'generates a different secret per project' do
      a = create(:project)
      b = create(:project)
      expect(a.webhook_secret).not_to eq(b.webhook_secret)
    end
  end

  describe '#regenerate_webhook_secret!' do
    it 'replaces the current secret with a new random one' do
      project = create(:project, :with_webhook)
      old_secret = project.webhook_secret

      project.regenerate_webhook_secret!

      expect(project.webhook_secret).to be_present
      expect(project.webhook_secret).not_to eq(old_secret)
    end

    it 'persists the change' do
      project = create(:project)
      project.regenerate_webhook_secret!
      expect(project.reload.webhook_secret).to eq(project.webhook_secret)
    end
  end
end
