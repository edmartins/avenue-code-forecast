require "rails_helper"

RSpec.describe "Forecasts", type: :request do
  let(:forecast) do
    Forecast.new(
      current_temp: 65.5,
      current_weather_code: 0,
      high: 72.0,
      low: 55.0,
      daily: [
        Forecast::DailyEntry.new(date: Date.new(2024, 1, 1), high: 72.0, low: 55.0, weather_code: 0),
        Forecast::DailyEntry.new(date: Date.new(2024, 1, 2), high: 70.0, low: 54.0, weather_code: 1)
      ],
      units: :fahrenheit,
      location_name: "San Francisco, CA"
    )
  end

  describe "GET /" do
    before { get "/" }

    it { expect(response).to have_http_status(:ok) }
    it { expect(response.body).to include("address") }
  end

  describe "POST /forecasts" do
    subject(:post_forecasts) { post "/forecasts", params: { address: } }

    context "when testing cache" do
      let(:address) { "San Francisco" }
      let(:result) { ForecastService::Result.new(forecast:, from_cache:, zip: "94105") }

      before do
        allow(ForecastService).to receive(:call).with(address:).and_return(result)
        post_forecasts
      end

      context "with a valid address (cache miss)" do
        let(:from_cache) { false }

        it { expect(response).to have_http_status(:ok) }
        it { expect(response.body).to include("65.5") }
        it { expect(response.body).to include("San Francisco, CA") }
        it { expect(response.body).not_to include("Served from cache") }
      end

      context "with a cached result" do
        let(:from_cache) { true }

        it { expect(response.body).to include("Served from cache") }
      end
    end

    context "with a blank address" do
      let(:address) { "   " }

      before { post_forecasts }

      it { expect(response.body).to include("Please enter an address") }
    end

    context "when raises an error" do
      let(:address) { "asdfasdf" }

      before do
        allow(ForecastService).to receive(:call).and_raise(*error)
        post_forecasts
      end

      context "when the address can't be geocoded" do
        let(:error) { [GeocodingService::AddressNotFound, "no result"] }

        it { expect(response.body).to include("couldn&#39;t find that address") }
      end

      context "when the weather upstream fails" do
        let(:error) { [WeatherService::UpstreamError, "boom"] }

        it { expect(response.body).to include("unavailable") }
      end
    end
  end
end
