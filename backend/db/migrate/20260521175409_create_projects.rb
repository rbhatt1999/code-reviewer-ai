class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name,           null: false
      t.text   :description
      t.string :language,       null: false
      t.string :default_branch, null: false, default: 'main'
      t.string :repo_url
      t.string :webhook_secret

      t.timestamps
    end

    add_index :projects, %i[user_id name], unique: true
  end
end
