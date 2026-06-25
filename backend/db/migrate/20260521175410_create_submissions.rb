class CreateSubmissions < ActiveRecord::Migration[7.1]
  def change
    create_table :submissions do |t|
      t.references :user,    null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.integer  :kind,       null: false, default: 0 # paste/single_file/zip/git_url/github_webhook
      t.integer  :status,     null: false, default: 0 # AASM pipeline state
      t.string   :source_ref
      t.string   :blob_path,  null: false
      t.bigint   :size_bytes, null: false
      t.string   :language,   null: false
      t.jsonb    :ast_summary
      t.text     :error_message
      t.datetime :finished_at

      t.timestamps
    end

    add_index :submissions, %i[project_id created_at]
    add_index :submissions, :status
  end
end
