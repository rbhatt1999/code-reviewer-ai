class ApplicationController < ActionController::API
  before_action :authenticate_user!

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: 'not_found', message: e.message }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: 'unprocessable', errors: e.record.errors.as_json }, status: :unprocessable_entity
  end

  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: 'bad_request', message: e.message }, status: :bad_request
  end
end
