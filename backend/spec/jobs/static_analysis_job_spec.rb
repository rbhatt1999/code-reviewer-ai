require 'rails_helper'

RSpec.describe StaticAnalysisJob, type: :job do
  include ActiveJob::TestHelper

  let(:blob_path) { '/tmp/static_analysis_spec_file.rb' }
  let!(:submission) { create(:submission, status: :analyzing, language: 'ruby', blob_path: blob_path) }

  # Helper: builds a canned Result for use as a runner stub return value.
  def make_result(runner_name:, rule_id:, file_path: blob_path)
    Runners::Base::Result.new(
      issues_attrs: [
        {
          source: :linter,
          rule_id: rule_id,
          severity: 'info',
          category: 'code_quality',
          file_path: file_path,
          line_start: 1,
          line_end: 1,
          column_start: 1,
          column_end: 10,
          message: "Issue from #{runner_name}",
          suggestion: nil,
          confidence: nil,
          dedup_key: Digest::SHA1.hexdigest("#{file_path}|1|#{rule_id}")
        }
      ],
      stdout: '{}',
      stderr: '',
      exit_code: 1,
      duration_ms: 200
    )
  end

  # Stub all three ruby runners up front so no real subprocess is spawned.
  let(:rubocop_result) { make_result(runner_name: 'rubocop', rule_id: 'RuboCop/Style/StringLiterals') }
  let(:brakeman_result) { make_result(runner_name: 'brakeman', rule_id: 'Brakeman/0') }
  let(:semgrep_result)  { make_result(runner_name: 'semgrep',  rule_id: 'semgrep/rule') }

  let(:rubocop_double)  { instance_double(Runners::Rubocop,  call: rubocop_result) }
  let(:brakeman_double) { instance_double(Runners::Brakeman, call: brakeman_result) }
  let(:semgrep_double)  { instance_double(Runners::Semgrep,  call: semgrep_result) }

  before do
    allow(Runners::Rubocop).to receive(:new)
      .with(file_path: blob_path, submission_id: submission.id)
      .and_return(rubocop_double)
    allow(Runners::Brakeman).to receive(:new)
      .with(file_path: blob_path, submission_id: submission.id)
      .and_return(brakeman_double)
    allow(Runners::Semgrep).to receive(:new)
      .with(file_path: blob_path, submission_id: submission.id)
      .and_return(semgrep_double)
  end

  describe 'guard clause' do
    it 'returns early when submission is missing' do
      expect { described_class.perform_now(0) }.not_to raise_error
    end

    it 'returns early when submission is not analyzing' do
      submission.update!(status: :pending)
      expect { described_class.perform_now(submission.id) }.not_to(change do
        submission.reload.status
      end)
    end
  end

  describe 'happy path — ruby submission' do
    it 'creates AnalysisRun rows for rubocop, brakeman, and semgrep' do
      described_class.perform_now(submission.id)
      expect(submission.analysis_runs.pluck(:runner).sort).to eq(%w[brakeman rubocop semgrep])
    end

    it 'persists one issue per runner and transitions to reviewing' do
      described_class.perform_now(submission.id)
      expect(submission.reload.status).to eq('reviewing')
      expect(submission.issues.count).to eq(3)
    end

    it 'enqueues LLMReviewJob' do
      expect do
        described_class.perform_now(submission.id)
      end.to have_enqueued_job(LLMReviewJob).with(submission.id)
    end

    it 'broadcasts a status event on SubmissionChannel after finishing analysis' do
      expect do
        described_class.perform_now(submission.id)
      end.to have_broadcasted_to(submission).from_channel(SubmissionChannel)
        .with(hash_including(status: 'reviewing'))
    end

    it 'records all three AnalysisRuns as succeeded' do
      described_class.perform_now(submission.id)
      submission.analysis_runs.each do |run|
        expect(run.status).to eq('succeeded')
      end
    end
  end

  describe 'runner registry dispatch by language' do
    context 'python submission' do
      let!(:submission) { create(:submission, status: :analyzing, language: 'python', blob_path: blob_path) }

      let(:bandit_result) { make_result(runner_name: 'bandit', rule_id: 'Bandit/B105') }
      let(:bandit_double) { instance_double(Runners::Bandit, call: bandit_result) }

      before do
        allow(Runners::Bandit).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(bandit_double)
        allow(Runners::Semgrep).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(semgrep_double)
      end

      it 'creates bandit and semgrep AnalysisRuns' do
        described_class.perform_now(submission.id)
        expect(submission.analysis_runs.pluck(:runner).sort).to eq(%w[bandit semgrep])
      end

      it 'dispatches to exactly Bandit and Semgrep' do
        expect(Runners::Bandit).to receive(:new).and_return(bandit_double)
        expect(Runners::Semgrep).to receive(:new).and_return(semgrep_double)
        expect(Runners::Rubocop).not_to receive(:new)
        described_class.perform_now(submission.id)
      end
    end

    context 'javascript submission' do
      let!(:submission) { create(:submission, status: :analyzing, language: 'javascript', blob_path: blob_path) }

      let(:eslint_result) { make_result(runner_name: 'eslint', rule_id: 'ESLint/no-var') }
      let(:eslint_double) { instance_double(Runners::Eslint, call: eslint_result) }

      before do
        allow(Runners::Eslint).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(eslint_double)
        allow(Runners::Semgrep).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(semgrep_double)
      end

      it 'creates eslint and semgrep AnalysisRuns' do
        described_class.perform_now(submission.id)
        expect(submission.analysis_runs.pluck(:runner).sort).to eq(%w[eslint semgrep])
      end
    end

    context 'typescript submission' do
      let!(:submission) { create(:submission, status: :analyzing, language: 'typescript', blob_path: blob_path) }

      let(:eslint_result) { make_result(runner_name: 'eslint', rule_id: 'ESLint/no-var') }
      let(:eslint_double) { instance_double(Runners::Eslint, call: eslint_result) }

      before do
        allow(Runners::Eslint).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(eslint_double)
        allow(Runners::Semgrep).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(semgrep_double)
      end

      it 'creates eslint and semgrep AnalysisRuns' do
        described_class.perform_now(submission.id)
        expect(submission.analysis_runs.pluck(:runner).sort).to eq(%w[eslint semgrep])
      end
    end

    context 'java submission' do
      let!(:submission) { create(:submission, status: :analyzing, language: 'java', blob_path: blob_path) }

      before do
        allow(Runners::Semgrep).to receive(:new)
          .with(file_path: blob_path, submission_id: submission.id)
          .and_return(semgrep_double)
      end

      it 'creates only a semgrep AnalysisRun' do
        described_class.perform_now(submission.id)
        expect(submission.analysis_runs.pluck(:runner)).to eq(%w[semgrep])
      end
    end

    context 'unknown language' do
      let!(:submission) { create(:submission, status: :analyzing, language: 'cobol', blob_path: blob_path) }

      it 'creates no AnalysisRuns and still transitions to reviewing' do
        expect { described_class.perform_now(submission.id) }
          .not_to(change { submission.analysis_runs.count })
        expect(submission.reload.status).to eq('reviewing')
      end
    end
  end

  describe 'idempotency — retry skips duplicate issues' do
    it 'does not raise when dedup_key already exists (RecordInvalid rescued)' do
      submission.issues.create!(rubocop_result.issues_attrs.first)

      expect { described_class.perform_now(submission.id) }.not_to raise_error
    end
  end

  describe 'runners_for helper' do
    it 'returns Bandit and Semgrep for python' do
      pairs = described_class.new.send(:runners_for, 'python')
      expect(pairs.map(&:first)).to eq(%w[bandit semgrep])
      expect(pairs.map(&:last).map(&:to_s)).to eq(%w[Runners::Bandit Runners::Semgrep])
    end

    it 'returns Rubocop, Brakeman, Semgrep for ruby' do
      pairs = described_class.new.send(:runners_for, 'ruby')
      expect(pairs.map(&:first)).to eq(%w[rubocop brakeman semgrep])
      expect(pairs.map(&:last).map(&:to_s)).to eq(%w[Runners::Rubocop Runners::Brakeman Runners::Semgrep])
    end

    it 'returns empty for unrecognised language' do
      expect(described_class.new.send(:runners_for, 'cobol')).to be_empty
    end
  end

  describe 'exception path' do
    before do
      allow(rubocop_double).to receive(:call).and_raise(RuntimeError, 'runner exploded')
    end

    it 'lands the submission in failed and re-raises' do
      expect { described_class.perform_now(submission.id) }.to raise_error(RuntimeError, 'runner exploded')

      submission.reload
      expect(submission.status).to eq('failed')
      expect(submission.error_message).to eq('runner exploded')
    end
  end

  describe 'RuboCop fatal exit (exit_code == 2)' do
    # RuboCop exits 2 on a configuration/parse error — distinct from exit 1
    # (offences found) and exit 0 (clean). The AnalysisRun must be :failed.
    let(:fatal_result) do
      Runners::Base::Result.new(
        issues_attrs: [],
        stdout: '',
        stderr: 'RuboCop configuration error',
        exit_code: 2,
        duration_ms: 50
      )
    end

    before do
      allow(rubocop_double).to receive(:call).and_return(fatal_result)
    end

    it 'records the rubocop AnalysisRun as failed' do
      described_class.perform_now(submission.id)
      rubocop_run = submission.analysis_runs.find_by(runner: 'rubocop')
      expect(rubocop_run.status).to eq('failed')
    end

    it 'still records brakeman and semgrep AnalysisRuns as succeeded' do
      described_class.perform_now(submission.id)
      %w[brakeman semgrep].each do |runner_name|
        run = submission.analysis_runs.find_by(runner: runner_name)
        expect(run.status).to eq('succeeded')
      end
    end
  end
end
