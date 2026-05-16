# Weather Forecast — Take-Home Assessment Plan

## Source documents
- `take-home-exercise_ruby.pdf` — functional requirements
- `assessment_guide_bts.pdf` — submission rules and evaluation criteria

## Important note about AI usage
The assessment guide explicitly states: **"DO NOT use any AI tools like ChatGPT or similar."**
This plan document is a planning artifact only. Treat any AI-produced material as a discussion outline; the actual submitted code, commits, and prose must be written by hand (or you should disclose AI usage to the recruiter). Do not paste generated code into the repo verbatim.

---

## 1. Requirements digest

Functional (from `take-home-exercise_ruby.pdf`):
1. Built with **Ruby on Rails**.
2. Accept an **address** as input (free-form, not just a zip).
3. Resolve the address to a **zip code** and fetch forecast data for it.
4. Return at least the **current temperature**. Bonus: **high/low** and/or **extended forecast**.
5. **Display** the forecast to the user.
6. **Cache by zip code for 30 minutes**; subsequent requests for the same zip serve from cache.
7. Show a **"from cache"** indicator when the response is cached.
8. **Do not use "Apple"** anywhere in the project name, code, or copy.

Submission (from `assessment_guide_bts.pdf`):
- Public Git repo link (GitHub etc.).
- README with run instructions — if it doesn't run, it fails.
- Document approach, library choices, trade-offs, challenges, and what you'd do next.
- Be honest about anything incomplete.
- One final round with the client to defend the solution after pass.

Naming chosen: **avenue-code-forecast** (working dir already matches).

---

## 2. Architecture overview

A standard Rails MVC monolith with thin service objects.

```
Browser ──► ForecastsController ──► ForecastService ──► GeocodingService ──► Geocoder/Nominatim
                                              │
                                              └──► WeatherService ──► Open-Meteo API
                                              │
                                              └──► Rails.cache (30 min TTL, keyed by zip)
```

**Why MVC + services, not API-only:**
The requirement to "display details to the user" implies a UI. A server-rendered ERB view is the smallest path to that and lets the cache indicator be a simple flag rendered in the template. Service objects keep the controller skinny and make each step independently testable.

---

## 3. Stack choices and rationale

| Concern | Choice | Why |
|---|---|---|
| Ruby | Latest stable (3.4.x or newer — check `ruby -v` available on the dev box) | Use the newest patch release of the current stable line; no reason to pin to an older minor. |
| Rails | Latest stable (8.0.x or newer) | Use the newest stable Rails release; built-in `Rails.cache` is enough — no Redis needed for the demo. |
| HTTP client | `Faraday` | Standard, easy to stub in tests; cleaner than `Net::HTTP`. |
| Geocoding | `geocoder` gem w/ Nominatim (OpenStreetMap) | Free, no API key, handles address → lat/lon + postal code in one call. Fallback: Zippopotam.us if input is already a US zip. |
| Weather API | **Open-Meteo** (`https://api.open-meteo.com`) | Free, no API key, returns current + daily high/low + multi-day forecast in one request. Avoids the key-management story in the README. |
| Cache store | `:memory_store` in **all** environments (dev, test, prod) for the demo | Simplest possible setup — no extra processes, no file-system cleanup, no config drift between envs. Requirement is 30-min TTL per zip; no need for Redis. Document that a real deployment would swap in Redis/Memcached. |
| Testing | RSpec + WebMock + VCR | RSpec is more expressive than Minitest for service objects; WebMock blocks live HTTP in tests; VCR records cassettes for the happy path. |
| Linting | RuboCop (rails-omakase config) | Free, no opinion to defend. |

Keep the README terse — only what a reviewer needs to run and understand the app. Park the deeper rationale (rejected alternatives, trade-off reasoning, things to defend live) in a local `NOTES.md` that is **gitignored** and used only as personal prep for the interview round. This avoids both over-stuffing the README and losing the reasoning.

