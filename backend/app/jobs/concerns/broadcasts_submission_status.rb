module BroadcastsSubmissionStatus
  extend ActiveSupport::Concern

  PROGRESS_BY_STATUS = {
    'pending' => 0,
    'ingesting' => 15,
    'analyzing' => 40,
    'reviewing' => 65,
    'aggregating' => 85,
    'completed' => 100,
    'failed' => 100
  }.freeze

  private

  def broadcast_status(submission, message: nil)
    submission.reload
    SubmissionChannel.broadcast_to(submission, {
                                     submission_id: submission.id,
                                     status: submission.status,
                                     progress: PROGRESS_BY_STATUS.fetch(submission.status, 0),
                                     issues_count: submission.issues.count,
                                     mode: submission.review&.mode,
                                     message: message,
                                     updated_at: Time.current.iso8601
                                   })
  rescue StandardError => e
    Rails.logger.warn("[BroadcastsSubmissionStatus] broadcast failed: #{e.message}")
  end
end
