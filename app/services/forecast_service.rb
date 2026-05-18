class ForecastService
  attr_reader :address, :geocoding_service, :weather_service

  Result = Data.define(:forecast, :from_cache, :zip)

  def self.call(address:, geocoding_service: GeocodingService.new, weather_service: WeatherService.new)
    new(address:, geocoding_service:, weather_service:).call
  end

  def initialize(address:, geocoding_service: GeocodingService.new, weather_service: WeatherService.new)
    @address = address
    @geocoding_service = geocoding_service
    @weather_service = weather_service
  end

  def call
    if (cached = Rails.cache.read(cache_key))
      return Result.new(forecast: cached, from_cache: true, zip: location.zip)
    end

    Rails.cache.write(cache_key, fresh, expires_in: 30.minutes)
    Result.new(forecast: fresh, from_cache: false, zip: location.zip)
  end

  private

  def cache_key
    @cache_key ||= "forecast:v1:#{location.zip}"
  end

  def location
    @location ||= geocoding_service.geocode(address)
  end

  def fresh
    @fresh ||= weather_service
      .fetch(lat: location.lat, lon: location.lon)
      .with_location(location.formatted_address)
  end
end