---

## 4. Components

### 4.1 Service: `GeocodingService`
- Input: free-form address string.
- Output: `{ zip:, lat:, lon:, formatted_address: }` or `nil`.
- Backed by `Geocoder.search(address)`; pull `postal_code` from the first result.
- Raises a typed error (`GeocodingService::AddressNotFound`) on no result.

### 4.2 Service: `WeatherService`
- Input: lat, lon (and optional unit preference).
- Output: a `Forecast` value object with `current_temp`, `high`, `low`, `daily:` array, `units:`.
- Calls Open-Meteo with `current_weather=true&daily=temperature_2m_max,temperature_2m_min,weathercode&forecast_days=5`.
- Wraps Faraday errors in `WeatherService::UpstreamError`.

### 4.3 Service: `ForecastService` (orchestrator)
- Input: address string.
- Steps:
  1. Geocode → get zip + lat/lon.
  2. Cache key: `"forecast:v1:#{zip}"`.
  3. Use a small wrapper that returns `{ forecast:, from_cache: Boolean }`:
     ```ruby
     cached = Rails.cache.read(key)
     return { forecast: cached, from_cache: true } if cached
     fresh = weather_service.fetch(lat, lon)
     Rails.cache.write(key, fresh, expires_in: 30.minutes)
     { forecast: fresh, from_cache: false }
     ```
     Using `read`/`write` explicitly (instead of `fetch { ... }`) is the cleanest way to know hit vs miss without monkey-patching.

### 4.4 Controller: `ForecastsController`
- `GET /` → form (`new` action).
- `POST /forecasts` → calls `ForecastService.call(params[:address])`, renders result.
- Use **strong params**; the address is the only user input.
- Rescue typed errors and re-render the form with flash messages.
- Apply `rate_limit` (Rails 8 built-in) on `:create` — see §7 for the configuration and rationale.

### 4.5 Views
- `new.html.erb`: address form.
- `create.html.erb` (or shared partial): location, current temp, high/low, 5-day list, and a clearly visible **"Served from cache"** badge when `from_cache` is true.
- Plain Rails defaults + a small amount of CSS — form is the priority, not styling.

### 4.6 Routes
```ruby
root "forecasts#new"
resources :forecasts, only: [:new, :create]
```

---

## 5. Caching strategy (the 30-minute rule)

- **Key:** `"forecast:v1:#{zip}"` — prefix with a version so you can invalidate on schema changes.
- **TTL:** `expires_in: 30.minutes`.
- **Scope:** keyed by *zip*, not by full address — two users entering different street addresses in the same zip share the cache (matches the spec).
- **Hit detection:** explicit `read` → `write`, not `fetch`, so `from_cache` is unambiguous.
- **What's cached:** the `Forecast` value object only. Don't cache the geocoding result under the same key — geocoding is per-address, weather is per-zip.
- Optional: also cache geocoding by normalized-address for a shorter TTL (say 24h) to cut Nominatim calls. Document as a "with more time" item if not done.

---

## 6. Error handling & edge cases

| Case | Behavior |
|---|---|
| Empty / blank address | Re-render form with "Please enter an address." |
| Geocoder returns no result | Flash "We couldn't find that address." |
| Geocoder returns a result with no postal code | Same as above (some countries / partial inputs). |
| Weather API timeout / 5xx | Flash "Weather service is unavailable — try again." |
| Non-US zips | Open-Meteo is global, so this works; only the *display* (units) needs handling. Default to °F, allow `?units=metric` toggle if time permits. |
| Cached entry exists for zip | Return immediately with `from_cache: true`. |

Set Faraday timeouts (e.g. 5s open, 5s read) so a stalled upstream doesn't hang a request.

---

## 7. Security & input handling

(Following the global security requirements: validate at the boundary, no secrets in code.)

