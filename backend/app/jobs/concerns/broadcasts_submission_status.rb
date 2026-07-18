module BroadcastsSubmissionStatus
  extend ActiveSupport::Concern

  STATUS_MESSAGES = {
    'pending' => 'Queued for review',
    'ingesting' => 'Preparing source code',
    'analyzing' => 'Starting static analysis',
    'reviewing' => 'AI reviewing source code',
    'aggregating' => 'Combining review findings',
    'completed' => 'Review complete',
    'failed' => 'Review failed'
  }.freeze

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

  def broadcast_status(submission, message: nil, type: 'stage', file: nil)
    submission.reload
    activity = submission.append_activity!(
      type: type,
      message: message.presence || STATUS_MESSAGES.fetch(submission.status),
      file: file
    )
    SubmissionChannel.broadcast_to(submission, {
                                     submission_id: submission.id,
                                     status: submission.status,
                                     progress: PROGRESS_BY_STATUS.fetch(submission.status, 0),
                                     issues_count: submission.issues.count,
                                     mode: submission.review&.mode,
                                     message: activity['message'],
                                     activity: activity,
                                     updated_at: Time.current.iso8601
                                   })
  rescue StandardError => e
    Rails.logger.warn("[BroadcastsSubmissionStatus] broadcast failed: #{e.message}")
  end
end
