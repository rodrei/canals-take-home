module Geocoding
  # Mocked geocoder. A real implementation would call a 3rd-party geocoding API.
  # Returns deterministic coordinates: the centroid of the address's US state,
  # nudged by a small deterministic offset derived from the postal code so that
  # distinct addresses within a state still differ slightly.
  class GeocodeService
    STATE_CENTROIDS = {
      "NY" => [42.9538, -75.5268], "CA" => [37.1841, -119.4696],
      "IL" => [40.0417, -89.1965], "TX" => [31.4757, -99.3312],
      "FL" => [28.6305, -82.4497], "WA" => [47.3826, -120.4472],
      "MA" => [42.2596, -71.8083], "GA" => [32.6415, -83.4426],
      "CO" => [38.9972, -105.5478], "PA" => [40.8781, -77.7996]
    }.freeze

    def self.call(address)
      new(address).call
    end

    def initialize(address)
      @address = address.to_h.with_indifferent_access
    end

    def call
      raise UnsupportedAddressError, "only US addresses are supported" unless us?

      centroid = STATE_CENTROIDS[state]
      raise UnsupportedAddressError, "unrecognized state: #{state}" unless centroid

      lat = centroid[0] + offset(0)
      lng = centroid[1] + offset(1)
      { lat: lat.round(6), lng: lng.round(6) }
    end

    private

    attr_reader :address

    def us?
      address[:country].to_s.upcase == "US"
    end

    def state
      address[:state].to_s.upcase
    end

    def offset(index)
      digest = Digest::SHA256.hexdigest("#{address[:postal_code]}:#{index}")
      (digest[0, 4].to_i(16) % 1000) / 10_000.0 # 0.0..0.0999
    end
  end
end
