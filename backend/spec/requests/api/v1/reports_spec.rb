require 'rails_helper'

RSpec.describe 'Api::V1::Reports', type: :request do
  let!(:user)       { create(:user) }
  let!(:project)    { create(:project, user: user) }
  let!(:submission) { create(:submission, :with_issues, user: user, project: project) }
  let!(:review)     { create(:review, submission: submission, mode: :hybrid, total_issues: 2) }
  let(:headers)     { auth_headers_for(user) }

  it 'exports JSON' do
    get "/api/v1/submissions/#{submission.id}/report.json", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/json')
    expect(response.headers['Content-Disposition']).to include("review-#{submission.id}.json")
    expect(JSON.parse(response.body)['issues'].size).to eq(2)
  end

  it 'exports Markdown' do
    get "/api/v1/submissions/#{submission.id}/report.md", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/markdown')
  end

  it 'exports PDF (renderer stubbed)' do
    allow_any_instance_of(Reports::PdfRenderer).to receive(:call).and_return("%PDF-1.4\nstub")
    get "/api/v1/submissions/#{submission.id}/report.pdf", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    expect(response.body).to start_with('%PDF')
  end

  it '422 for a non-completed submission' do
    pending_sub = create(:submission, user: user, project: project)
    get "/api/v1/submissions/#{pending_sub.id}/report.json", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it '404 for another users submission' do
    other = create(:submission, :completed)
    get "/api/v1/submissions/#{other.id}/report.json", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it '401 without auth' do
    get "/api/v1/submissions/#{submission.id}/report.json"
    expect(response).to have_http_status(:unauthorized)
  end
end
