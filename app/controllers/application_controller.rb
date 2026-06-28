class ApplicationController < ActionController::API
  include Authenticable

  rescue_from Orders::ValidationError, with: :render_unprocessable
  rescue_from Payments::InvalidCardError, with: :render_unprocessable
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_unprocessable(error)
    render json: { error: error.message }, status: :unprocessable_content
  end

  def render_not_found(_error)
    render json: { error: "not found" }, status: :not_found
  end
end
