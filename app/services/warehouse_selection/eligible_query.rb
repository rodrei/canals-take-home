module WarehouseSelection
  # Returns warehouses that can fill the ENTIRE order from a single location:
  # every requested product must be stocked at >= the requested quantity.
  class EligibleQuery
    def self.call(order_items)
      new(order_items).call
    end

    def initialize(order_items)
      @order_items = order_items
    end

    def call
      return Warehouse.none if @order_items.blank?

      product_count = @order_items.map(&:product_id).uniq.size

      # A warehouse is eligible if, counting only rows where it stocks enough of
      # a requested product, it covers all requested products.
      conditions = @order_items.map do |item|
        Inventory.sanitize_sql_array(
          ["(inventories.product_id = ? AND inventories.quantity >= ?)", item.product_id, item.quantity]
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
