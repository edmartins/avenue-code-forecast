class Forecast < Data.define(
  :current_temp,
  :current_weather_code,
  :high,
  :low,
  :daily,
  :units,
  :location_name
)
  DailyEntry = Data.define(:date, :high, :low, :weather_code)

  def with_location(name)
    with(location_name: name)
  end
end
