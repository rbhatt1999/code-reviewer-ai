class AddWebhookDedupIndexToSubmissions < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :submissions, %i[project_id source_ref],
              unique: true,
              where: 'kind = 4',
              name: 'idx_submissions_webhook_dedup',
              algorithm: :concurrently
  end
end
