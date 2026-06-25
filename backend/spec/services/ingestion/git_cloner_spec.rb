require 'rails_helper'

RSpec.describe Ingestion::GitCloner do
  let(:tmp_root)  { Rails.root.join('tmp', 'git_cloner_spec') }
  let(:dest_dir)  { File.join(tmp_root.to_s, 'repo') }
  let(:repo_url)  { 'https://github.com/example/repo.git' }
  let(:max_bytes) { 1_048_576 }

  subject(:cloner) do
    described_class.new(
      repo_url:        repo_url,
      dest_dir:        dest_dir,
      max_bytes:       max_bytes,
      timeout_seconds: 5
    )
  end

  # Represents a successful Process::Status (exitstatus == 0).
  def ok_status
    instance_double(Process::Status, exitstatus: 0)
  end

  # Represents a failed Process::Status.
  def fail_status(code = 128)
    instance_double(Process::Status, exitstatus: code)
  end

  before { FileUtils.mkdir_p(tmp_root) }
  after  { FileUtils.rm_rf(tmp_root) }

  describe 'URL validation' do
    context 'when repo_url is not HTTPS' do
      let(:repo_url) { 'git@github.com:example/repo.git' }

      it 'raises ArgumentError without calling git' do
        expect(Open3).not_to receive(:capture3)
        expect { cloner.call }.to raise_error(ArgumentError, /HTTPS/)
      end
    end

    context 'when repo_url uses http (not https)' do
      let(:repo_url) { 'http://github.com/example/repo.git' }

      it 'raises ArgumentError' do
        expect { cloner.call }.to raise_error(ArgumentError, /HTTPS/)
      end
    end
  end

  describe 'happy path' do
    let(:canned_sha) { 'abc123def456' * 2 } # 24 chars, realistic SHA-ish

    before do
      call_count = 0
      allow(Open3).to receive(:capture3) do |*args|
        call_count += 1
        if call_count == 1
          # First call: git clone — simulate by creating the dest_dir with a file.
          FileUtils.mkdir_p(dest_dir)
          File.write(File.join(dest_dir, 'app.rb'), "puts 'hello'\n")
          ['', '', ok_status]
        else
          # Second call: git rev-parse HEAD
          [canned_sha, '', ok_status]
        end
      end
    end

    it 'returns a Result with commit_sha and files list' do
      result = cloner.call

      expect(result.commit_sha).to eq(canned_sha)
      expect(result.files).to include('app.rb')
      expect(result.total_bytes).to be > 0
    end
  end

  describe 'non-zero exit from git clone' do
    before do
      allow(Open3).to receive(:capture3)
        .with(anything, 'git', 'clone', '--depth', '1', repo_url, dest_dir.to_s)
        .and_return(['', 'fatal: repository not found', fail_status])
    end

    it 'raises CloneFailed with stderr in the message' do
      expect { cloner.call }.to raise_error(Ingestion::CloneFailed, /fatal: repository not found/)
    end
  end

  describe 'oversize cloned tree' do
    let(:max_bytes) { 10 } # far below any real checkout

    before do
      allow(Open3).to receive(:capture3) do |*args|
        # Simulate clone producing files that exceed the cap.
        FileUtils.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, 'big.rb'), 'x' * 100)
        ['', '', ok_status]
      end
    end

    it 'raises SizeLimitExceeded and removes the cloned directory' do
      expect { cloner.call }.to raise_error(Ingestion::SizeLimitExceeded)
      expect(File).not_to exist(dest_dir)
    end
  end

  describe 'rev-parse failure' do
    before do
      call_count = 0
      allow(Open3).to receive(:capture3) do |*args|
        call_count += 1
        if call_count == 1
          FileUtils.mkdir_p(dest_dir)
          File.write(File.join(dest_dir, 'app.rb'), "puts 1\n")
          ['', '', ok_status]
        else
          # rev-parse fails
          ['', 'error', fail_status(1)]
        end
      end
    end

    it 'returns Result with nil commit_sha instead of raising' do
      result = cloner.call
      expect(result.commit_sha).to be_nil
    end
  end

  describe 'PR head checkout' do
    subject(:cloner) do
      described_class.new(repo_url: repo_url, dest_dir: dest_dir, max_bytes: max_bytes, pr_number: 42, timeout_seconds: 5)
    end

    before do
      @calls = []
      allow(Open3).to receive(:capture3) do |*args|
        @calls << args
        cmd = args.reject { |a| a.is_a?(Hash) }
        if cmd[0..1] == ['git', 'clone']
          FileUtils.mkdir_p(dest_dir)
          File.write(File.join(dest_dir, 'app.rb'), "puts 1\n")
          ['', '', ok_status]
        else
          ['abc123', '', ok_status]  # fetch / checkout / rev-parse all succeed
        end
      end
    end

    it 'fetches pull/42/head and checks out FETCH_HEAD' do
      cloner.call
      flat = @calls.map { |a| a.reject { |x| x.is_a?(Hash) } }
      expect(flat).to include(['git', '-C', dest_dir.to_s, 'fetch', '--depth', '1', 'origin', 'pull/42/head'])
      expect(flat).to include(['git', '-C', dest_dir.to_s, 'checkout', 'FETCH_HEAD'])
    end

    it 'does not fetch when pr_number is nil' do
      cloner_no_pr = described_class.new(repo_url: repo_url, dest_dir: dest_dir, max_bytes: max_bytes, timeout_seconds: 5)
      cloner_no_pr.call
      flat = @calls.map { |a| a.reject { |x| x.is_a?(Hash) } }
      expect(flat.none? { |c| c.include?('fetch') }).to be true
    end
  end
end
