# Idempotent seeds — safe to run repeatedly.

alice = Customer.find_or_create_by!(auth_token: "alice-token") do |c|
  c.name = "Alice"
  c.email = "alice@example.com"
end

Customer.find_or_create_by!(auth_token: "bob-token") do |c|
  c.name = "Bob"
  c.email = "bob@example.com"
end

widget = Product.find_or_create_by!(sku: "WIDGET") { |p| p.name = "Widget"; p.price_cents = 1_500; p.currency = "USD" }
gadget = Product.find_or_create_by!(sku: "GADGET") { |p| p.name = "Gadget"; p.price_cents = 2_500; p.currency = "USD" }
gizmo  = Product.find_or_create_by!(sku: "GIZMO")  { |p| p.name = "Gizmo";  p.price_cents = 800;   p.currency = "USD" }

# Warehouses at distinct US coordinates.
nyc = Warehouse.find_or_create_by!(name: "NYC DC")     { |w| w.latitude = 40.7128; w.longitude = -74.0060 }
chi = Warehouse.find_or_create_by!(name: "Chicago DC") { |w| w.latitude = 41.8781; w.longitude = -87.6298 }
lax = Warehouse.find_or_create_by!(name: "LA DC")      { |w| w.latitude = 34.0522; w.longitude = -118.2437 }

def stock(warehouse, product, quantity)
  inv = Inventory.find_or_initialize_by(warehouse: warehouse, product: product)
  inv.quantity = quantity
  inv.save!
end

# NYC stocks everything; Chicago stocks widget+gadget; LA stocks only widget.
stock(nyc, widget, 100); stock(nyc, gadget, 100); stock(nyc, gizmo, 100)
stock(chi, widget, 100); stock(chi, gadget, 100)
stock(lax, widget, 100)

puts "Seeded #{Customer.count} customers, #{Product.count} products, #{Warehouse.count} warehouses."
