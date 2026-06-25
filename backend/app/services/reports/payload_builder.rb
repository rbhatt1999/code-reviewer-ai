module Reports
  class PayloadBuilder
    def initialize(submission:)
      @submission = submission
    end

    def call
      {
        submission: {
          id: @submission.id, kind: @submission.kind, language: @submission.language,
          source_ref: @submission.source_ref, status: @submission.status,
          created_at: @submission.created_at, finished_at: @submission.finished_at
        },
        review: review_hash,
        issues: @submission.issues.order(severity: :desc, file_path: :asc, line_start: :asc).map { |i| issue_hash(i) },
        generated_at: Time.current
      }
    end

    private

    def review_hash
      r = @submission.review
      return nil unless r

      { mode: r.mode, summary: r.summary, scores: r.scores, total_issues: r.total_issues }
    end

    def issue_hash(issue)
      { source: issue.source, rule_id: issue.rule_id, severity: issue.severity, category: issue.category,
        file_path: issue.file_path, line_start: issue.line_start, line_end: issue.line_end,
        message: issue.message, suggestion: issue.suggestion, confidence: issue.confidence }
    end
  end
end
