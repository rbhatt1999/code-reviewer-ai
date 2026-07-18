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
      # Ordered trace of what the agentic reviewer actually did: which changed
      # files it started from (diff), which extra files it asked to read
      # (read_file / read_file_error), and how it finished (final_answer /
      # degraded). Drives the "review process" + reviewed-files-only view in
      # the submission detail page — see LLM::ReviewService#run_agent_loop.
      t.jsonb   :review_log,   null: false, default: []

      t.timestamps
    end
  end
end
