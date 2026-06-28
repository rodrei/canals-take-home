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
end
