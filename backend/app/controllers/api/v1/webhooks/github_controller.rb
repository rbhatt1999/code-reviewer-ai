require 'openssl'

module Api
  module V1
    module Webhooks
      class GithubController < ApplicationController
        skip_before_action :authenticate_user!

        def create
          payload = parse_payload
          project = authenticate_project(payload)
          return head(:unauthorized) unless project

          pr_number = payload.dig('pull_request', 'number')
          head_sha  = payload.dig('pull_request', 'head', 'sha')
          return head(:bad_request) if pr_number.blank? || head_sha.blank?

          ref = "PR##{pr_number.to_i}@#{head_sha}"
          return head(:ok) if project.submissions.kind_github_webhook.exists?(source_ref: ref)

          submission = create_submission(project, pr_number.to_i, ref)
          IngestJob.perform_later(submission.id)
          head :accepted
        rescue ActiveRecord::RecordNotUnique
          head :ok
        end

        private

        def parse_payload
          JSON.parse(request.raw_post)
        rescue JSON::ParserError
          {}
        end

        def authenticate_project(payload)
          url = payload.dig('repository', 'clone_url')
          return nil if url.blank?

          normalized = normalize_repo_url(url)
          candidates = Project.where.not(repo_url: nil).select { |p| normalize_repo_url(p.repo_url) == normalized }
          candidates.find { |project| valid_signature?(project) }
        end

        def normalize_repo_url(url)
          url.to_s.strip.downcase.sub(/\.git\z/, '').sub(%r{/\z}, '')
        end

        def valid_signature?(project)
          secret = project.webhook_secret.to_s
          return false if secret.blank?

          header   = request.headers['X-Hub-Signature-256'].to_s
          expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
          return false unless header.bytesize == expected.bytesize

          ActiveSupport::SecurityUtils.secure_compare(header, expected)
        end

        def create_submission(project, pr_number, ref)
          submission = project.submissions.create!(
            user: project.user, kind: :github_webhook, status: :pending,
            language: project.language, size_bytes: 0, source_ref: ref, blob_path: '(pending)'
          )
          submission.update!(blob_path: store_meta(submission, project.repo_url, pr_number))
          submission.append_activity!(type: 'stage', message: 'Queued for review')
          submission
        end

        def store_meta(submission, repo_url, pr_number)
          dir = Rails.root.join(ENV.fetch('SUBMISSION_BLOB_ROOT', 'storage/submissions'), submission.id.to_s)
          FileUtils.mkdir_p(dir)
          path = dir.join('webhook_meta.txt')
          File.write(path, "#{repo_url}\n#{pr_number}")
          path.to_s
        end
      end
    end
  end
end
