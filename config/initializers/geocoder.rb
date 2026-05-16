Geocoder.configure(
  # Nominatim (OpenStreetMap) — keyless and the geocoder gem default.
  lookup: :nominatim,

  # Nominatim's usage policy requires a real User-Agent identifying the app.
  # See https://operations.osmfoundation.org/policies/nominatim/.
  http_headers: { "User-Agent" => "avenue-code-forecast (#{Rails.env})" },

  # Bound request time so a slow upstream cannot hang the request thread.
  timeout: 5,

  # Cache geocoder results in-process for 24h to cut Nominatim load.
  # Separate from the 30-minute forecast cache, which is keyed by zip.
  cache: Rails.cache,
  cache_options: { expiration: 24.hours, prefix: "geocoder:v1:" }
)
