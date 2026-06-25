class AggregateReportJob < ApplicationJob
  include BroadcastsSubmissionStatus

  queue_as :default

  def perform(submission_id)
    submission = Submission.find_by(id: submission_id)
    return unless submission
    return unless submission.aggregating?

    # Atomic + serialized: a mid-merge crash rolls back the DELETEs.
    # Re-check aggregating? inside the lock (lost-race guard for concurrent delivery).
    # broadcast_status stays OUTSIDE the lock (never hold a row lock across a network call).
    submission.with_lock do
      next unless submission.aggregating?

      run_cross_source_merge(submission)
      upsert_review(submission)
      submission.complete!
    end

    broadcast_status(submission)
  rescue StandardError => e
    # Narrowed: only fail if THIS worker still owns the aggregating state.
    if submission&.aggregating?
      submission.fail!(e.message)
      broadcast_status(submission)
    end
    raise
  end

  private

  # Collapse a linter issue and an LLM issue that share file + overlapping line range + category
  # into one :hybrid issue (keep higher-severity / richer-message, delete the other).
  def run_cross_source_merge(submission)
    issues = submission.issues.to_a
    groups = issues.group_by { |i| [canon_path(submission, i.file_path), i.category] }
    groups.each_value { |group| merge_group(group) }
  end

  def merge_group(group)
    linters  = group.select(&:linter?)
    llms     = group.select(&:llm?)
    consumed = []

    llms.each do |llm_issue|
      match = find_overlapping(linters, llm_issue, consumed)
      next unless match

      merge_pair(match, llm_issue)
      consumed << match
    end
  end

  def find_overlapping(linters, llm_issue, consumed)
    linters.find do |k|
      consumed.exclude?(k) &&
        llm_issue.line_start <= k.line_end &&
        k.line_start <= llm_issue.line_end
    end
  end

  def merge_pair(linter_issue, llm_issue)
    keep, drop = pick_keep(linter_issue, llm_issue)
    keep.suggestion ||= llm_issue.suggestion
    keep.confidence ||= llm_issue.confidence
    keep.update!(source: :hybrid)
    drop.destroy!
  end

  def pick_keep(linter_issue, llm_issue)
    sev = Issue.severities
    linter_sev = sev[linter_issue.severity]
    llm_sev    = sev[llm_issue.severity]

    return [llm_issue, linter_issue] if llm_sev > linter_sev
    return [linter_issue, llm_issue] if llm_sev < linter_sev
    return [llm_issue, linter_issue] if llm_issue.message.to_s.length > linter_issue.message.to_s.length

    [linter_issue, llm_issue]
  end

  # Single owner of Review.mode — must set it in ALL branches (create AND update)
  # so it's always recomputed after merge. Preserves llm_attempts/llm_duration_ms.
  def upsert_review(submission)
    total  = submission.issues.count
    mode   = submission.issues.exists?(source: %i[llm hybrid]) ? :hybrid : :linter_only
    scores = severity_scores(submission)

    review = submission.review || submission.build_review
    review.assign_attributes(mode: mode, total_issues: total, scores: scores)
    review.save!
  end

  def severity_scores(submission)
    counts = Issue.severities.keys.index_with { |s| submission.issues.where(severity: s).count }
    counts.merge('total' => counts.values.sum)
  end

  def canon_path(submission, path)
    return File.basename(path) unless File.directory?(submission.blob_path)

    root = File.expand_path(submission.blob_path)
    abs  = File.expand_path(path, root)
    abs.start_with?(root + File::SEPARATOR) ? abs[(root.size + 1)..] : File.basename(path)
  end
end
