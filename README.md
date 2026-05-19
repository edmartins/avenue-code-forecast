# Avenue Code Forecast

Rails app that resolves a free-form address to a zip, fetches current weather
and a 5-day outlook, and caches the result for 30 minutes per zip.

<img width="651" height="343" alt="image" src="https://github.com/user-attachments/assets/a5443d9e-5b8d-4a0f-b4c5-7ad15d75aed4" />

<img width="656" height="696" alt="image" src="https://github.com/user-attachments/assets/8b0d64b4-9a64-478a-bb28-520fe88cb143" />

No API keys, no database. Uses Open-Meteo (weather) and Nominatim (geocoding),
both free and keyless.

## Run locally

Requires Ruby 3.4.x and Bundler 2.x.

```bash
bundle install
bin/rails server
```

Open <http://localhost:3000> and enter any address.

## Run the tests

```bash
bundle exec rspec
```

WebMock blocks outbound HTTP so the test suite never hits the network.

## Architecture

Service objects:

- `GeocodingService` resolves an address to a zip, lat, and lon. Inputs are trimmed and capped at 200 chars; missing postal codes raise `AddressNotFound`.
- `WeatherService` takes a lat/lon and returns a `Forecast`. Faraday with 5s timeouts; upstream failures raise `UpstreamError`.
- `ForecastService` orchestrates the geocode, cache lookup, and weather fetch. Returns a `Result` with a `from_cache` flag.

## Caching

- Keyed by zip (`forecast:v1:<zip>`), not the raw address, so different addresses in the same zip share a result.
- 30-minute TTL, starting at the first write per zip.
- Explicit `read` + `write` (not `fetch`) so the `from_cache` flag is unambiguous.
- `:memory_store` in every environment; a real deployment would use Redis or Memcached.
- "Served from cache" badge renders when `from_cache` is true.

## Known limitations

- `:memory_store` is per-process; multi-worker deployments would each warm their own copy.
- Nominatim allows ~1 req/sec; a 24h in-process geocoder cache softens this, but a public deployment needs a paid or self-hosted geocoder.
- No auth. A per-IP rate limit (10/min) caps abuse but isn't a substitute for real auth.
- No persistence (no history, favorites, audit trail).

## Future work

- Swap `:memory_store` for `:redis_cache_store`.
- Unit toggle (F/C) persisted in a cookie.
- Debounced address autocomplete.
- Per-session history of recent lookups.
- Fallback weather provider behind the same `WeatherService` interface.
- ActiveSupport::Notifications for upstream latency and cache hit rate, exposed via `/metrics`.

## Project layout

```
app/
  controllers/forecasts_controller.rb
  services/{geocoding,weather,forecast}_service.rb
  models/forecast.rb               # PORO value object
  views/forecasts/{new,create}.html.erb

spec/
  services/                        # unit specs
  requests/                        # controller + view specs
```
