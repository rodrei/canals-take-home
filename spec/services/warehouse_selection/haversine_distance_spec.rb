require "rails_helper"

RSpec.describe WarehouseSelection::HaversineDistance do
  it "computes zero for identical points" do
    expect(described_class.call(lat1: 40.0, lng1: -74.0, lat2: 40.0, lng2: -74.0)).to be_within(0.001).of(0.0)
  end

  it "approximates the NYC-to-Chicago distance (~1145 km)" do
    km = described_class.call(lat1: 40.7128, lng1: -74.0060, lat2: 41.8781, lng2: -87.6298)
    expect(km).to be_within(50).of(1145)
  end
end
