module WarehouseSelection
  # Given candidate warehouses already known to be able to fill the order,
  # returns the one closest to the destination per the distance strategy.
  class SelectService
    def self.call(warehouses:, lat:, lng:, strategy: HaversineDistance)
      new(warehouses: warehouses, lat: lat, lng: lng, strategy: strategy).call
    end

    def initialize(warehouses:, lat:, lng:, strategy:)
      @warehouses = warehouses
      @lat = lat
      @lng = lng
      @strategy = strategy
    end

    def call
      @warehouses.min_by do |warehouse|
        @strategy.call(
          lat1: @lat, lng1: @lng,
          lat2: warehouse.latitude.to_f, lng2: warehouse.longitude.to_f
        )
      end
    end
  end
end
