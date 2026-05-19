require "rails_helper"

RSpec.describe WeatherService do
  let(:lat) { 37.7749 }
  let(:lon) { -122.4194 }

  describe "#fetch" do
    context "with a successful response", vcr: { cassette_name: "weather_service/san_francisco" } do
      subject(:forecast) { described_class.new.fetch(lat: lat, lon: lon) }

      it "returns the current temperature from the cassette" do
        expect(forecast.current_temp).to eq(67.9)
        expect(forecast.current_weather_code).to eq(0)
      end

      it "returns today's high and low from the cassette" do
        expect(forecast.high).to eq(74.3)
        expect(forecast.low).to eq(49.9)
      end

      it "reports the units it requested" do
        expect(forecast.units).to eq(:fahrenheit)
      end

      it "returns five daily entries with parsed dates" do
        expect(forecast.daily.size).to eq(5)
        expect(forecast.daily.first.date).to eq(Date.new(2026, 5, 17))
        expect(forecast.daily.last.date).to eq(Date.new(2026, 5, 21))
        expect(forecast.daily.map(&:high)).to eq([ 74.3, 81.6, 85.5, 75.1, 77.1 ])
        expect(forecast.daily.map(&:weather_code)).to eq([ 0, 0, 0, 3, 1 ])
      end
    end

    context "with units: :celsius", vcr: { cassette_name: "weather_service/san_francisco_celsius" } do
      it "passes temperature_unit=celsius upstream and tags the result" do
        forecast = described_class.new.fetch(lat: lat, lon: lon, units: :celsius)

        expect(forecast.units).to eq(:celsius)
        expect(forecast.current_temp).to eq(20.0)
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

    context "when the transport fails (timeout / connection refused)" do
      it "raises an UpstreamError when Faraday raises a transport error" do
        stub_request(:get, /api\.open-meteo\.com/).to_raise(Faraday::ConnectionFailed.new("connection refused"))

        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError, /unreachable/)
      end
    end

    context "when the upstream returns a malformed payload", vcr: { cassette_name: "weather_service/malformed" } do
      it "raises an UpstreamError" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError)
      end
    end

    context "when current_weather is missing the temperature key",
            vcr: { cassette_name: "weather_service/missing_current_temperature" } do
      it "raises an UpstreamError instead of leaking KeyError" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError, /malformed/)
      end
    end

    context "when daily.time is empty", vcr: { cassette_name: "weather_service/empty_daily" } do
      it "raises an UpstreamError instead of leaking NoMethodError on nil.first" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError, /empty/)
      end
    end

    context "when the daily arrays have mismatched lengths",
            vcr: { cassette_name: "weather_service/mismatched_daily_arrays" } do
      it "raises an UpstreamError instead of yielding nil temperatures" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError, /inconsistent/)
      end
    end

    context "when the upstream omits a required daily array",
            vcr: { cassette_name: "weather_service/missing_daily_max" } do
      it "raises an UpstreamError instead of leaking KeyError" do
        expect { described_class.new.fetch(lat: lat, lon: lon) }
          .to raise_error(WeatherService::UpstreamError, /malformed/)
      end
    end
  end
end
