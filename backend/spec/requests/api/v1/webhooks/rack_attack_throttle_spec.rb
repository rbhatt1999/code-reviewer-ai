require 'rails_helper'

RSpec.describe 'Webhook throttling', type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
    begin
      example.run
    ensure
      Rack::Attack.enabled = false
      Rack::Attack.cache.store.clear
    end
  end

  it 'returns 429 after exceeding the per-IP limit' do
    body = { repository: { clone_url: 'https://github.com/x/y.git' },
             pull_request: { number: 1, head: { sha: 'abc' } } }.to_json
    headers = { 'CONTENT_TYPE' => 'application/json' } # unsigned: controller 401s, throttle still counts

    61.times { post '/api/v1/webhooks/github', params: body, headers: headers }
    expect(response).to have_http_status(:too_many_requests)
  end
end
