module WarehouseSelection
  # Great-circle distance in kilometers.
  #
  # NOTE: distance is only a proxy for fulfillment optimality. An optimal
  # selection strategy would also weigh real transit time (road/carrier
  # routing, not straight-line), shipping cost and carrier zones, the delivery
  # SLA, warehouse capacity/throughput, and inventory balancing across the
  # network. True fulfillment is a cost-minimization problem, not nearest-
  # neighbor. This strategy is intentionally swappable behind SelectService.
  class HaversineDistance
    EARTH_RADIUS_KM = 6371.0

    def self.call(lat1:, lng1:, lat2:, lng2:)
      rlat1 = to_rad(lat1)
      rlat2 = to_rad(lat2)
      dlat = to_rad(lat2 - lat1)
      dlng = to_rad(lng2 - lng1)

      a = (Math.sin(dlat / 2)**2) +
          (Math.cos(rlat1) * Math.cos(rlat2) * (Math.sin(dlng / 2)**2))
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      EARTH_RADIUS_KM * c
    end

    def self.to_rad(degrees)
      degrees.to_f * Math::PI / 180
    end
  end
end