- Address is the only untrusted input. Sanitize / strip; bound length (e.g. 200 chars) before passing to geocoder.
- No DB, no SQL — N/A for SQL injection, but stay parameterized if a model is added later.
- No auth needed (single-user demo), but **do** add a simple per-IP rate limit on `POST /forecasts` to protect the upstream geocoder/weather APIs from a runaway client or basic abuse:
  - Rails 8 ships `ActionController::RateLimiting` — one line in the controller, backed by `Rails.cache` (already `:memory_store`, so no extra infra):
    ```ruby
    class ForecastsController < ApplicationController
      rate_limit to: 10, within: 1.minute, only: :create,
                 with: -> { redirect_to root_path, alert: "Too many requests — try again shortly." }
    end
    ```
  - If we end up on a Rails version without the built-in limiter, fall back to `rack-attack` with an equivalent throttle (`throttle("forecasts/ip", limit: 10, period: 60) { |req| req.ip if req.post? && req.path == "/forecasts" }`).
  - Document in the README that the limit is per-process (memory-store) and would need Redis behind a multi-process deployment.
- The default stack (Open-Meteo + Nominatim) is **keyless**, so the submission ships with **no secrets at all** — nothing to leak. If we ever swap in a keyed provider (e.g. OpenWeatherMap) the key comes from `ENV` via the `dotenv-rails` gem:
  - Add `gem "dotenv-rails", groups: [:development, :test]` so production reads real `ENV` (set by the host) and dev/test reads `.env` / `.env.test`.
  - Commit a `.env.example` with placeholder keys (`OPENWEATHER_API_KEY=YOUR_API_KEY_HERE`) so a reviewer knows what to set without us leaking anything.
  - Add `.env*` (with `!.env.example` exception) to `.gitignore` *before* the first commit — once a real key lands in git history, rotating is the only safe recovery.
  - Trade-off vs Rails' built-in `credentials.yml.enc`: dotenv keeps secrets in plaintext on disk (so `.gitignore` discipline is load-bearing) but is simpler, framework-agnostic, and matches how most teams actually work. Credentials are encrypted-at-rest but add a master-key-management story we don't need for a take-home.
- CORS not relevant (server-rendered).

---

## 8. Testing plan

RSpec, organized by layer:

- **Service specs** (mocked HTTP via WebMock):
  - `GeocodingService` — happy path, no-results, malformed input.
  - `WeatherService` — happy path, upstream 500, timeout.
  - `ForecastService` — cache miss writes to cache; cache hit doesn't call `WeatherService`; `from_cache` flag is correct.
- **Request specs**:
  - `GET /` renders form.
  - `POST /forecasts` with valid address renders forecast.
  - Second `POST` with the same address shows the cache indicator.
  - Invalid address re-renders form with flash.
- **System spec**: Capybara end-to-end of the happy path.

Use Rails' built-in `:memory_store` for the test cache and `Rails.cache.clear` in a `before` block.

---

## 9. Project layout

```
avenue-code-forecast/
├── app/
│   ├── controllers/forecasts_controller.rb
│   ├── services/
│   │   ├── geocoding_service.rb
│   │   ├── weather_service.rb
│   │   └── forecast_service.rb
│   ├── models/forecast.rb          # PORO value object, not AR
│   └── views/forecasts/
│       ├── new.html.erb
│       └── create.html.erb
├── config/
│   ├── routes.rb
│   ├── initializers/geocoder.rb
│   └── environments/*.rb           # cache_store config
├── spec/
│   ├── services/
│   ├── requests/
│   └── support/
└── README.md
```

---

## 10. Implementation order (TDD commit sequence)

Each `feat:` commit bundles **spec + implementation + refactor** for one slice of behavior. TDD is followed *within* the working session — write the failing spec, see it red, implement until green, then refactor with the spec as a safety net — and only then stage everything and commit. The git log stays compact and review-friendly; the discipline is something to demonstrate in the live round rather than read off the history. Conventional-commit prefixes per global rules.

