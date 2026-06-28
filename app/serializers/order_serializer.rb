class OrderSerializer
  def self.call(order)
    {
      order: {
        id: order.id,
        status: order.status,
        total_cents: order.total_cents,
        currency: order.currency,
        warehouse_id: order.warehouse_id,
        failure_reason: order.failure_reason,
        items: order.order_items.map do |item|
          { product_id: item.product_id, quantity: item.quantity, unit_price_cents: item.unit_price_cents }
        end,
        latest_payment_status: order.payments.order(:created_at).last&.status
      }
    }
  end
end
