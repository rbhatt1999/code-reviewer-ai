module Api
  module V1
    module Auth
      class RegistrationsController < Devise::RegistrationsController
        respond_to :json

        # The default create action calls sign_in after registration which can
        # attempt session writes. Override to let devise-jwt handle auth dispatch.
        def create
          build_resource(sign_up_params)
          resource.save
          if resource.persisted?
            sign_up(resource_name, resource)
            render json: { user: user_payload(resource) }, status: :ok
          else
            clean_up_passwords(resource)
            render json: { error: 'unprocessable', errors: resource.errors.as_json },
                   status: :unprocessable_entity
          end
        end

        private

        def sign_up_params
          params.require(:user).permit(:name, :email, :password)
        end

        def account_update_params
          params.require(:user).permit(:name, :email, :password, :current_password)
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
