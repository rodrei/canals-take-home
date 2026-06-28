module Authenticable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_customer!
  end

  private

  def current_customer
    @current_customer
  end

  def authenticate_customer!
    token = bearer_token
    @current_customer = Customer.find_by(auth_token: token) if token.present?
    return if @current_customer

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def bearer_token
    header = request.headers["Authorization"]
    return if header.blank?

    header.split(" ").last
  end
end
