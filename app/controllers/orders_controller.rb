class OrdersController < ApplicationController
  def create
    order = Orders::CreateService.call(customer: current_customer, params: order_params)
    render json: OrderSerializer.call(order), status: :created
  end

  def show
    order = current_customer.orders.find(params[:id])
    render json: OrderSerializer.call(order), status: :ok
  end

  private

  def order_params
    params.require(:order).permit(
      shipping_address: [:line1, :line2, :city, :state, :postal_code, :country],
      payment: [:card_number],
      items: [:product_id, :quantity]
    )
  end
end
