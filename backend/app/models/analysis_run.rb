class AnalysisRun < ApplicationRecord
  belongs_to :submission

  enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, skipped: 4 }

  validates :runner, presence: true, uniqueness: { scope: :submission_id }
end
