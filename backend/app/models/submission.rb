class Submission < ApplicationRecord
  include AASM

  belongs_to :user
  belongs_to :project
  has_many :analysis_runs, dependent: :destroy
  has_many :issues, dependent: :destroy
  has_one :review, dependent: :destroy

  enum :kind, { paste: 0, single_file: 1, zip: 2, git_url: 3, github_webhook: 4 }, prefix: :kind
  enum :status, {
    pending: 0, ingesting: 1, analyzing: 2, reviewing: 3,
    aggregating: 4, completed: 5, failed: 6
  }

  validates :blob_path, presence: true
  validates :size_bytes, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :language, presence: true

  delegate :count, to: :issues, prefix: true

  # AASM state machine — drives the asynchronous review pipeline.
  # Event names are intentionally distinct from the Rails enum's
  # value-setter bang methods (e.g. `completed!`, `failed!`) so the two
  # APIs do not collide. Each job in the chain calls its `start_*`/
  # `finish_*` event; on success the chain progresses, on exception any
  # job calls `fail!(message)` to land the submission in :failed.
  aasm column: :status, enum: true, whiny_persistence: true do
    state :pending, initial: true
    state :ingesting, :analyzing, :reviewing, :aggregating, :completed, :failed

    event :start_ingest do
      transitions from: :pending, to: :ingesting
    end

    event :finish_ingest do
      transitions from: :ingesting, to: :analyzing
    end

    event :finish_analysis do
      transitions from: :analyzing, to: :reviewing
    end

    event :finish_review do
      transitions from: :reviewing, to: :aggregating
    end

    event :complete do
      # Stamp finished_at on the same save that persists the state change.
      # Setting it from a state-level after_enter callback fires too late —
      # AASM has already saved the new status by then and the attribute write
      # never reaches the database.
      before { self.finished_at = Time.current }
      transitions from: :aggregating, to: :completed
    end

    event :fail do
      before do |message = nil|
        self.finished_at = Time.current
        self.error_message = message if message.present?
      end
      transitions from: %i[pending ingesting analyzing reviewing aggregating], to: :failed
    end
  end
end
