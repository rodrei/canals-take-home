require "rails_helper"

RSpec.describe Payments::ChargeService do
  it "charges a valid token deterministically by idempotency key" do
    id1 = described_class.call(token: "pm_ok_abc", amount_cents: 1000, idempotency_key: "k1", description: "order 1")
    id2 = described_class.call(token: "pm_ok_abc", amount_cents: 1000, idempotency_key: "k1", description: "order 1")

    expect(id1).to eq("ch_k1")
    expect(id2).to eq(id1)
  end

  it "declines a decline token" do
    expect {
      described_class.call(token: "pm_decline_abc", amount_cents: 1000, idempotency_key: "k2", description: "order 2")
    }.to raise_error(Payments::PaymentDeclinedError)
  end
end
