# Avenue Code Forecast

A small Ruby on Rails app that takes a free-form address, resolves it to a zip
code, fetches the current weather and a 5-day outlook for that area, and caches
the result for 30 minutes per zip.

Built for the take-home exercise. No API keys, no database, no extra
infrastructure to run locally.

## Run locally

Requirements:

- Ruby 3.4.x (see `.ruby-version`)
- Bundler 2.x

```bash
bundle install
bin/rails server
```

Then open <http://localhost:3000> and enter any address — a street, a city, a
postal code. No API keys are required; the app uses Open-Meteo for weather and
Nominatim (OpenStreetMap) for geocoding, both of which are free and keyless.

## Run the tests

```bash
bundle exec rspec
```

RSpec is configured to block real outbound HTTP via WebMock, so the suite is
hermetic and fast.

## Architecture

```
Browser ──► ForecastsController ──► ForecastService ──► GeocodingService ──► Nominatim
                                            │
                                            └──► WeatherService ──► Open-Meteo
                                            │
                                            └──► Rails.cache (memory store, 30 min TTL, keyed by zip)
```

Server-rendered MVC, three thin service objects:

- `GeocodingService` — address → `{ zip, lat, lon, formatted_address }`, or
  `AddressNotFound`. Backed by the `geocoder` gem with Nominatim. Input is
  trimmed and bounded to 200 chars before the lookup.
- `WeatherService` — `(lat, lon)` → `Forecast` value object (current temp,
  today's high/low, 5-day daily series). Backed by Faraday with 5-second
  timeouts. Network or shape errors are wrapped in `UpstreamError`.
- `ForecastService` — orchestrates geocode → cache lookup → weather fetch and
  returns a `Result` with the `Forecast` plus a `from_cache` boolean for the
  view.

## Caching behavior

- The cache is **keyed by zip code** (`forecast:v1:<zip>`), not by the
  user-entered address. Two users entering different street addresses in the
  same zip share the cached forecast — that matches the spec's requirement.
- TTL is **30 minutes**, starting at the first cache write for a given zip.
- Hit/miss is tracked with an explicit `Rails.cache.read` followed by
  `Rails.cache.write` (rather than `Rails.cache.fetch`) so the `from_cache`
  flag exposed to the view is unambiguous.
- The cache store is `:memory_store` in every environment. A real deployment
  would swap this for Redis or Memcached so the cache survives restarts and is
  shared across processes.
- A "Served from cache" badge is rendered above the forecast whenever
  `from_cache` is `true`.

## Known limitations

- **Single-process cache.** `:memory_store` is per-process; with a multi-worker
  deployment, each worker would warm its own copy. Redis/Memcached would fix
  this.
- **Rate-limited geocoder.** Nominatim's usage policy permits about one request
  per second per app. A geocoder result cache (24 hours, in-process) is wired
  up in `config/initializers/geocoder.rb` to soften the load, but a public
  deployment would need a paid geocoder or a self-hosted Nominatim.
- **No authentication.** The form is open to anyone; a simple per-IP rate
  limiter (10 requests per minute) caps abuse, but it isn't a substitute for
  real auth in front of a production deployment.
- **No persistence.** History, favorites, and audit trails are out of scope.

## With more time

- Swap `:memory_store` for Redis-backed `:redis_cache_store` and document a
  deployment path.
- Add a unit toggle (`°F` / `°C`) and persist the choice in a cookie.
- Address autocomplete on the form (debounced).
- A small history list of recent lookups per session.
- Add OpenWeatherMap (or similar) as a fallback weather provider behind the
  same `WeatherService` interface — Open-Meteo's free tier has no SLA.
- Instrumentation: emit ActiveSupport::Notifications for upstream call latency
  and cache hit rate, expose via a `/metrics` endpoint.

## Project layout

```
app/
├── controllers/forecasts_controller.rb
├── services/
│   ├── geocoding_service.rb
│   ├── weather_service.rb
│   └── forecast_service.rb
├── models/forecast.rb          # PORO value object, not ActiveRecord
└── views/forecasts/{new,create}.html.erb

spec/
├── services/                   # unit specs for each service object
└── requests/                   # request specs for the controller + views
```
