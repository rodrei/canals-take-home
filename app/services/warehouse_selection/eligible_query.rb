module WarehouseSelection
  # Returns warehouses that can fill the ENTIRE order from a single location:
  # every requested product must be stocked at >= the requested quantity.
  class EligibleQuery
    def self.call(item_quantities)
      new(item_quantities).call
    end

    def initialize(item_quantities)
      @item_quantities = item_quantities
    end

    def call
      return Warehouse.none if @item_quantities.blank?

      product_count = @item_quantities.size

      # A warehouse is eligible if, counting only rows where it stocks enough of
      # a requested product, it covers all requested products.
      conditions = @item_quantities.map do |product_id, quantity|
        Inventory.sanitize_sql_array(
          ["(inventories.product_id = ? AND inventories.quantity >= ?)", product_id, quantity]
        )
      end.join(" OR ")

      eligible_ids = Inventory
        .where(Arel.sql(conditions))
        .group(:warehouse_id)
        .having("COUNT(DISTINCT inventories.product_id) = ?", product_count)
        .pluck(:warehouse_id)

      Warehouse.where(id: eligible_ids)
    end
  end
end
