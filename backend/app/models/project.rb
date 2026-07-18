class Project < ApplicationRecord
  VALID_LANGUAGES = %w[ruby python javascript typescript java].freeze

  belongs_to :user
  has_many :submissions, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :language, presence: true, inclusion: { in: VALID_LANGUAGES }
  validates :default_branch, presence: true

  before_validation :set_default_branch
  before_create :generate_webhook_secret

  delegate :count, to: :submissions, prefix: true

  # Generates a fresh HMAC secret and persists it immediately. Used both to
  # backfill projects created before webhook_secret existed in the UI and to
  # let a user rotate a leaked secret from the project page.
  def regenerate_webhook_secret!
    update!(webhook_secret: SecureRandom.hex(20))
  end

  private

  def set_default_branch
    self.default_branch ||= 'main'
  end

  def generate_webhook_secret
    self.webhook_secret ||= SecureRandom.hex(20)
  end
end
