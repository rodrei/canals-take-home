require "rails_helper"

RSpec.describe Inventory, type: :model do
  it "forbids duplicate product rows within a warehouse" do
    warehouse = create(:warehouse)
    product = create(:product)
    create(:inventory, warehouse: warehouse, product: product)

    dup = build(:inventory, warehouse: warehouse, product: product)

    expect(dup).not_to be_valid
  end
end
