module Api
  module V1
    class ReportsController < ApplicationController
      before_action :set_submission

      def json
        send_data Reports::PayloadBuilder.new(submission: @submission).call.to_json,
                  type: 'application/json', disposition: 'attachment',
                  filename: "review-#{@submission.id}.json"
      end

      def markdown
        send_data markdown_body, type: 'text/markdown', disposition: 'attachment',
                                 filename: "review-#{@submission.id}.md"
      end

      def pdf
        send_data Reports::PdfRenderer.new(markdown: markdown_body).call,
                  type: 'application/pdf', disposition: 'attachment',
                  filename: "review-#{@submission.id}.pdf"
      end

      private

      def set_submission
        @submission = current_user.submissions.find(params[:id])
        return if @submission.completed?

        render json: { error: 'unprocessable', message: 'Report available only for completed submissions' },
               status: :unprocessable_entity
      end

      def markdown_body
        payload = Reports::PayloadBuilder.new(submission: @submission).call
        Reports::MarkdownRenderer.new(payload: payload).call
      end
    end
  end
end
