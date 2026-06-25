class SubmissionChannel < ApplicationCable::Channel
  def subscribed
    submission = current_user.submissions.find_by(id: params[:submission_id])
    return reject if submission.nil?

    stream_for submission
  end

  def unsubscribed
    stop_all_streams
  end
end
