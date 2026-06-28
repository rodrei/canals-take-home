require "rails_helper"

RSpec.describe Order, type: :model do
  it "transitions pending -> processing -> confirmed" do
    order = create(:order, status: :pending)
    warehouse = create(:warehouse)

    order.start_processing!
    expect(order).to be_processing

    order.mark_confirmed!(warehouse: warehouse)
    expect(order).to be_confirmed
    expect(order.warehouse).to eq(warehouse)
  end

  it "rejects confirming an order that is not processing" do
    order = create(:order, status: :pending)
    warehouse = create(:warehouse)

    expect { order.mark_confirmed!(warehouse: warehouse) }
      .to raise_error(Order::InvalidTransition)
  end

  it "requires the shipping address fields (line2 optional)" do
    order = build(:order, ship_city: nil, ship_country: nil, ship_line1: nil,
                          ship_postal_code: nil, ship_state: nil, ship_line2: nil)

    expect(order).not_to be_valid
    expect(order.errors.attribute_names)
      .to include(:ship_city, :ship_country, :ship_line1, :ship_postal_code, :ship_state)
    expect(order.errors.attribute_names).not_to include(:ship_line2)
  end
end
