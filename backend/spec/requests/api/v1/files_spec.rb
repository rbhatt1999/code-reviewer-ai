require 'rails_helper'

RSpec.describe 'Api::V1::Files', type: :request do
  let(:user)       { create(:user) }
  let(:submission) { create(:submission, user: user, blob_path: '/tmp/placeholder', language: 'ruby') }
  let(:headers)    { auth_headers_for(user) }

  let(:tmpdir) { Dir.mktmpdir }

  before do
    File.write(File.join(tmpdir, 'app.rb'), "puts 'hello'\n")
    submission.update!(blob_path: tmpdir)
  end

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe 'GET /api/v1/submissions/:id/files (index)' do
    it 'returns 200 with the list of servable files for the owner' do
      get "/api/v1/submissions/#{submission.id}/files", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['files']).to include('path' => 'app.rb')
    end

    it 'returns 401 when unauthenticated' do
      get "/api/v1/submissions/#{submission.id}/files"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for a submission owned by another user' do
      other_submission = create(:submission, blob_path: tmpdir)
      get "/api/v1/submissions/#{other_submission.id}/files", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/submissions/:id/files/:path (show)' do
    it 'returns 200 with file content for the owner' do
      get "/api/v1/submissions/#{submission.id}/files/app.rb", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['path']).to eq('app.rb')
      expect(body['language']).to eq('ruby')
      expect(body['content']).to eq("puts 'hello'\n")
    end

    it 'returns 401 when unauthenticated' do
      get "/api/v1/submissions/#{submission.id}/files/app.rb"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for a submission owned by another user' do
      other_submission = create(:submission, blob_path: tmpdir)
      get "/api/v1/submissions/#{other_submission.id}/files/app.rb", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 on path traversal attempt' do
      get "/api/v1/submissions/#{submission.id}/files/..%2F..%2Fetc%2Fpasswd", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 413 for a file exceeding MAX_VIEW_BYTES' do
      large_file = File.join(tmpdir, 'big.rb')
      File.write(large_file, 'x' * 1_000_001)

      get "/api/v1/submissions/#{submission.id}/files/big.rb", headers: headers

      expect(response).to have_http_status(:payload_too_large)
    end

    it 'returns 415 for an unsupported file extension' do
      File.write(File.join(tmpdir, 'image.png'), '')

      get "/api/v1/submissions/#{submission.id}/files/image.png", headers: headers

      expect(response).to have_http_status(:unsupported_media_type)
    end
  end
end
