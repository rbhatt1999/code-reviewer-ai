class IngestJob < ApplicationJob
  include BroadcastsSubmissionStatus

  queue_as :default

  BLOB_ROOT = ENV.fetch('SUBMISSION_BLOB_ROOT', 'storage/submissions')

  # rubocop:disable Metrics/CyclomaticComplexity -- dispatcher; each branch delegates to a single private method
  def perform(submission_id)
    submission = Submission.find_by(id: submission_id)
    return unless submission
    # Idempotency: only process when the pipeline is at the right entry point.
    return unless submission.pending?

    submission.start_ingest!
    broadcast_status(submission)

    case submission.kind
    when 'zip'            then handle_zip(submission)
    when 'git_url'        then handle_git_url(submission)
    when 'github_webhook' then handle_github_webhook(submission)
    else
      # paste / single_file — verify the pre-stored blob.
      verify_blob!(submission)
    end

    extract_ast!(submission)

    submission.finish_ingest!
    broadcast_status(submission)
    StaticAnalysisJob.perform_later(submission.id)
  rescue StandardError => e
    submission&.fail!(e.message) if submission&.may_fail?
    broadcast_status(submission)
    raise
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  private

  # ── paste / single_file ──────────────────────────────────────────────────

  def verify_blob!(submission)
    blob_path = submission.blob_path
    raise "Blob missing at #{blob_path}" unless File.exist?(blob_path)

    actual_size = File.size(blob_path)
    return if actual_size == submission.size_bytes

    raise "Blob size mismatch: expected #{submission.size_bytes}, got #{actual_size}"
  end

  # ── zip ──────────────────────────────────────────────────────────────────

  def handle_zip(submission)
    zip_path = submission.blob_path
    raise "ZIP blob missing at #{zip_path}" unless File.exist?(zip_path)

    dest_dir = Rails.root.join(BLOB_ROOT, submission.id.to_s, 'extracted').to_s

    result = Ingestion::ZipExtractor.new(
      zip_path: zip_path,
      dest_dir: dest_dir,
      max_bytes: max_upload_bytes
    ).call

    submission.update!(blob_path: dest_dir)
    # total_bytes reflects the decompressed size; record it for downstream awareness.
    Rails.logger.info(
      "[IngestJob] zip extracted #{result.file_count} files, " \
      "#{result.total_bytes} bytes → #{dest_dir}"
    )
  end

  # ── git_url ──────────────────────────────────────────────────────────────

  def handle_git_url(submission)
    # Controller stored the repo URL as a single-line text file at blob_path.
    url_file = submission.blob_path
    raise "URL file missing at #{url_file}" unless File.exist?(url_file)

    repo_url = File.read(url_file).strip
    dest_dir = Rails.root.join(BLOB_ROOT, submission.id.to_s, 'cloned').to_s

    result = Ingestion::GitCloner.new(
      repo_url: repo_url,
      dest_dir: dest_dir,
      max_bytes: max_upload_bytes
    ).call

    sha_suffix = result.commit_sha ? "@#{result.commit_sha[0, 12]}" : ''
    submission.update!(
      blob_path: dest_dir,
      source_ref: "#{repo_url}#{sha_suffix}"
    )
    Rails.logger.info(
      "[IngestJob] git cloned #{result.files.size} files, " \
      "#{result.total_bytes} bytes → #{dest_dir}"
    )
  end

  # ── github_webhook ───────────────────────────────────────────────────────

  # Webhook meta file stores two lines: repo_url\npr_number
  # repo_url is the server-trusted project.repo_url (SSRF guard — never the payload clone_url).
  def handle_github_webhook(submission)
    meta_file = submission.blob_path
    raise "Webhook meta missing at #{meta_file}" unless File.exist?(meta_file)

    repo_url, pr_number = File.read(meta_file).split("\n", 2).map(&:to_s).map(&:strip)
    dest_dir = Rails.root.join(BLOB_ROOT, submission.id.to_s, 'cloned').to_s

    Ingestion::GitCloner.new(
      repo_url: repo_url, dest_dir: dest_dir, pr_number: pr_number, max_bytes: max_upload_bytes
    ).call

    submission.update!(blob_path: dest_dir) # source_ref deliberately preserved (dedup key)
  end

  # ── AST extraction (2F) ──────────────────────────────────────────────────

  def extract_ast!(submission)
    summary = Ast::Extractor.new(
      root_path: submission.blob_path,
      language: submission.language
    ).call
    submission.update!(ast_summary: summary) if summary
  rescue StandardError => e
    # Extractor must not fail the chain; log and continue.
    Rails.logger.warn("[IngestJob] AST extraction error (non-fatal): #{e.message}")
  end

  def max_upload_bytes
    ENV.fetch('MAX_UPLOAD_BYTES', 5_242_880).to_i
  end
end
