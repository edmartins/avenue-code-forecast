class ForecastsController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create,
             with: -> { redirect_to root_path, alert: "Too many requests — try again shortly." }

  def new
  end

  def create
    address = params[:address].to_s.strip

    if address.empty?
      flash.now[:alert] = "Please enter an address."
      render :new, status: :unprocessable_content
      return
    end

    @result = ForecastService.call(address:)
  rescue GeocodingService::AddressNotFound
    flash.now[:alert] = "We couldn't find that address."
    render :new, status: :unprocessable_content
  rescue WeatherService::UpstreamError
    flash.now[:alert] = "The weather service is currently unavailable. Please try again."
    render :new, status: :bad_gateway
  end
end
