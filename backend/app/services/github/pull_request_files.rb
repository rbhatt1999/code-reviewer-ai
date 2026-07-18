require 'faraday'

module Github
  # Fetches the list of changed files (with unified-diff patches) for a pull
  # request from GitHub's public REST API — no auth token, so this only works
  # for public repos (same scope as the rest of the git-based ingestion).
  # Used to seed LLM::ReviewService with "review these changes first" instead
  # of the whole repo, mirroring how GitHub Copilot's own PR review works:
  # start from the diff, let the agent read more files if it needs to.
  class PullRequestFiles
    Result  = Struct.new(:files, keyword_init: true)
    FileDiff = Struct.new(:filename, :status, :patch, :additions, :deletions, keyword_init: true)

    API_BASE        = 'https://api.github.com'.freeze
    PER_PAGE        = 100
    DEFAULT_TIMEOUT = 10

    def initialize(repo_url:, pr_number:, timeout_seconds: DEFAULT_TIMEOUT)
      @repo_url        = repo_url.to_s
      @pr_number       = pr_number.to_s
      @timeout_seconds = timeout_seconds
    end

    # Never raises — a failed/rate-limited/private-repo lookup just yields no
    # files, and callers fall back to full-tree review instead of failing.
    def call
      owner_repo = parse_owner_repo(@repo_url)
      return Result.new(files: []) unless owner_repo

      resp = connection.get("/repos/#{owner_repo}/pulls/#{@pr_number}/files") do |req|
        req.params['per_page'] = PER_PAGE
        req.headers['Accept']     = 'application/vnd.github+json'
        req.headers['User-Agent'] = 'CodeReviewerAI'
      end
      return Result.new(files: []) unless resp.success?

      data = JSON.parse(resp.body)
      Result.new(files: data.filter_map { |raw| build_file_diff(raw) })
    rescue StandardError => e
      Rails.logger.warn("[Github::PullRequestFiles] error (non-fatal): #{e.class} — #{e.message}")
      Result.new(files: [])
    end

    private

    # Binary files (images, etc.) have no `patch` field — skip them, there's
    # nothing meaningful to review as a text diff.
    def build_file_diff(raw)
      return nil if raw['patch'].nil?

      FileDiff.new(
        filename: raw['filename'],
        status: raw['status'],
        patch: raw['patch'],
        additions: raw['additions'],
        deletions: raw['deletions']
      )
    end

    # https://github.com/owner/repo(.git)?(/)? -> "owner/repo"
    # Order matters: strip the trailing slash BEFORE the .git suffix, since a
    # URL can end in ".git/" — stripping .git first would never match that.
    def parse_owner_repo(url)
      clean = url.to_s.strip.sub(%r{/\z}, '').sub(/\.git\z/, '')
      segments = clean.split('/').last(2)
      return nil if segments.size != 2 || segments.any?(&:empty?)

      segments.join('/')
    end

    def connection
      @connection ||= Faraday.new(url: API_BASE) do |f|
        f.options.timeout      = @timeout_seconds
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end
  end
end
