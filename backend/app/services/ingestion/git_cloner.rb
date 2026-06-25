require 'open3'
require 'timeout'
require 'fileutils'

module Ingestion
  # Raised when the git subprocess exits non-zero.
  class CloneFailed < StandardError; end

  # Raised when the cloned/extracted tree exceeds the configured byte limit.
  class SizeLimitExceeded < StandardError; end

  class GitCloner
    Result = Struct.new(:commit_sha, :total_bytes, :files, keyword_init: true)

    DEFAULT_MAX_BYTES     = ENV.fetch('MAX_UPLOAD_BYTES', 5_242_880).to_i
    DEFAULT_TIMEOUT       = 30
    HTTPS_ONLY_PATTERN    = %r{\Ahttps://}

    def initialize(repo_url:, dest_dir:, max_bytes: DEFAULT_MAX_BYTES, timeout_seconds: DEFAULT_TIMEOUT, pr_number: nil)
      @repo_url        = repo_url.to_s.strip
      @dest_dir        = dest_dir.to_s
      @max_bytes       = max_bytes
      @timeout_seconds = timeout_seconds
      @pr_number       = pr_number.to_s.strip.presence
    end

    def call
      validate_url!

      # git clone requires dest_dir to be absent or empty; mkdir_p the parent only.
      FileUtils.mkdir_p(File.dirname(@dest_dir))

      clone!
      checkout_pr_head! if @pr_number

      total_bytes, files = measure_tree
      if total_bytes > @max_bytes
        FileUtils.rm_rf(@dest_dir)
        raise SizeLimitExceeded,
              "Cloned tree (#{total_bytes} bytes) exceeds limit of #{@max_bytes} bytes"
      end

      sha = head_sha

      Result.new(commit_sha: sha, total_bytes: total_bytes, files: files)
    end

    private

    def validate_url!
      return if @repo_url.match?(HTTPS_ONLY_PATTERN)

      raise ArgumentError, "Only HTTPS clone URLs are permitted (got: #{@repo_url})"
    end

    def clone!
      _, stderr, status = Timeout.timeout(@timeout_seconds) do
        Open3.capture3(
          { 'GIT_TERMINAL_PROMPT' => '0' },
          'git', 'clone', '--depth', '1', @repo_url, @dest_dir.to_s
        )
      end

      return if status.exitstatus.zero?

      excerpt = stderr.to_s.lines.first(5).join.strip
      raise CloneFailed, "git clone failed (exit #{status.exitstatus}): #{excerpt}"
    end

    def measure_tree
      files       = []
      total_bytes = 0

      Dir.glob('**/*', base: @dest_dir).each do |rel|
        full = File.join(@dest_dir, rel)
        next unless File.file?(full)

        total_bytes += File.size(full)
        files << rel
      end

      [total_bytes, files]
    end

    def checkout_pr_head!
      ref = "pull/#{@pr_number}/head"
      # brakeman:ignore:CommandInjection -- Open3 array args are never shell-expanded; ref contains
      # only the integer pr_number (cast in GithubController before storage in the meta file).
      _o, fe, fs = Open3.capture3(
        { 'GIT_TERMINAL_PROMPT' => '0' },
        'git', '-C', @dest_dir.to_s, 'fetch', '--depth', '1', 'origin', ref
      )
      raise CloneFailed, "git fetch #{ref} failed: #{fe.to_s.lines.first(3).join.strip}" unless fs.exitstatus.zero?

      _o2, ce, cs = Open3.capture3('git', '-C', @dest_dir.to_s, 'checkout', 'FETCH_HEAD')
      return if cs.exitstatus.zero?

      raise CloneFailed, "git checkout FETCH_HEAD failed: #{ce.to_s.lines.first(3).join.strip}"
    end

    def head_sha
      stdout, _stderr, status = Open3.capture3('git', '-C', @dest_dir, 'rev-parse', 'HEAD')
      status.exitstatus.zero? ? stdout.strip : nil
    rescue StandardError
      nil
    end
  end
end
