class CreateAnalysisRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :analysis_runs do |t|
      t.references :submission, null: false, foreign_key: true
      t.string   :runner, null: false # rubocop|eslint|brakeman|bandit|semgrep|tree_sitter|llm
      t.integer  :status, null: false, default: 0
      t.integer  :exit_code
      t.integer  :duration_ms
      t.text     :stdout_excerpt
      t.text     :stderr_excerpt
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :analysis_runs, %i[submission_id runner], unique: true
  end
end
