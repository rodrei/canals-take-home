require "rails_helper"

RSpec.describe Orders::FulfillmentService do
  let(:product) { create(:product, price_cents: 1_000) }

  def build_order(card_token:, quantity: 2)
    order = create(:order, status: :pending, payment_method_token: card_token, total_cents: 1_000 * quantity,
                           ship_state: "NY", ship_country: "US", ship_postal_code: "10001", ship_city: "New York")
    create(:order_item, order: order, product: product, quantity: quantity, unit_price_cents: 1_000)
    order
  end

  it "confirms the order and decrements stock at the nearest eligible warehouse" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)
    inv = create(:inventory, warehouse: near, product: product, quantity: 10)
    order = build_order(card_token: "pm_ok_x")

    described_class.call(order)

    expect(order.reload).to be_confirmed
    expect(order.warehouse).to eq(near)
    expect(inv.reload.quantity).to eq(8)
    expect(order.payments.where(status: :succeeded).count).to eq(1)
  end

  it "marks unfulfillable when no warehouse can fill the order" do
    create(:inventory, warehouse: create(:warehouse), product: product, quantity: 1)
    order = build_order(card_token: "pm_ok_x", quantity: 5)

    described_class.call(order)

    expect(order.reload).to be_unfulfillable
    expect(order.failure_reason).to be_present
  end

  it "restores stock and marks payment_failed on a declined charge" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)
    inv = create(:inventory, warehouse: near, product: product, quantity: 10)
    order = build_order(card_token: "pm_decline_x")

    described_class.call(order)

    expect(order.reload).to be_payment_failed
    expect(inv.reload.quantity).to eq(10) # restored
    expect(order.payments.where(status: :failed).count).to eq(1)
  end

  it "does not double-charge or double-decrement when re-run after success" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)
    inv = create(:inventory, warehouse: near, product: product, quantity: 10)
    order = build_order(card_token: "pm_ok_x")

    described_class.call(order)
    described_class.call(order.reload) # simulate Sidekiq retry

    expect(inv.reload.quantity).to eq(8)        # decremented once
    expect(order.payments.count).to eq(1)       # charged once
    expect(order.reload).to be_confirmed
  end
end
