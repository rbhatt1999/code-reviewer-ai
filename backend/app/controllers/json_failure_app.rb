class JsonFailureApp < Devise::FailureApp
  def respond
    self.status        = 401
    self.content_type  = 'application/json'
    self.response_body = { error: 'unauthenticated', message: i18n_message }.to_json
  end
end
