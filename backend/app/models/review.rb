class Review < ApplicationRecord
  belongs_to :submission

  enum :mode, { hybrid: 0, linter_only: 1 }

  validates :total_issues, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
