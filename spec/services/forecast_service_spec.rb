require "rails_helper"

RSpec.describe ForecastService do
  let(:address) { "123 Main St, Anywhere" }
  let(:location) do
    GeocodingService::Location.new(
      zip: "94105",
      lat: 37.7,
      lon: -122.4,
      formatted_address: "San Francisco, CA"
    )
  end
  let(:forecast) do
    Forecast.new(
      current_temp: 60.0,
      current_weather_code: 0,
      high: 65.0,
      low: 50.0,
      daily: [],
      units: :fahrenheit
    )
  end
  let(:geocoding_service) { instance_double(GeocodingService, call: location) }
  let(:weather_service) { instance_double(WeatherService, fetch: forecast) }
  let(:cache_key) { "forecast:v1:94105" }

  describe ".call" do
    subject(:result) { described_class.call(address:, geocoding_service:, weather_service:) }

    context "on a cache miss" do
      it "fetches a fresh forecast and writes it to the cache" do
        expect(result.from_cache).to be(false)
        expect(result.zip).to eq("94105")
        expect(weather_service).to have_received(:fetch).with(lat: 37.7, lon: -122.4)
        expect(Rails.cache.read(cache_key)).not_to be_nil
      end

      it "tags the returned forecast with the formatted address" do
        expect(result.forecast.location_name).to eq("San Francisco, CA")
      end

      it "writes the cache entry with a 30-minute expiry" do
        allow(Rails.cache).to receive(:write).and_call_original
        result
        expect(Rails.cache).to have_received(:write).with(cache_key, anything, expires_in: 30.minutes)
      end
    end

    context "on a cache hit for the same zip" do
      let(:cached_forecast) { forecast.with_location("Previously cached SF") }

      before { Rails.cache.write(cache_key, cached_forecast, expires_in: 30.minutes) }

      it "returns the cached forecast without calling WeatherService" do
        expect(result.from_cache).to be(true)
        expect(result.forecast.location_name).to eq("Previously cached SF")
        expect(weather_service).not_to have_received(:fetch)
      end
    end

    context "when geocoding fails" do
      let(:address) { "" }

      before { allow(geocoding_service).to receive(:call).and_raise(GeocodingService::AddressNotFound, "blank") }

      it "propagates AddressNotFound and never touches the weather service or cache" do
        expect { result }.to raise_error(GeocodingService::AddressNotFound)
        expect(weather_service).not_to have_received(:fetch)
      end
    end
  end
end
