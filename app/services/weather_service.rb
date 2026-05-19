require "faraday"

class WeatherService
  UpstreamError = Class.new(StandardError)

  BASE_URL = "https://api.open-meteo.com/v1/forecast".freeze
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
      forecast_days: 5,
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
      units: units,
      location_name: nil
    )
  rescue KeyError, TypeError, Date::Error, JSON::ParserError => e
    raise UpstreamError, "malformed response: #{e.class}"
  end

  def build_daily_entries(daily)
    times = daily.fetch("time")
    highs = daily.fetch("temperature_2m_max")
    lows  = daily.fetch("temperature_2m_min")
    codes = daily.fetch("weathercode")

    raise UpstreamError, "malformed response: empty daily forecast" if times.empty?
    unless [ highs, lows, codes ].all? { |a| a.is_a?(Array) && a.size == times.size }
      raise UpstreamError, "malformed response: inconsistent daily arrays"
    end

    times.each_with_index.map do |date, i|
      Forecast::DailyEntry.new(
        date: Date.parse(date),
        high: highs[i],
        low: lows[i],
        weather_code: codes[i]
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
