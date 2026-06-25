module Api
  module V1
    class HealthController < ApplicationController
      skip_before_action :authenticate_user!

      def show
        render json: { status: 'ok', version: '1.0.0' }, status: :ok
      end
    end
  end
end
