require "rails_helper"

RSpec.describe Geocoding::GeocodeService do
  describe ".geocode" do
    it "returns deterministic coordinates for a US address" do
      address = Address.from_params(city: "New York", state: "NY", postal_code: "10001", country: "US")

      first = described_class.geocode(address)
      second = described_class.geocode(address)

      expect(first[:lat]).to be_within(0.0001).of(second[:lat])
      expect(first[:lng]).to be_within(0.0001).of(second[:lng])
      expect(first[:lat]).to be_between(24.0, 50.0)
    end

    it "raises for a non-US country" do
      address = Address.from_params(city: "Toronto", state: "ON", postal_code: "M5V", country: "CA")

      expect { described_class.geocode(address) }
        .to raise_error(Geocoding::UnsupportedAddressError)
    end

    it "raises for an unrecognized state" do
      address = Address.from_params(city: "Nowhere", state: "ZZ", postal_code: "00000", country: "US")

      expect { described_class.geocode(address) }
        .to raise_error(Geocoding::UnsupportedAddressError)
    end
  end

  describe ".validate" do
    it "returns truthy for a supported US address" do
      address = Address.from_params(city: "New York", state: "NY", postal_code: "10001", country: "US")

      expect(described_class.validate(address)).to be_truthy
    end

    it "raises for a non-US country" do
      address = Address.from_params(city: "Toronto", state: "ON", postal_code: "M5V", country: "CA")

      expect { described_class.validate(address) }
        .to raise_error(Geocoding::UnsupportedAddressError)
    end

    it "raises for an unrecognized state" do
      address = Address.from_params(city: "Nowhere", state: "ZZ", postal_code: "00000", country: "US")

      expect { described_class.validate(address) }
        .to raise_error(Geocoding::UnsupportedAddressError)
    end
  end
end
