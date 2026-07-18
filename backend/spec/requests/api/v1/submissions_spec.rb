require 'rails_helper'

RSpec.describe 'Api::V1::Submissions', type: :request do
  let!(:user) { create(:user) }
  let!(:project) { create(:project, user: user) }
  let(:headers) { auth_headers_for(user) }

  describe 'POST /api/v1/projects/:project_id/submissions (single_file)' do
    let(:ruby_content) { "x = \"hello\"\nputs x\n" }
    let(:file) do
      Rack::Test::UploadedFile.new(
        StringIO.new(ruby_content), 'text/plain', original_filename: 'test_file.rb'
      )
    end

    it 'creates a submission in pending state and returns 201' do
      post "/api/v1/projects/#{project.id}/submissions",
           params: { submission: { kind: 'single_file', file: file } },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['submission']['status']).to eq('pending')
      expect(body['submission']['language']).to eq('ruby')
      expect(body['submission']['kind']).to eq('single_file')
      expect(body['submission']).to have_key('issues_count')
      expect(body['submission']['activity_log'].first).to include('message' => 'Queued for review')
    end

    it 'enqueues IngestJob for the created submission' do
      expect do
        post "/api/v1/projects/#{project.id}/submissions",
             params: { submission: { kind: 'single_file', file: file } },
             headers: headers
      end.to have_enqueued_job(IngestJob)
    end

    it 'returns 404 for a non-owned project' do
      other_project = create(:project)
      post "/api/v1/projects/#{other_project.id}/submissions",
           params: { submission: { kind: 'single_file', file: file } },
           headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/projects/:project_id/submissions (paste)' do
    it 'creates a submission from pasted content in pending state' do
      post "/api/v1/projects/#{project.id}/submissions",
           params: { submission: { kind: 'paste', content: "puts 'hello'", language: 'ruby' } },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['submission']['kind']).to eq('paste')
      expect(body['submission']['language']).to eq('ruby')
      expect(body['submission']['status']).to eq('pending')
    end

    it 'returns 400 when content is missing for paste kind' do
      post "/api/v1/projects/#{project.id}/submissions",
           params: { submission: { kind: 'paste', language: 'ruby' } },
           headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe '5 MB file size limit' do
    it 'rejects submissions over MAX_UPLOAD_BYTES' do
      big_content = 'x' * 5_242_881
      big_file = Rack::Test::UploadedFile.new(
        StringIO.new(big_content), 'text/plain', original_filename: 'huge.rb'
      )

      post "/api/v1/projects/#{project.id}/submissions",
           params: { submission: { kind: 'single_file', file: big_file } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/projects/:project_id/submissions (index)' do
    before { create_list(:submission, 2, :completed, project: project, user: user) }

    it 'returns submissions for the project' do
      get "/api/v1/projects/#{project.id}/submissions", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['submissions'].size).to eq(2)
    end
  end

  describe 'GET /api/v1/submissions/:id' do
    let!(:submission) { create(:submission, :completed, user: user, project: project) }

    it 'returns the submission' do
      get "/api/v1/submissions/#{submission.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['submission']['id']).to eq(submission.id)
    end

    it 'returns persisted activity history' do
      submission.update!(activity_log: [
                           { 'type' => 'read_file', 'message' => 'AI read app/models/user.rb',
                             'file' => 'app/models/user.rb', 'created_at' => '2026-07-19T01:00:00Z' }
                         ])

      get "/api/v1/submissions/#{submission.id}", headers: headers

      activity = JSON.parse(response.body).dig('submission', 'activity_log')
      expect(activity).to eq([
                               {
                                 'type' => 'read_file',
                                 'message' => 'AI read app/models/user.rb',
                                 'file' => 'app/models/user.rb',
                                 'created_at' => '2026-07-19T01:00:00Z'
                               }
                             ])
    end

    it 'returns 404 for another users submission' do
      other_sub = create(:submission)
      get "/api/v1/submissions/#{other_sub.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/submissions/:id/issues' do
    let!(:submission) { create(:submission, :completed, user: user, project: project) }
    let!(:issue) { create(:issue, :linter, submission: submission) }

    it 'returns issues for the submission' do
      get "/api/v1/submissions/#{submission.id}/issues", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['issues'].size).to eq(1)
      expect(body['issues'].first).to include('rule_id', 'severity', 'category', 'message')
    end

    it 'returns 404 for another users submission' do
      other_sub = create(:submission)
      get "/api/v1/submissions/#{other_sub.id}/issues", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/submissions/:id/review' do
    let!(:submission) { create(:submission, :completed, user: user, project: project) }
    let!(:review) { create(:review, submission: submission, mode: :linter_only, total_issues: 1) }

    it 'returns the review' do
      get "/api/v1/submissions/#{submission.id}/review", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['review']['mode']).to eq('linter_only')
      expect(body['review']['total_issues']).to eq(1)
    end

    it 'returns 404 when no review exists' do
      sub_no_review = create(:submission, :pending, user: user, project: project)
      get "/api/v1/submissions/#{sub_no_review.id}/review", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
