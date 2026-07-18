class LLMReviewJob < ApplicationJob
  include BroadcastsSubmissionStatus

  queue_as :llm

  def perform(submission_id)
    submission = Submission.find_by(id: submission_id)
    return unless submission
    return unless submission.reviewing?

    result = LLM::ReviewService.new(
      submission: submission,
      on_progress: ->(message) { broadcast_status(submission, message: message) }
    ).call # never raises on LLM-domain errors
    persist_issues(result.issues_attrs, submission)
    stash_llm_meta(submission, result)

    submission.finish_review!                                    # ALWAYS runs (graceful degradation)
    broadcast_status(submission)
    AggregateReportJob.perform_later(submission.id)
  rescue StandardError => e
    # Narrowed: only fail if THIS worker still owns the reviewing state.
    # A concurrent duplicate delivery causes AASM::InvalidTransition here;
    # the broad may_fail? would wrongly fail a submission the winner already advanced.
    if submission&.reviewing?
      submission.fail!(e.message)
      broadcast_status(submission)
    end
    raise
  end

  private

  def persist_issues(attrs_list, submission)
    attrs_list.each do |attrs|
      submission.issues.create!(attrs)
    rescue ActiveRecord::RecordInvalid
      next # duplicate dedup_key — idempotent on Sidekiq retry
    end
  end

  def stash_llm_meta(submission, result)
    review = submission.review || submission.build_review(mode: :linter_only, total_issues: 0)
    review.update!(llm_attempts: result.attempts, llm_duration_ms: result.duration_ms,
                   review_log: result.review_log || [])
  end
end
