class AddReviewLogToReviews < ActiveRecord::Migration[7.1]
  # Ordered trace of what the agentic reviewer actually did: which changed
  # files it started from (diff), which extra files it asked to read
  # (read_file / read_file_error), and how it finished (final_answer /
  # degraded). Drives the "review process" + reviewed-files-only view in
  # the submission detail page — see LLM::ReviewService#run_agent_loop.
  def change
    add_column :reviews, :review_log, :jsonb, null: false, default: []
  end
end
