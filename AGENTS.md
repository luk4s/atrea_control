# Repository guidance

## Commands and toolchain
- Install dependencies: `bin/setup` (`bundle install`).
- Full local checks: `bundle exec rake` runs specs, then RuboCop.
- CI runs the RSpec Ruby matrix and a separate `bundle exec rubocop` job.
- Focused test: `bundle exec rspec spec/atrea_control/duplex/unit_spec.rb`;
  append `:LINE` to select an example.
- Ruby versions differ across config: `.ruby-version` pins 4.0.7, gemspec
  allows >= 3.2, RuboCop targets 3.3. Do not infer minimum Ruby from local version.
- RuboCop inherits `.rubocop_todo.yml`; RSpec message expectations use
  `receive`, not `have_received`.

## Protocol and state
- This gem wraps Atrea RD5's web portal. `Duplex::Login` obtains tokens;
  `Duplex::Request` performs unit requests; `UserCtrl` discovers sensor/mode
  mappings; `SensorParser` decodes readings and encodes writes.
- Sensor and mode maps use string keys. Derive sensor IDs from `UserCtrl`;
  fixture IDs are not universal device configuration.
- `UserCtrl.data` is persisted by `home_control`. Preserve JSON-safe
  `input_temperature_source` metadata when exporting/reconstructing `user_ctrl:`;
  a sensor ID alone cannot represent conditional inlet-temperature selection.
- RD5 Modbus register semantics inform command policy, not cloud HTTP framing.
  See `docs/rd5-cloud-protocol.md` for supported profiles and evidence limits.
- `Unit` caches parsed readings; `refresh!` fetches again. `values` raises
  `AtreaControl::SessionExpired` when device timestamp is missing or older
  than 15 minutes, rather than relying on HTTP authentication errors.
- All current-value readers validate snapshots. Failed refresh stays failed until
  explicit `refresh!`; write attempts discard prewrite data even on failure.
- `set_power`/`set_mode` verify by default and require caller-proven
  `verification_registers:`; legacy setters are transport-only. Never infer a
  read-back register from PDF addresses or automatically replay timed-out writes.
- Use Faraday/Net::HTTP: login has a 300-second total limit, HTTP requests 60.
  Standard `Timeout` wrappers use an explicit exception class so Net::HTTP closes
  sockets during TLS setup; do not reintroduce a custom transport or write retries.
- Loading `atrea_control` registers `config/locales/*.yml` and sets global
  `I18n.default_locale` to `:cs`.

## Tests
- Specs use WebMock and XML/HTML fixtures in `spec/fixtures/files`;
  normal test runs need no portal credentials or physical unit.
- Support files are not auto-loaded. Specs using shared `"userCtrl"` context
  explicitly require `spec/support/user_ctrl.rb`.
- `unit.xml` contains an old timestamp; most Unit specs stub `valid?`.
  Exercise real validity behavior with controlled timestamps.

## Packaging
- Gem contents come from `git ls-files`, excluding test/spec/features.
  New runtime files must be tracked to enter built gem.
- `bundle exec rake release` pushes commits/tags and publishes to RubyGems;
  it is not a local verification command.
