require "rails_helper"

RSpec.describe GeocodingService do
  describe "#geocode" do
    context "with a recognizable address", vcr: { cassette_name: "geocoding_service/white_house" } do
      subject(:result) { described_class.new.geocode("1600 Pennsylvania Ave, Washington DC") }

      it "returns a Location with a postal code" do
        expect(result.zip).to match(/\A\d{5}\z/)
      end

      it "returns lat/lon near the White House" do
        expect(result.lat).to be_within(0.05).of(38.8977)
        expect(result.lon).to be_within(0.05).of(-77.0365)
      end

      it "returns a human-readable formatted address" do
        expect(result.formatted_address).to include("Washington")
      end
    end

    context "with an unrecognizable address", vcr: { cassette_name: "geocoding_service/unrecognizable" } do
      it "raises AddressNotFound" do
        expect { described_class.new.geocode("asdfasdfgargle_no_such_place_zzz") }
          .to raise_error(GeocodingService::AddressNotFound)
      end
    end

    context "when the result has no postal code", vcr: { cassette_name: "geocoding_service/no_postal_code" } do
      it "raises AddressNotFound" do
        expect { described_class.new.geocode("middle of the ocean") }
          .to raise_error(GeocodingService::AddressNotFound)
      end
    end

    context "with blank input" do
      it "raises AddressNotFound without calling the geocoder" do
        expect { described_class.new.geocode("   ") }
          .to raise_error(GeocodingService::AddressNotFound)

        expect(WebMock).not_to have_requested(:get, /nominatim/)
      end
    end

    context "with an overly long input", vcr: { cassette_name: "geocoding_service/truncated_long_address" } do
      it "truncates the address to 200 characters before geocoding" do
        expect { described_class.new.geocode("a" * 1000) }
          .to raise_error(GeocodingService::AddressNotFound)
      end
    end

    context "when the geocoder result has a blank display_name",
            vcr: { cassette_name: "geocoding_service/blank_display_name" } do
      it "falls back to the input address for formatted_address" do
        location = described_class.new.geocode("123 Main St")
        expect(location.formatted_address).to eq("123 Main St")
      end
    end
  end
end
