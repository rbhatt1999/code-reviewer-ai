require 'rails_helper'

RSpec.describe Github::PullRequestFiles do
  let(:repo_url) { 'https://github.com/acme/widget' }
  let(:api_url)  { 'https://api.github.com/repos/acme/widget/pulls/7/files' }

  def build_service
    described_class.new(repo_url: repo_url, pr_number: 7)
  end

  describe '#call' do
    context 'happy path — two changed files, one binary' do
      before do
        stub_request(:get, api_url)
          .with(query: hash_including('per_page' => '100'))
          .to_return(
            status: 200,
            body: [
              {
                filename: 'app/models/user.rb', status: 'modified',
                additions: 3, deletions: 1,
                patch: "@@ -1,3 +1,3 @@\n def foo\n-  old\n+  new\n end"
              },
              {
                filename: 'app/assets/logo.png', status: 'modified',
                additions: 0, deletions: 0
                # no `patch` key — GitHub omits it for binary files
              }
            ].to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns only the file with a patch, mapped to FileDiff structs' do
        result = build_service.call

        expect(result.files.size).to eq(1)
        file = result.files.first
        expect(file.filename).to eq('app/models/user.rb')
        expect(file.status).to eq('modified')
        expect(file.additions).to eq(3)
        expect(file.deletions).to eq(1)
        expect(file.patch).to include('+  new')
      end
    end

    context 'repo not found / private (404)' do
      before { stub_request(:get, api_url).to_return(status: 404, body: '{}') }

      it 'returns an empty result, raises nothing' do
        expect(build_service.call.files).to eq([])
      end
    end

    context 'rate limited (403)' do
      before { stub_request(:get, api_url).to_return(status: 403, body: '{"message":"rate limit"}') }

      it 'returns an empty result, raises nothing' do
        expect(build_service.call.files).to eq([])
      end
    end

    context 'network error' do
      before { stub_request(:get, api_url).to_raise(Faraday::ConnectionFailed.new('refused')) }

      it 'returns an empty result, raises nothing' do
        expect(build_service.call.files).to eq([])
      end
    end

    context 'malformed repo_url' do
      let(:repo_url) { 'not-a-url' }

      it 'returns an empty result without making an HTTP call' do
        result = build_service.call
        expect(result.files).to eq([])
        expect(WebMock).not_to have_requested(:get, api_url)
      end
    end

    context 'repo_url with a trailing .git and slash' do
      let(:repo_url) { 'https://github.com/acme/widget.git/' }

      before do
        stub_request(:get, api_url).to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })
      end

      it 'still resolves owner/repo correctly' do
        build_service.call
        expect(WebMock).to have_requested(:get, api_url)
      end
    end
  end
end
