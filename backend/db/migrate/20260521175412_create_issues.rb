class CreateIssues < ActiveRecord::Migration[7.1]
  def change
    create_table :issues do |t|
      t.references :submission,   null: false, foreign_key: true
      t.references :analysis_run, null: true,  foreign_key: true
      t.integer :source,      null: false, default: 0 # linter/llm/hybrid
      t.string  :rule_id,     null: false
      t.integer :severity,    null: false, default: 0 # info/low/medium/high/critical
      t.integer :category,    null: false, default: 0 # code_quality/bug/style/security/refactor
      t.string  :file_path,   null: false
      t.integer :line_start,  null: false
      t.integer :line_end,    null: false
      t.integer :column_start
      t.integer :column_end
      t.text    :message,     null: false
      t.text    :suggestion
      t.decimal :confidence, precision: 4, scale: 3
      t.string  :dedup_key,   null: false

      t.timestamps
    end

    add_index :issues, %i[submission_id dedup_key], unique: true
    add_index :issues, %i[submission_id severity]
  end
end
