# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_05_21_175413) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "analysis_runs", force: :cascade do |t|
    t.bigint "submission_id", null: false
    t.string "runner", null: false
    t.integer "status", default: 0, null: false
    t.integer "exit_code"
    t.integer "duration_ms"
    t.text "stdout_excerpt"
    t.text "stderr_excerpt"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["submission_id", "runner"], name: "index_analysis_runs_on_submission_id_and_runner", unique: true
    t.index ["submission_id"], name: "index_analysis_runs_on_submission_id"
  end

  create_table "issues", force: :cascade do |t|
    t.bigint "submission_id", null: false
    t.bigint "analysis_run_id"
    t.integer "source", default: 0, null: false
    t.string "rule_id", null: false
    t.integer "severity", default: 0, null: false
    t.integer "category", default: 0, null: false
    t.string "file_path", null: false
    t.integer "line_start", null: false
    t.integer "line_end", null: false
    t.integer "column_start"
    t.integer "column_end"
    t.text "message", null: false
    t.text "suggestion"
    t.decimal "confidence", precision: 4, scale: 3
    t.string "dedup_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_run_id"], name: "index_issues_on_analysis_run_id"
    t.index ["submission_id", "dedup_key"], name: "index_issues_on_submission_id_and_dedup_key", unique: true
    t.index ["submission_id", "severity"], name: "index_issues_on_submission_id_and_severity"
    t.index ["submission_id"], name: "index_issues_on_submission_id"
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "language", null: false
    t.string "default_branch", default: "main", null: false
    t.string "repo_url"
    t.string "webhook_secret"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_projects_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "submission_id", null: false
    t.integer "mode", default: 0, null: false
    t.text "summary"
    t.jsonb "scores"
    t.integer "total_issues", default: 0, null: false
    t.integer "llm_attempts", default: 0, null: false
    t.integer "llm_duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["submission_id"], name: "index_reviews_on_submission_id", unique: true
  end

  create_table "submissions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id", null: false
    t.integer "kind", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "source_ref"
    t.string "blob_path", null: false
    t.bigint "size_bytes", null: false
    t.string "language", null: false
    t.jsonb "ast_summary"
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "created_at"], name: "index_submissions_on_project_id_and_created_at"
    t.index ["project_id", "source_ref"], name: "idx_submissions_webhook_dedup", unique: true, where: "(kind = 4)"
    t.index ["project_id"], name: "index_submissions_on_project_id"
    t.index ["status"], name: "index_submissions_on_status"
    t.index ["user_id"], name: "index_submissions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.string "jti", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "analysis_runs", "submissions"
  add_foreign_key "issues", "analysis_runs"
  add_foreign_key "issues", "submissions"
  add_foreign_key "projects", "users"
  add_foreign_key "reviews", "submissions"
  add_foreign_key "submissions", "projects"
  add_foreign_key "submissions", "users"
end
