require 'rails_helper'

RSpec.describe 'Api::V1::Auth', type: :request do
  describe 'POST /api/v1/auth (register)' do
    let(:valid_params) do
      { user: { name: 'Test User', email: 'test@example.com', password: 'password123' } }
    end

    context 'with valid params' do
      it 'returns 200 with user payload and JWT token' do
        post '/api/v1/auth', params: valid_params, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.headers['Authorization']).to be_present
        expect(response.headers['Authorization']).to match(/^Bearer /)

        body = JSON.parse(response.body)
        expect(body['user']).to include('id', 'email', 'name', 'role')
        expect(body['user']['email']).to eq('test@example.com')
        expect(body['user']['name']).to eq('Test User')
        expect(body['user']['role']).to eq('reviewer')
      end
    end

    context 'with missing name' do
      it 'returns 422' do
        post '/api/v1/auth',
             params: { user: { email: 'test@example.com', password: 'password123' } },
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with duplicate email' do
      before { create(:user, email: 'test@example.com') }

      it 'returns 422' do
        post '/api/v1/auth', params: valid_params, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/auth/sign_in' do
    let!(:user) { create(:user, email: 'login@example.com', password: 'password123') }

    context 'with valid credentials' do
      it 'returns 200 with JWT token in Authorization header' do
        post '/api/v1/auth/sign_in',
             params: { user: { email: 'login@example.com', password: 'password123' } },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(response.headers['Authorization']).to match(/^Bearer /)

        body = JSON.parse(response.body)
        expect(body['user']['email']).to eq('login@example.com')
      end
    end

    context 'with invalid password' do
      it 'returns 401' do
        post '/api/v1/auth/sign_in',
             params: { user: { email: 'login@example.com', password: 'wrongpass' } },
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with unknown email' do
      it 'returns 401' do
        post '/api/v1/auth/sign_in',
             params: { user: { email: 'nobody@example.com', password: 'password123' } },
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/auth/sign_out' do
    let!(:user) { create(:user) }

    context 'with a valid token' do
      it 'returns 204' do
        headers = auth_headers_for(user)
        delete '/api/v1/auth/sign_out', headers: headers
        expect(response).to have_http_status(:no_content)
      end
    end

    context 'without a token' do
      # Devise sign_out is idempotent — with no token there's nothing to revoke;
      # it returns 204 (no content) rather than 401.
      it 'returns 204' do
        delete '/api/v1/auth/sign_out'
        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe 'GET /api/v1/auth/me' do
    let!(:user) { create(:user) }

    context 'with a valid token' do
      it 'returns the current user' do
        headers = auth_headers_for(user)
        get '/api/v1/auth/me', headers: headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['user']['email']).to eq(user.email)
        expect(body['user']['name']).to eq(user.name)
      end
    end

    context 'without a token' do
      it 'returns 401' do
        get '/api/v1/auth/me'
        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('unauthenticated')
      end
    end
  end
end
