module Orders
  class FulfillmentJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find(order_id)
      Orders::FulfillmentService.call(order)
    end
  end
end
