module Orders
  class FulfillmentService
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return @order if @order.confirmed? || @order.unfulfillable?

      @order.start_processing! if @order.pending?

      reserve_stock! unless @order.warehouse_id.present?
      return @order if @order.unfulfillable?

      settle_payment!
      @order
    end

    private

    def reserve_stock!
      coords = geocode
      return mark_unfulfillable("unsupported shipping address") if coords.nil?

      order_items = @order.order_items.to_a
      eligible = WarehouseSelection::EligibleQuery.call(order_items)
      warehouse = WarehouseSelection::SelectService.call(
        warehouses: eligible, lat: coords[:lat], lng: coords[:lng]
      )
      return mark_unfulfillable("no warehouse can fulfill this order") if warehouse.nil?

      Order.transaction do
        inventories = Inventory
          .where(warehouse_id: warehouse.id, product_id: order_items.map(&:product_id))
          .lock("FOR UPDATE")
          .index_by(&:product_id)

        order_items.each do |item|
          inv = inventories[item.product_id]
          if inv.nil? || inv.quantity < item.quantity
            raise ActiveRecord::Rollback, :insufficient
          end
        end

        order_items.each do |item|
          inv = inventories[item.product_id]
          inv.update!(quantity: inv.quantity - item.quantity)
        end

        @order.update!(shipping_lat: coords[:lat], shipping_lng: coords[:lng], warehouse_id: warehouse.id)
      end

      # If the transaction rolled back, warehouse_id is still nil -> unfulfillable.
      mark_unfulfillable("warehouse stock changed before reservation") if @order.warehouse_id.blank?
    end

    def settle_payment!
      return if @order.payments.exists?(status: :succeeded)

      idempotency_key = "order-#{@order.id}-charge"
      begin
        provider_id = Payments::ChargeService.call(
          token: @order.payment_method_token,
          amount_cents: @order.total_cents,
          idempotency_key: idempotency_key,
          description: "Order #{@order.id}"
        )
        Order.transaction do
          @order.payments.create!(
            amount_cents: @order.total_cents, currency: @order.currency,
            status: :succeeded, provider_payment_id: provider_id, idempotency_key: idempotency_key
          )
          @order.mark_confirmed!(warehouse: @order.warehouse)
        end
      rescue Payments::PaymentDeclinedError => e
        Order.transaction do
          restore_stock!
          @order.payments.create!(
            amount_cents: @order.total_cents, currency: @order.currency,
            status: :failed, error_code: "declined", error_message: e.message,
            idempotency_key: idempotency_key
          )
          @order.mark_payment_failed!
        end
      end
    end

    def restore_stock!
      @order.order_items.each do |item|
        inv = Inventory.lock("FOR UPDATE").find_by(warehouse_id: @order.warehouse_id, product_id: item.product_id)
        inv&.update!(quantity: inv.quantity + item.quantity)
      end
    end

    def geocode
      Geocoding::GeocodeService.geocode(ship_address)
    rescue Geocoding::UnsupportedAddressError
      nil
    end

    def ship_address
      Address.new(
        line1: @order.ship_line1, line2: @order.ship_line2,
        city: @order.ship_city, state: @order.ship_state,
        postal_code: @order.ship_postal_code, country: @order.ship_country
      )
    end

    def mark_unfulfillable(reason)
      @order.mark_unfulfillable!(reason)
      @order
    end
  end
end
