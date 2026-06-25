module Api
  module V1
    module Auth
      class SessionsController < Devise::SessionsController
        respond_to :json

        private

        def respond_with(resource, _opts = {})
          render json: { user: user_payload(resource) }, status: :ok
        end

        def respond_to_on_destroy
          head :no_content
        end

        def user_payload(user)
          {
            id: user.id,
            email: user.email,
            name: user.name,
            role: user.role
          }
        end
      end
    end
  end
end
