require "rails_helper"

RSpec.describe WeatherService do
  let(:lat) { 37.7749 }
  let(:lon) { -122.4194 }

  describe "#fetch" do
    context "with a successful response", vcr: { cassette_name: "weather_service/san_francisco" } do
      subject(:forecast) { described_class.new.fetch(lat: lat, lon: lon) }

      it "returns a Forecast with a current temperature" do
        expect(forecast.current_temp).to be_a(Numeric)
      end

      it "returns today's high and low" do
        expect(forecast.high).to be_a(Numeric)
        expect(forecast.low).to be_a(Numeric)
        expect(forecast.high).to be >= forecast.low
      end

      it "reports the units it requested" do
        expect(forecast.units).to eq(:fahrenheit)
      end

      it "returns five daily entries with parsed dates" do
        expect(forecast.daily.size).to eq(5)
        expect(forecast.daily.first.date).to be_a(Date)
        expect(forecast.daily.first.high).to be_a(Numeric)
        expect(forecast.daily.first.low).to be_a(Numeric)
        expect(forecast.daily.first.weather_code).to be_a(Integer)
      end
    end

    context "when the upstream returns a 5xx error", vcr: { cassette_name: "weather_service/upstream_error" } do
      it "raises an UpstreamError" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError)
      end
    end

    context "when the upstream returns a 504 gateway timeout", vcr: { cassette_name: "weather_service/gateway_timeout" } do
      it "raises an UpstreamError" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError)
      end
    end

    context "when the upstream returns a malformed payload", vcr: { cassette_name: "weather_service/malformed" } do
      it "raises an UpstreamError" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError)
      end
    end
  end
end
