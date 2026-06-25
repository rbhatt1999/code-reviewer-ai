require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Metrics', type: :request do
  let(:admin)    { create(:user, :admin) }
  let(:reviewer) { create(:user) }

  before do
    stats = instance_double(Sidekiq::Stats, processed: 10, failed: 1, enqueued: 2,
                                            scheduled_size: 0, retry_size: 0)
    allow(Sidekiq::Stats).to receive(:new).and_return(stats)
  end

  it 'returns metrics for an admin' do
    create(:submission, :completed)
    get '/api/v1/admin/metrics', headers: auth_headers_for(admin)
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['metrics']).to include('submissions', 'issues', 'users', 'sidekiq')
    expect(body['metrics']['sidekiq']['processed']).to eq(10)
  end

  it '403 for a non-admin' do
    get '/api/v1/admin/metrics', headers: auth_headers_for(reviewer)
    expect(response).to have_http_status(:forbidden)
  end

  it '401 without auth' do
    get '/api/v1/admin/metrics'
    expect(response).to have_http_status(:unauthorized)
  end
end
