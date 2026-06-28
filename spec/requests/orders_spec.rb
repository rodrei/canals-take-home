require "rails_helper"

RSpec.describe "Orders", type: :request do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, price_cents: 1_000) }
  let(:auth) { { "Authorization" => "Bearer #{customer.auth_token}" } }

  let(:valid_body) do
    {
      order: {
        shipping_address: { line1: "1 Main", city: "New York", state: "NY", postal_code: "10001", country: "US" },
        items: [{ product_id: product.id, quantity: 2 }],
        payment: { card_number: "4111111111111111" }
      }
    }
  end

  describe "POST /orders" do
    it "creates a pending order" do
      post "/orders", params: valid_body, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig("order", "status")).to eq("pending")
      expect(body.dig("order", "total_cents")).to eq(2_000)
    end

    it "returns 401 without a valid token" do
      post "/orders", params: valid_body, headers: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 422 for an invalid card" do
      body = valid_body.deep_dup
      body[:order][:payment][:card_number] = "1234567812345678"

      post "/orders", params: body, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for a non-US address" do
      body = valid_body.deep_dup
      body[:order][:shipping_address] = { line1: "1", city: "Toronto", state: "ON", postal_code: "M5V", country: "CA" }

      post "/orders", params: body, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when a required shipping field is missing" do
      body = valid_body.deep_dup
      body[:order][:shipping_address].delete(:city)

      post "/orders", params: body, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /orders/:id" do
    it "returns the caller's order" do
      order = create(:order, customer: customer)

      get "/orders/#{order.id}", headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("order", "id")).to eq(order.id)
    end

    it "returns 404 for another customer's order" do
      other = create(:order, customer: create(:customer))

      get "/orders/#{other.id}", headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
