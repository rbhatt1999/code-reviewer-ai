class CreateReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :reviews do |t|
      t.references :submission, null: false, foreign_key: true, index: { unique: true }
      t.integer :mode,         null: false, default: 0 # hybrid: 0, linter_only: 1
      t.text    :summary
      t.jsonb   :scores
      t.integer :total_issues, null: false, default: 0
      t.integer :llm_attempts, null: false, default: 0
      t.integer :llm_duration_ms

      t.timestamps
    end
  end
end
