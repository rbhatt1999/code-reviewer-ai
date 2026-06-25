class StaticAnalysisJob < ApplicationJob
  include BroadcastsSubmissionStatus

  queue_as :analysis

  # Each entry is [short_name, runner_class].  Rubocop is the existing runner
  # and has no RUNNER_NAME constant — the name is carried here instead so the
  # reference implementation is left untouched.
  RUNNER_REGISTRY = {
    'ruby'       => [['rubocop',  Runners::Rubocop],
                     ['brakeman', Runners::Brakeman],
                     ['semgrep',  Runners::Semgrep]],
    'python'     => [['bandit',   Runners::Bandit],
                     ['semgrep',  Runners::Semgrep]],
    'javascript' => [['eslint',   Runners::Eslint],
                     ['semgrep',  Runners::Semgrep]],
    'typescript' => [['eslint',   Runners::Eslint],
                     ['semgrep',  Runners::Semgrep]],
    'java'       => [['semgrep',  Runners::Semgrep]]
  }.freeze

  def perform(submission_id)
    submission = Submission.find_by(id: submission_id)
    return unless submission
    # Idempotency: only process when the pipeline is at the right entry point.
    return unless submission.analyzing?

    runners_for(submission.language).each do |runner_name, runner_class|
      run_single_runner(runner_name, runner_class, submission)
    end

    submission.finish_analysis!
    broadcast_status(submission)
    LLMReviewJob.perform_later(submission.id)
  rescue StandardError => e
    submission&.fail!(e.message) if submission&.may_fail?
    broadcast_status(submission)
    raise
  end

  private

  # Returns an ordered list of [short_name, runner_class] pairs for a language.
  # Exposed as a private method so tests can introspect it directly
  # (e.g. `job.send(:runners_for, 'python').map { |_n, c| c.name }`).
  def runners_for(language)
    RUNNER_REGISTRY.fetch(language.to_s, [])
  end

  def run_single_runner(runner_name, runner_class, submission)
    run = AnalysisRun.find_or_create_by(submission: submission, runner: runner_name) do |r|
      r.status     = :running
      r.started_at = Time.current
    end
    # Reset fields so a Sidekiq retry starts clean rather than lying about
    # fields from a prior attempt.
    run.update!(status: :running, started_at: Time.current, finished_at: nil,
                exit_code: nil, duration_ms: nil, stdout_excerpt: nil, stderr_excerpt: nil)

    result = runner_class.new(
      file_path: submission.blob_path,
      submission_id: submission.id
    ).call

    persist_issues(result.issues_attrs, run, submission)
    finalize_run(run, runner_name, result)
  end

  def persist_issues(issues_attrs, run, submission)
    issues_attrs.each do |attrs|
      submission.issues.create!(attrs.merge(analysis_run: run))
    rescue ActiveRecord::RecordInvalid
      next
    end
  end

  def finalize_run(run, runner_name, result)
    # Treat a run as failed when the runner explicitly crashed (nil exit_code
    # from Errno::ENOENT rescue) or when RuboCop exits 2 (its own convention
    # for a fatal configuration / parse error, distinct from exit 1 which means
    # offences found).  Exit codes 0–N from all other linters are normal.
    status = if result.exit_code.nil? || (runner_name == 'rubocop' && result.exit_code == 2)
               :failed
             else
               :succeeded
             end

    run.update!(
      status: status,
      exit_code: result.exit_code,
      duration_ms: result.duration_ms,
      stdout_excerpt: result.stdout.to_s.first(8000),
      stderr_excerpt: result.stderr.to_s.first(8000),
      finished_at: Time.current
    )
  end
end
