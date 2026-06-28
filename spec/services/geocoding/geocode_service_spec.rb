require "rails_helper"

RSpec.describe Geocoding::GeocodeService do
  it "returns deterministic coordinates for a US address" do
    address = { city: "New York", state: "NY", postal_code: "10001", country: "US" }

    first = described_class.call(address)
    second = described_class.call(address)

    expect(first[:lat]).to be_within(0.0001).of(second[:lat])
    expect(first[:lng]).to be_within(0.0001).of(second[:lng])
    expect(first[:lat]).to be_between(24.0, 50.0)
  end

  it "raises for a non-US country" do
    address = { city: "Toronto", state: "ON", postal_code: "M5V", country: "CA" }

    expect { described_class.call(address) }
      .to raise_error(Geocoding::UnsupportedAddressError)
  end

  it "raises for an unrecognized state" do
    address = { city: "Nowhere", state: "ZZ", postal_code: "00000", country: "US" }

    expect { described_class.call(address) }
      .to raise_error(Geocoding::UnsupportedAddressError)
  end
end
