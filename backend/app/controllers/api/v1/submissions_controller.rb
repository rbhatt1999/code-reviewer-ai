require 'fileutils'

module Api
  module V1
    class SubmissionsController < ApplicationController
      MAX_UPLOAD_BYTES = ENV.fetch('MAX_UPLOAD_BYTES', 5_242_880).to_i
      BLOB_ROOT        = ENV.fetch('SUBMISSION_BLOB_ROOT', 'storage/submissions')

      LANGUAGE_MAP = {
        'rb' => 'ruby',
        'py' => 'python',
        'js' => 'javascript',
        'ts' => 'typescript',
        'jsx' => 'javascript',
        'tsx' => 'typescript',
        'java' => 'java'
      }.freeze

      before_action :set_project, only: %i[index create]
      before_action :set_submission, only: %i[show issues review]

      def index
        submissions = @project.submissions.order(created_at: :desc)
        render json: { submissions: submissions.map { |s| submission_payload(s) } }, status: :ok
      end

      def create
        kind = params.dig(:submission, :kind) || 'single_file'
        content, filename = extract_content_and_filename(kind)
        return if over_size_limit?(content)

        # Persist first so the record has an id, then namespace the blob by that
        # id. Building the path before save would use a nil id and collide every
        # submission's blob into one shared directory.
        submission = @project.submissions.create!(
          user: current_user,
          kind: kind,
          status: :pending,
          language: detect_language(kind),
          size_bytes: content.bytesize,
          source_ref: filename,
          blob_path: '(pending)'
        )
        submission.update!(blob_path: store_blob(submission, content, filename))

        IngestJob.perform_later(submission.id)

        render json: { submission: submission_payload(submission) }, status: :created
      end

      def show
        render json: { submission: submission_payload(@submission) }, status: :ok
      end

      def issues
        issues = @submission.issues.order(severity: :desc, line_start: :asc)
        render json: { issues: issues.map { |i| issue_payload(i) } }, status: :ok
      end

      def review
        review = @submission.review
        if review
          render json: { review: review_payload(review) }, status: :ok
        else
          render json: { error: 'not_found', message: 'Review not ready' }, status: :not_found
        end
      end

      private

      def set_project
        @project = current_user.projects.find(params[:project_id])
      end

      def set_submission
        @submission = current_user.submissions.find(params[:id])
      end

      def detect_language(kind)
        if kind.to_s == 'paste'
          params.dig(:submission, :language) || 'ruby'
        else
          file = params.dig(:submission, :file)
          return 'ruby' unless file.respond_to?(:original_filename)

          ext = File.extname(file.original_filename).delete('.').downcase
          LANGUAGE_MAP.fetch(ext, 'ruby')
        end
      end

      def extract_content_and_filename(kind)
        if kind.to_s == 'paste'
          content_param = params.dig(:submission, :content)
          raise ActionController::ParameterMissing, 'submission[content]' if content_param.blank?

          [content_param.to_s, 'paste.rb']
        else
          file = params.dig(:submission, :file)
          raise ActionController::ParameterMissing, 'submission[file]' unless file.respond_to?(:read)

          [file.read, file.original_filename]
        end
      end

      def over_size_limit?(content)
        return false unless content.bytesize > MAX_UPLOAD_BYTES

        render json: {
          error: 'unprocessable',
          errors: { file: ["exceeds maximum size of #{MAX_UPLOAD_BYTES} bytes"] }
        }, status: :unprocessable_entity
        true
      end

      def store_blob(submission, content, filename)
        dir = Rails.root.join(BLOB_ROOT, submission.id.to_s)
        FileUtils.mkdir_p(dir)
        safe_name = File.basename(filename)
        path = dir.join(safe_name)
        File.binwrite(path, content)
        path.to_s
      end

      def submission_payload(submission)
        {
          id: submission.id,
          project_id: submission.project_id,
          kind: submission.kind,
          status: submission.status,
          language: submission.language,
          size_bytes: submission.size_bytes,
          source_ref: submission.source_ref,
          issues_count: submission.issues_count,
          finished_at: submission.finished_at,
          created_at: submission.created_at,
          error_message: submission.error_message
        }
      end

      def issue_payload(issue)
        {
          id: issue.id,
          source: issue.source,
          rule_id: issue.rule_id,
          severity: issue.severity,
          category: issue.category,
          file_path: issue.file_path,
          line_start: issue.line_start,
          line_end: issue.line_end,
          message: issue.message,
          suggestion: issue.suggestion,
          confidence: issue.confidence
        }
      end

      def review_payload(review)
        {
          id: review.id,
          mode: review.mode,
          summary: review.summary,
          scores: review.scores,
          total_issues: review.total_issues,
          review_log: review.review_log
        }
      end
    end
  end
end
