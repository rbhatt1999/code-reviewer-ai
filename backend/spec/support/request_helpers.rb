module RequestHelpers
  def auth_headers_for(user)
    post '/api/v1/auth/sign_in',
         params: { user: { email: user.email, password: 'password123' } },
         as: :json
    token = response.headers['Authorization']
    { 'Authorization' => token }
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
