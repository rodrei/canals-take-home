# Immutable value object for a shipping address. Plain (non-persisted) data
# carried between the request params, the geocoder, and the order's ship_*
# columns. Validation of *what* makes an address geocodable (US / recognized
# state) lives in Geocoding::GeocodeService, not here.
class Address < Data.define(:line1, :line2, :city, :state, :postal_code, :country)
  # Build from a (possibly indifferent-access) params hash, tolerating missing
  # keys — presence is enforced by Order's model validations downstream.
  def self.from_params(params)
    h = params.to_h.with_indifferent_access
    new(
      line1: h[:line1], line2: h[:line2], city: h[:city],
      state: h[:state], postal_code: h[:postal_code], country: h[:country]
    )
  end
end
