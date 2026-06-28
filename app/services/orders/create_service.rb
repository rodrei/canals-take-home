module Orders
  # Synchronous order-creation path. Validates input, confirms the address is a
  # supported US address, snapshots prices, tokenizes the card (real billing
  # validation), persists a pending order, and enqueues asynchronous
  # fulfillment. Does NOT geocode-to-coordinates or charge — those happen in the
  # fulfillment job.
  class CreateService
    def self.call(customer:, params:)
      new(customer: customer, params: params).call
    end

    def initialize(customer:, params:)
      @customer = customer
      @params = params.to_h.with_indifferent_access
    end

    def call
      validate_address!
      line_items = build_line_items! # [{ product:, quantity:, unit_price_cents: }]
      token = Payments::TokenizeService.call(card_number)

      order = Order.create!(
        customer: @customer,
        status: :pending,
        ship_line1: address[:line1], ship_line2: address[:line2],
        ship_city: address[:city], ship_state: address[:state],
        ship_postal_code: address[:postal_code], ship_country: address[:country],
        total_cents: line_items.sum { |li| li[:unit_price_cents] * li[:quantity] },
        currency: "USD",
        payment_method_token: token
      )

      line_items.each do |li|
        order.order_items.create!(
          product: li[:product], quantity: li[:quantity], unit_price_cents: li[:unit_price_cents]
        )
      end

      Orders::FulfillmentJob.perform_later(order.id)
      order
    end

    private

    def address
      @address ||= (@params[:shipping_address] || {}).with_indifferent_access
    end

    def card_number
      (@params[:payment] || {}).with_indifferent_access[:card_number]
    end

    def validate_address!
      # Reuse the geocoder's US/state validation; full coordinates come later.
      Geocoding::GeocodeService.call(address)
    rescue Geocoding::UnsupportedAddressError => e
      raise ValidationError, e.message
    end

    def build_line_items!
      items = @params[:items]
      raise ValidationError, "items required" if items.blank?

      items.map do |item|
        product = Product.find_by(id: item[:product_id])
        raise ValidationError, "unknown product: #{item[:product_id]}" unless product

        quantity = item[:quantity].to_i
        raise ValidationError, "quantity must be positive" unless quantity.positive?

        { product: product, quantity: quantity, unit_price_cents: product.price_cents }
      end
    end
  end
end
