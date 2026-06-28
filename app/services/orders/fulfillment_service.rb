module Orders
  # Asynchronous fulfillment pipeline.
  #
  # The external charge MUST NOT happen inside an open DB transaction (holding
  # row locks across network I/O is a production hazard). So this runs as two
  # transactions with a compensating action:
  #   Tx A  - lock inventory rows, verify stock, atomic decrement, set warehouse
  #   charge - call the provider (no transaction)
  #   Tx B  - settle: confirm, OR restore stock + mark payment_failed
  #
  # Idempotent on Sidekiq retry: skips Tx A if a warehouse is already assigned,
  # and skips the charge if a succeeded payment already exists.
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
      return @order if @order.unfulfillable? # reserve_stock! may have marked it

      settle_payment!
      @order
    end

    private

    def reserve_stock!
      coords = geocode
      return mark_unfulfillable("unsupported shipping address") if coords.nil?

      item_quantities = @order.order_items.pluck(:product_id, :quantity).to_h
      eligible = WarehouseSelection::EligibleQuery.call(item_quantities)
      warehouse = WarehouseSelection::SelectService.call(
        warehouses: eligible, lat: coords[:lat], lng: coords[:lng]
      )
      return mark_unfulfillable("no warehouse can fulfill this order") if warehouse.nil?

      Order.transaction do
        inventories = Inventory
          .where(warehouse_id: warehouse.id, product_id: item_quantities.keys)
          .lock("FOR UPDATE")
          .index_by(&:product_id)

        item_quantities.each do |product_id, quantity|
          inv = inventories[product_id]
          if inv.nil? || inv.quantity < quantity
            raise ActiveRecord::Rollback, :insufficient
          end
        end

        item_quantities.each do |product_id, quantity|
          inv = inventories[product_id]
          inv.update!(quantity: inv.quantity - quantity)
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
      Geocoding::GeocodeService.call(
        city: @order.ship_city, state: @order.ship_state,
        postal_code: @order.ship_postal_code, country: @order.ship_country
      )
    rescue Geocoding::UnsupportedAddressError
      nil
    end

    def mark_unfulfillable(reason)
      @order.mark_unfulfillable!(reason)
      @order
    end
  end
end
