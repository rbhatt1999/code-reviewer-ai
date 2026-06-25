require 'rails_helper'

RSpec.describe 'Api::V1::Webhooks::Github', type: :request do
  let!(:project) { create(:project, :with_webhook) }
  let(:secret)   { 'shh-secret' }

  def payload_for(clone_url: 'https://github.com/acme/widget.git', pr: 7, sha: 'deadbeef1234')
    { repository: { clone_url: clone_url }, pull_request: { number: pr, head: { sha: sha } } }.to_json
  end

  def sig(body, key = secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, body)}"
  end

  it 'accepts a valid signed pull_request and enqueues IngestJob' do
    body = payload_for
    expect do
      post '/api/v1/webhooks/github', params: body,
           headers: { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    end.to have_enqueued_job(IngestJob)
    expect(response).to have_http_status(:accepted)
    sub = project.submissions.kind_github_webhook.last
    expect(sub.source_ref).to eq('PR#7@deadbeef1234')
  end

  it 'normalizes .git / trailing slash when matching the project' do
    body = payload_for(clone_url: 'https://github.com/ACME/widget/')
    post '/api/v1/webhooks/github', params: body,
         headers: { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:accepted)
  end

  it 'disambiguates by secret when two projects share the same repo_url' do
    decoy = create(:project, :with_webhook, webhook_secret: 'other-secret')
    body  = payload_for
    post '/api/v1/webhooks/github', params: body,
         headers: { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:accepted)
    expect(project.submissions.kind_github_webhook.count).to eq(1)
    expect(decoy.submissions.kind_github_webhook.count).to eq(0)
  end

  it 'stores the trusted project.repo_url (not the payload clone_url) for cloning (SSRF guard)' do
    body = payload_for(clone_url: 'https://github.com/acme/widget.git')
    post '/api/v1/webhooks/github', params: body,
         headers: { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    sub        = project.submissions.kind_github_webhook.last
    stored_url = File.read(sub.blob_path).lines.first.strip
    expect(stored_url).to eq(project.repo_url)
    expect(stored_url).not_to include('.git')
  end

  it 'is idempotent on redelivery (200, no second enqueue)' do
    body = payload_for
    h    = { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    post '/api/v1/webhooks/github', params: body, headers: h
    expect do
      post '/api/v1/webhooks/github', params: body, headers: h
    end.not_to have_enqueued_job(IngestJob)
    expect(response).to have_http_status(:ok)
  end

  it '401 on bad signature' do
    body = payload_for
    post '/api/v1/webhooks/github', params: body,
         headers: { 'X-Hub-Signature-256' => sig(body, 'wrong'), 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  it '401 when no project matches the repo' do
    body = payload_for(clone_url: 'https://github.com/unknown/repo.git')
    post '/api/v1/webhooks/github', params: body,
         headers: { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  it '401 when the project has a blank webhook_secret' do
    project.update!(webhook_secret: nil)
    body = payload_for
    post '/api/v1/webhooks/github', params: body,
         headers: { 'X-Hub-Signature-256' => sig(body), 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end
end
