require "rails_helper"

RSpec.describe Orders::CreateService do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, price_cents: 1_000) }

  def params(overrides = {})
    {
      shipping_address: { line1: "1 Main", city: "New York", state: "NY", postal_code: "10001", country: "US" },
      items: [{ product_id: product.id, quantity: 2 }],
      payment: { card_number: "4111111111111111" }
    }.merge(overrides)
  end

  it "creates a pending order with snapshotted prices and a token" do
    order = nil
    expect {
      order = described_class.call(customer: customer, params: params)
    }.to change(Order, :count).by(1)

    expect(order).to be_pending
    expect(order.total_cents).to eq(2_000)
    expect(order.order_items.first.unit_price_cents).to eq(1_000)
    expect(order.payment_method_token).to start_with("pm_ok_")
  end

  it "enqueues the fulfillment job" do
    expect {
      described_class.call(customer: customer, params: params)
    }.to have_enqueued_job(Orders::FulfillmentJob)
  end

  it "rejects an unsupported (non-US) address" do
    bad = params(shipping_address: { line1: "1", city: "Toronto", state: "ON", postal_code: "M5V", country: "CA" })
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Orders::ValidationError)
  end

  it "rejects an unknown product" do
    bad = params(items: [{ product_id: -1, quantity: 1 }])
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Orders::ValidationError)
  end

  it "rejects an invalid card" do
    bad = params(payment: { card_number: "1234567812345678" })
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Orders::ValidationError)
  end

  it "raises ValidationError (not RecordInvalid) when a required field is missing" do
    bad = params(shipping_address: { line1: "1", state: "NY", postal_code: "10001", country: "US" }) # no city
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Orders::ValidationError)
  end
end
