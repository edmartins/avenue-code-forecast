Geocoder.configure(
  lookup: :nominatim,
  # Nominatim requires a User-Agent identifying the app.
  http_headers: { "User-Agent" => "avenue-code-forecast (#{Rails.env})" },
  timeout: 5,
  cache: Rails.cache,
  cache_options: { expiration: 24.hours, prefix: "geocoder:v1:" }
)
