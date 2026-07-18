class AddActivityLogToSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :submissions, :activity_log, :jsonb, null: false, default: []
  end
end
