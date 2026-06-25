module Api
  module V1
    module Auth
      class ProfilesController < ApplicationController
        def show
          render json: {
            user: {
              id: current_user.id,
              email: current_user.email,
              name: current_user.name,
              role: current_user.role
            }
          }, status: :ok
        end
      end
    end
  end
end
