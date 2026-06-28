require "rails_helper"

RSpec.describe Address do
  it "builds from a params hash" do
    address = described_class.from_params(
      line1: "1 Main", city: "New York", state: "NY", postal_code: "10001", country: "US"
    )

    expect(address.line1).to eq("1 Main")
    expect(address.city).to eq("New York")
    expect(address.state).to eq("NY")
    expect(address.postal_code).to eq("10001")
    expect(address.country).to eq("US")
  end

  it "tolerates missing keys" do
    address = described_class.from_params(state: "NY")

    expect(address.line1).to be_nil
    expect(address.line2).to be_nil
    expect(address.state).to eq("NY")
  end

  it "is comparable by value" do
    a = described_class.from_params(state: "NY", postal_code: "10001")
    b = described_class.from_params(state: "NY", postal_code: "10001")

    expect(a).to eq(b)
  end
end
