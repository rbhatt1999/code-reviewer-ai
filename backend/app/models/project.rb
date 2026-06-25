class Project < ApplicationRecord
  VALID_LANGUAGES = %w[ruby python javascript typescript java].freeze

  belongs_to :user
  has_many :submissions, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :language, presence: true, inclusion: { in: VALID_LANGUAGES }
  validates :default_branch, presence: true

  before_validation :set_default_branch

  delegate :count, to: :submissions, prefix: true

  private

  def set_default_branch
    self.default_branch ||= 'main'
  end
end
