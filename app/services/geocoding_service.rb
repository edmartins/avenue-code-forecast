class GeocodingService
  AddressNotFound = Class.new(StandardError)

  Location = Data.define(:zip, :lat, :lon, :formatted_address)

  MAX_ADDRESS_LENGTH = 200

  def call(address)
    cleaned = address.to_s.strip
    raise AddressNotFound, "address is blank" if cleaned.empty?

    bounded = cleaned[0, MAX_ADDRESS_LENGTH]
    result = Geocoder.search(bounded).first
    raise AddressNotFound, "no result for #{bounded.inspect}" if result.nil?

    postal_code = result.postal_code.to_s.strip
    raise AddressNotFound, "no postal code on result for #{bounded.inspect}" if postal_code.empty?

    Location.new(
      zip: postal_code,
      lat: result.latitude,
      lon: result.longitude,
      formatted_address: result.display_name.presence || bounded
    )
  end
end
