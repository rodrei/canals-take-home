require "rails_helper"

RSpec.describe WarehouseSelection::SelectService do
  let(:product) { create(:product) }

  it "returns only eligible warehouses' nearest to the destination" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)   # NYC-ish
    far  = create(:warehouse, latitude: 34.05, longitude: -118.24)  # LA-ish
    create(:inventory, warehouse: near, product: product, quantity: 10)
    create(:inventory, warehouse: far, product: product, quantity: 10)

    eligible = WarehouseSelection::EligibleQuery.call({ product.id => 2 })
    chosen = described_class.call(warehouses: eligible, lat: 40.73, lng: -73.99)

    expect(chosen).to eq(near)
  end

  it "returns nil when no warehouse is eligible" do
    create(:inventory, warehouse: create(:warehouse), product: product, quantity: 1)

    eligible = WarehouseSelection::EligibleQuery.call({ product.id => 5 })
    chosen = described_class.call(warehouses: eligible, lat: 40.73, lng: -73.99)

    expect(chosen).to be_nil
  end
end
