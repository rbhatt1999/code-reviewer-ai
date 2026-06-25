class Issue < ApplicationRecord
  belongs_to :submission
  belongs_to :analysis_run, optional: true

  enum :source, { linter: 0, llm: 1, hybrid: 2 }
  enum :severity, { info: 0, low: 1, medium: 2, high: 3, critical: 4 }
  enum :category, { code_quality: 0, bug: 1, style: 2, security: 3, refactor: 4 }

  validates :rule_id, presence: true
  validates :file_path, presence: true
  validates :line_start, presence: true, numericality: { only_integer: true }
  validates :line_end, presence: true, numericality: { only_integer: true }
  validates :message, presence: true
  validates :dedup_key, presence: true, uniqueness: { scope: :submission_id }
end
