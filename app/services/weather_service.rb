require "faraday"

class WeatherService
  UpstreamError = Class.new(StandardError)

  BASE_URL = "https://api.open-meteo.com/v1/forecast".freeze
  FORECAST_DAYS = 5
  DEFAULT_TIMEOUT = 5

  def initialize(connection: nil)
    @connection = connection || default_connection
  end

  def fetch(lat:, lon:, units: :fahrenheit)
    response = @connection.get(BASE_URL, query_params(lat, lon, units))
    raise UpstreamError, "weather api returned #{response.status}" unless response.success?

    parse(response.body, units)
  rescue Faraday::Error => e
    raise UpstreamError, "weather api unreachable: #{e.class}"
  end

  private

  def query_params(lat, lon, units)
    {
      latitude: lat,
      longitude: lon,
      current_weather: true,
      daily: "temperature_2m_max,temperature_2m_min,weathercode",
      forecast_days: FORECAST_DAYS,
      temperature_unit: units.to_s,
      timezone: "auto"
    }
  end

  def parse(body, units)
    payload = body.is_a?(Hash) ? body : JSON.parse(body)
    current = payload["current_weather"]
    daily = payload["daily"]
    raise UpstreamError, "malformed response: #{payload['reason'] || 'missing fields'}" if current.nil? || daily.nil?

    daily_entries = build_daily_entries(daily)
    Forecast.new(
      current_temp: current.fetch("temperature"),
      current_weather_code: current.fetch("weathercode"),
      high: daily_entries.first.high,
      low: daily_entries.first.low,
      daily: daily_entries,
      units: units
    )
  end

  def build_daily_entries(daily)
    daily.fetch("time").each_with_index.map do |date, i|
      Forecast::DailyEntry.new(
        date: Date.parse(date),
        high: daily.fetch("temperature_2m_max")[i],
        low: daily.fetch("temperature_2m_min")[i],
        weather_code: daily.fetch("weathercode")[i]
      )
    end
  end

  def default_connection
    Faraday.new do |c|
      c.options.timeout = DEFAULT_TIMEOUT
      c.options.open_timeout = DEFAULT_TIMEOUT
      c.response :json, content_type: /\bjson$/
    end
  end
end
