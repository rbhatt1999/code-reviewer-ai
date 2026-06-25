module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      reject_unauthorized_connection unless current_user
    end

    private

    def find_verified_user
      token = request.params[:token].to_s
      return nil if token.empty?

      payload, = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY'), true, algorithm: 'HS256')
      User.find_by(id: payload['sub'])
    rescue JWT::DecodeError, JWT::ExpiredSignature
      nil
    end
  end
end
