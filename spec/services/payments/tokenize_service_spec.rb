require "rails_helper"

RSpec.describe Payments::TokenizeService do
  it "tokenizes a valid card" do
    token = described_class.call("4111111111111111")
    expect(token).to start_with("pm_ok_")
  end

  it "marks the designated decline card" do
    token = described_class.call("4000000000000002")
    expect(token).to start_with("pm_decline_")
  end

  it "raises on a Luhn-invalid card" do
    expect { described_class.call("1234567812345678") }
      .to raise_error(Payments::InvalidCardError)
  end
end
