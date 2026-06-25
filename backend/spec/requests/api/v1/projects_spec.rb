require 'rails_helper'

RSpec.describe 'Api::V1::Projects', type: :request do
  let!(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/projects' do
    before { create_list(:project, 2, user: user) }

    it 'returns all projects for the current user' do
      get '/api/v1/projects', headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['projects'].size).to eq(2)
    end

    it 'does not return other users projects' do
      other_user = create(:user)
      create(:project, user: other_user)

      get '/api/v1/projects', headers: headers
      body = JSON.parse(response.body)
      expect(body['projects'].size).to eq(2)
    end

    it 'returns 401 without token' do
      get '/api/v1/projects'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/projects' do
    let(:valid_params) { { project: { name: 'My App', language: 'ruby', description: 'Test' } } }

    it 'creates a project and returns 201' do
      post '/api/v1/projects', params: valid_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['project']['name']).to eq('My App')
      expect(body['project']['language']).to eq('ruby')
      expect(body['project']['default_branch']).to eq('main')
      expect(body['project']).to have_key('submissions_count')
    end

    it 'returns 422 for invalid language' do
      post '/api/v1/projects',
           params: { project: { name: 'Test', language: 'cobol' } },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 for duplicate name scoped to user' do
      create(:project, user: user, name: 'My App')
      post '/api/v1/projects', params: valid_params, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/projects/:id' do
    let!(:project) { create(:project, user: user) }

    it 'returns the project' do
      get "/api/v1/projects/#{project.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['project']['id']).to eq(project.id)
    end

    it 'returns 404 for another users project' do
      other_project = create(:project)
      get "/api/v1/projects/#{other_project.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/projects/:id' do
    let!(:project) { create(:project, user: user) }

    it 'updates the project' do
      patch "/api/v1/projects/#{project.id}",
            params: { project: { description: 'Updated desc' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['project']['description']).to eq('Updated desc')
    end

    it 'returns 404 for another users project' do
      other_project = create(:project)
      patch "/api/v1/projects/#{other_project.id}",
            params: { project: { description: 'hack' } },
            headers: headers,
            as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/projects/:id' do
    let!(:project) { create(:project, user: user) }

    it 'deletes the project and returns 204' do
      delete "/api/v1/projects/#{project.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(Project.find_by(id: project.id)).to be_nil
    end

    it 'returns 404 for another users project' do
      other_project = create(:project)
      delete "/api/v1/projects/#{other_project.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
