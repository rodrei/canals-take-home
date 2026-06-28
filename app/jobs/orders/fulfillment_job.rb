module Orders
  class FulfillmentJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      # Real body added in Task 10.
    end
  end
end
