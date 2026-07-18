require 'rails_helper'

RSpec.describe IngestJob, type: :job do
  include ActiveJob::TestHelper

  # ── helpers ──────────────────────────────────────────────────────────────

  def ok_status
    instance_double(Process::Status, exitstatus: 0)
  end

  # ── default single_file context (existing tests, unchanged) ─────────────

  let(:blob_path) { Rails.root.join('tmp/ingest_job_spec_blob.rb').to_s }
  let!(:submission) do
    create(:submission, status: :pending, blob_path: blob_path, size_bytes: content.bytesize)
  end
  let(:content) { "puts 'hello'\n" }

  before do
    File.binwrite(blob_path, content)
    # Stub AST extractor so it never calls the real tree-sitter CLI.
    allow_any_instance_of(Ast::Extractor).to receive(:call).and_return(nil)
  end

  after { FileUtils.rm_f(blob_path) }

  describe 'guard clause' do
    it 'returns early and does not change state when submission is missing' do
      expect { described_class.perform_now(0) }.not_to raise_error
    end

    it 'returns early when submission is not pending' do
      submission.update!(status: :analyzing)
      expect { described_class.perform_now(submission.id) }.not_to(change do
        submission.reload.status
      end)
    end
  end

  describe 'happy path (single_file)' do
    it 'transitions from pending to analyzing and enqueues StaticAnalysisJob' do
      expect do
        described_class.perform_now(submission.id)
      end.to have_enqueued_job(StaticAnalysisJob).with(submission.id)

      expect(submission.reload.status).to eq('analyzing')
    end

    it 'broadcasts at least one status event on SubmissionChannel' do
      expect do
        described_class.perform_now(submission.id)
      end.to have_broadcasted_to(submission).from_channel(SubmissionChannel).at_least(:once)
    end
  end

  describe 'exception path — blob missing' do
    before { FileUtils.rm_f(blob_path) }

    it 'lands the submission in failed with an error_message and re-raises' do
      expect { described_class.perform_now(submission.id) }.to raise_error(RuntimeError, /Blob missing/)

      submission.reload
      expect(submission.status).to eq('failed')
      expect(submission.error_message).to match(/Blob missing/)
    end
  end

  describe 'exception path — size mismatch' do
    before do
      # Write fewer bytes than submission.size_bytes claims
      submission.update!(size_bytes: content.bytesize + 100)
    end

    it 'lands the submission in failed with a size mismatch message and re-raises' do
      expect { described_class.perform_now(submission.id) }.to raise_error(RuntimeError, /size mismatch/)

      submission.reload
      expect(submission.status).to eq('failed')
      expect(submission.error_message).to match(/size mismatch/)
    end
  end

  # ── AST integration ───────────────────────────────────────────────────────

  describe 'AST extraction (2F)' do
    let(:ast_payload) { { 'files' => [{ 'path' => 'test_file.rb', 'language' => 'ruby', 'node_counts' => { 'method' => 1 }, 'definitions' => [] }] } }

    before do
      allow_any_instance_of(Ast::Extractor).to receive(:call).and_return(ast_payload)
    end

    it 'persists ast_summary on the submission after the job runs' do
      described_class.perform_now(submission.id)
      expect(submission.reload.ast_summary).to eq(ast_payload)
    end
  end

  # ── zip context (2E) ─────────────────────────────────────────────────────

  describe 'kind: zip' do
    let(:zip_dir) { Rails.root.join('tmp', 'ingest_zip_spec').to_s }
    let(:zip_file_path) { File.join(zip_dir, 'upload.zip') }
    let(:extracted_dir) do
      Rails.root.join(IngestJob::BLOB_ROOT, zip_submission.id.to_s, 'extracted').to_s
    end

    let!(:zip_submission) do
      FileUtils.mkdir_p(zip_dir)
      # Build a minimal zip in-memory.
      require 'zip'
      io = Zip::OutputStream.write_buffer do |zos|
        zos.put_next_entry('app.rb')
        zos.write("puts 'hi'\n")
      end
      File.binwrite(zip_file_path, io.string)

      create(
        :submission,
        kind: :zip,
        status: :pending,
        blob_path: zip_file_path,
        size_bytes: File.size(zip_file_path),
        language: 'ruby'
      )
    end

    before do
      allow_any_instance_of(Ast::Extractor).to receive(:call).and_return(nil)
    end

    after { FileUtils.rm_rf(zip_dir) }

    it 'extracts the zip, sets blob_path to the extracted directory, and enqueues StaticAnalysisJob' do
      expect do
        described_class.perform_now(zip_submission.id)
      end.to have_enqueued_job(StaticAnalysisJob).with(zip_submission.id)

      zip_submission.reload
      expect(zip_submission.status).to eq('analyzing')
      expect(zip_submission.blob_path).to eq(extracted_dir)
      expect(File).to exist(File.join(extracted_dir, 'app.rb'))
    end

    context 'when the zip exceeds the byte limit' do
      before do
        stub_const('ENV', ENV.to_hash.merge('MAX_UPLOAD_BYTES' => '5'))
      end

      it 'fails the submission' do
        expect { described_class.perform_now(zip_submission.id) }.to raise_error(Ingestion::SizeLimitExceeded)
        expect(zip_submission.reload.status).to eq('failed')
      end
    end
  end

  # ── git_url context (2E) ──────────────────────────────────────────────────

  describe 'kind: git_url' do
    let(:url_dir) { Rails.root.join('tmp', 'ingest_git_spec').to_s }
    let(:url_file_path) { File.join(url_dir, 'url.txt') }
    let(:repo_url)  { 'https://github.com/example/repo.git' }
    let(:cloned_dir) do
      Rails.root.join(IngestJob::BLOB_ROOT, git_submission.id.to_s, 'cloned').to_s
    end

    let!(:git_submission) do
      FileUtils.mkdir_p(url_dir)
      File.write(url_file_path, repo_url)
      create(
        :submission,
        kind: :git_url,
        status: :pending,
        blob_path: url_file_path,
        size_bytes: File.size(url_file_path),
        language: 'ruby'
      )
    end

    before do
      allow_any_instance_of(Ast::Extractor).to receive(:call).and_return(nil)

      call_count = 0
      allow(Open3).to receive(:capture3) do |*args|
        call_count += 1
        if call_count == 1
          # Simulate git clone by creating dest_dir with a file.
          FileUtils.mkdir_p(cloned_dir)
          File.write(File.join(cloned_dir, 'app.rb'), "puts 1\n")
          ['', '', instance_double(Process::Status, exitstatus: 0)]
        else
          # git rev-parse HEAD
          ['abcdef123456', '', instance_double(Process::Status, exitstatus: 0)]
        end
      end
    end

    after { FileUtils.rm_rf(url_dir) }

    it 'clones the repo, sets blob_path to cloned directory, updates source_ref, and enqueues StaticAnalysisJob' do
      expect do
        described_class.perform_now(git_submission.id)
      end.to have_enqueued_job(StaticAnalysisJob).with(git_submission.id)

      git_submission.reload
      expect(git_submission.status).to eq('analyzing')
      expect(git_submission.blob_path).to eq(cloned_dir)
      expect(git_submission.source_ref).to match(%r{https://github\.com/example/repo\.git@[a-f0-9]+})
    end

    context 'when git clone fails' do
      before do
        allow(Open3).to receive(:capture3)
          .with(anything, 'git', 'clone', '--depth', '1', repo_url, cloned_dir.to_s)
          .and_return(['', 'fatal: not found', instance_double(Process::Status, exitstatus: 128)])
      end

      it 'fails the submission with CloneFailed error' do
        expect { described_class.perform_now(git_submission.id) }.to raise_error(Ingestion::CloneFailed)
        expect(git_submission.reload.status).to eq('failed')
      end
    end
  end

  # ── github_webhook context (B8) ───────────────────────────────────────────

  describe 'kind: github_webhook' do
    let(:meta_dir) { Rails.root.join('tmp', 'ingest_webhook_spec').to_s }
    let(:meta_file_path) { File.join(meta_dir, 'webhook_meta.txt') }
    let(:webhook_repo_url) { 'https://github.com/acme/widget' }

    let!(:webhook_submission) do
      FileUtils.mkdir_p(meta_dir)
      File.write(meta_file_path, "#{webhook_repo_url}\n7")
      create(
        :submission,
        kind: :github_webhook,
        status: :pending,
        source_ref: 'PR#7@deadbeef',
        blob_path: meta_file_path,
        size_bytes: File.size(meta_file_path),
        language: 'ruby'
      )
    end

    let(:webhook_dest_dir) do
      Rails.root.join(IngestJob::BLOB_ROOT, webhook_submission.id.to_s, 'cloned').to_s
    end

    let(:pr_files_api_url) { 'https://api.github.com/repos/acme/widget/pulls/7/files' }

    before do
      allow_any_instance_of(Ast::Extractor).to receive(:call).and_return(nil)

      allow(Open3).to receive(:capture3) do |*args|
        cmd = args.reject { |a| a.is_a?(Hash) }
        if    cmd[0..1] == ['git', 'clone']
          FileUtils.mkdir_p(webhook_dest_dir)
          File.write("#{webhook_dest_dir}/app.rb", "x\n")
          ['', '', ok_status]
        elsif cmd.include?('fetch')
          ['', '', ok_status]
        elsif cmd.include?('checkout')
          ['', '', ok_status]
        elsif cmd.include?('rev-parse')
          ['abcdef123456', '', ok_status]
        else
          ['', '', ok_status]
        end
      end

      # Default: no PR files (empty diff) — individual examples override this.
      stub_request(:get, pr_files_api_url).to_return(
        status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' }
      )
    end

    after { FileUtils.rm_rf(meta_dir) }

    it 'transitions the submission to analyzing and enqueues StaticAnalysisJob' do
      expect do
        described_class.perform_now(webhook_submission.id)
      end.to have_enqueued_job(StaticAnalysisJob).with(webhook_submission.id)

      expect(webhook_submission.reload.status).to eq('analyzing')
    end

    it 'sets blob_path to the cloned directory' do
      described_class.perform_now(webhook_submission.id)
      expect(webhook_submission.reload.blob_path).to eq(webhook_dest_dir)
    end

    it 'preserves source_ref unchanged (dedup key regression guard)' do
      described_class.perform_now(webhook_submission.id)
      expect(webhook_submission.reload.source_ref).to eq('PR#7@deadbeef')
    end

    describe 'PR diff stashing' do
      let(:pr_diff_path) do
        Rails.root.join(IngestJob::BLOB_ROOT, webhook_submission.id.to_s, 'pr_diff.json')
      end

      it 'writes pr_diff.json when GitHub returns changed files' do
        stub_request(:get, pr_files_api_url).to_return(
          status: 200,
          body: [
            { filename: 'app.rb', status: 'modified', additions: 1, deletions: 1,
              patch: "@@ -1,1 +1,1 @@\n-old\n+new" }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        described_class.perform_now(webhook_submission.id)

        expect(File).to exist(pr_diff_path)
        stashed = JSON.parse(File.read(pr_diff_path))
        expect(stashed.first['filename']).to eq('app.rb')
        expect(stashed.first['patch_numbered']).to include('+new')
      end

      it 'does not write pr_diff.json when GitHub returns no files' do
        described_class.perform_now(webhook_submission.id)
        expect(File).not_to exist(pr_diff_path)
      end

      it 'does not fail the submission when the GitHub API call errors' do
        stub_request(:get, pr_files_api_url).to_raise(Faraday::ConnectionFailed.new('refused'))

        expect do
          described_class.perform_now(webhook_submission.id)
        end.not_to raise_error

        expect(webhook_submission.reload.status).to eq('analyzing')
        expect(File).not_to exist(pr_diff_path)
      end
    end
  end
end
