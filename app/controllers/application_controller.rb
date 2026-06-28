class ApplicationController < ActionController::API
  include Authenticable

  # Generic framework errors are handled globally; domain/service-specific
  # errors are handled in the actions that invoke those services.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found(_error)
    render json: { error: "not found" }, status: :not_found
  end
end