1. `chore: scaffold Rails app with RSpec, Faraday, geocoder, webmock` — test harness wiring (WebMock blocking real HTTP, `:memory_store` cache in `config/environments/test.rb`, shared `before { Rails.cache.clear }`).
2. `feat: WeatherService backed by Open-Meteo` — spec (current temp, daily high/low, upstream error), implementation, refactor.
3. `feat: GeocodingService backed by Nominatim` — spec (happy path, no result, blank input), implementation, refactor.
4. `feat: ForecastService with zip-keyed 30-min cache and from_cache flag` — spec (cache miss writes, cache hit sets `from_cache: true`, TTL respected), implementation, refactor.
5. `feat: ForecastsController and views` — request specs (form renders, valid address, cache indicator, invalid input), controller + ERB, refactor.
6. `docs: README with setup, design decisions, and trade-offs`
7. `chore: rubocop pass`

Rules of engagement (per `feat:` commit):
- Open the spec file *first*. Run `bundle exec rspec path/to/new_spec.rb` and confirm it actually goes red before writing any production code — that's the whole point of TDD, and skipping it turns the spec into a rubber stamp.
- Only write enough production code to make the new spec pass. Resist scope creep into the next slice.
- Refactor only with the full suite green. If a refactor drops you to red, revert the refactor — don't try to fix forward in the same session.
- Stage everything (spec + code + any view/refactor) into one commit. Run `bundle exec rspec` one last time before committing; the suite must be fully green at every commit boundary.
- Bug fixes follow the same shape: reproduce with a failing spec, fix, refactor — all in one `fix:` commit.

---

## 11. README outline (deliverable)

The README is graded as heavily as the code, but keep it focused on what a reviewer needs to **run** and **understand** the app at a glance. Deeper rationale lives in the gitignored `NOTES.md` (see §3).

1. **What it does** — one paragraph.
2. **Run locally** — `bundle install`, `bin/setup` (if used), `bin/rails server`, then visit `http://localhost:3000`. Ruby version. No API keys required.
3. **Run the tests** — `bundle exec rspec`.
4. **Architecture** — short diagram + one-line service-object explanation.
5. **Caching behavior** — exactly how the 30-min TTL works and what "from cache" means (this is a core spec requirement, so it stays in the README).
6. **Known limitations** — e.g. Nominatim rate limit, single-process cache, no auth.
7. **With more time** — Redis cache, units toggle, autocomplete, address history, OpenWeatherMap as a fallback provider, instrumentation.

Local-only `NOTES.md` (not committed) covers: rejected alternatives, why each choice over the others, things to defend during the live round.

---

## 12. Risk list / things to flag during the live round

- Open-Meteo is keyless — that's a deliberate trade-off for setup simplicity, not laziness. Be ready to defend it vs. a keyed provider.
- Cache is keyed by zip, not address — that's what the spec asked for, but it means two users in different parts of the same zip get the same forecast. Call this out.
- No DB / no migrations — intentional. The assignment doesn't need persistence beyond the cache.
- Nominatim's usage policy expects a real `User-Agent` header — configure it in the geocoder initializer.
- The 30-minute window starts at first cache write, not at the top of the hour. Confirm this matches the interviewer's expectation.

---

## 13. Definition of done

- [ ] App boots with `bin/rails server` after `bundle install` — no extra setup.
- [ ] Submitting an address shows current temp, high, low, and a 5-day outlook.
- [ ] Submitting the same zip within 30 minutes shows the "Served from cache" badge.
- [ ] Invalid / unresolvable addresses show a friendly error.
- [ ] `bundle exec rspec` is green.
- [ ] README covers run, design, trade-offs, and "with more time".
- [ ] Repo is public on GitHub and the link works in incognito.
- [ ] No occurrence of the forbidden brand name anywhere in code, commits, or README.
