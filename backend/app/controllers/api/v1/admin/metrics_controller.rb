require 'sidekiq/api'

module Api
  module V1
    module Admin
      class MetricsController < ApplicationController
        before_action :require_admin!

        def show
          render json: { metrics: {
            submissions: submissions_metrics,
            issues: issues_metrics,
            users: user_metrics,
            sidekiq: sidekiq_stats
          } }, status: :ok
        end

        private

        def require_admin!
          return if current_user.admin?

          render json: { error: 'forbidden', message: 'Admin access required' }, status: :forbidden
        end

        def submissions_metrics
          {
            total: Submission.count,
            by_status: Submission.group(:status).count,
            completed: Submission.where(status: :completed).count,
            failed: Submission.where(status: :failed).count
          }
        end

        def issues_metrics
          { total: Issue.count, by_severity: Issue.group(:severity).count }
        end

        def user_metrics
          { total: User.count, admins: User.where(role: :admin).count }
        end

        def sidekiq_stats
          stats = Sidekiq::Stats.new
          { processed: stats.processed, failed: stats.failed, enqueued: stats.enqueued,
            scheduled: stats.scheduled_size, retries: stats.retry_size }
        end
      end
    end
  end
end
