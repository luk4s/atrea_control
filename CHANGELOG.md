## [Unreleased]

## [4.0.0] - 2026-10-26
### Breaking changes
- Reject `nil` (formerly liable to become zero), booleans, negative/fractional
  values and malformed setter strings with `ArgumentError`; never truncate or clamp.
- Validate power domains, discovered modes, equipment prerequisites and schedule
  state. Unsupported or incomplete configuration now fails explicitly.
- Recheck freshness on all current-value getters and serializers. Failed refresh
  invalidates accessible data until `refresh!`; stale cached values no longer leak.
- Preserve manual schedule control; scheduled/temporary writes request temporary
  control even for zero power, rather than unconditionally switching policy.
- Return `nil` for unavailable/unsupported optional inlet temperature, not a
  fabricated zero. Add `required_temperature` reader/hash key while retaining
  historical `preheat_temperature`; both mean requested temperature.

### Change
- Export JSON-safe `input_temperature_source` in `UserCtrl.data` so persisted
  configuration retains conditional inlet sensor selection. Custom `user_ctrl:`
  objects should expose that metadata; the unreleased `input_temperature_profile`
  accessor is replaced. Sensor-selection rules stay in the gem, not consumer UIs.
- Include `Sync=1` on the unit-login POST, matching the current portal's
  synchronous handshake. Without it, the session query could stay at SID zero
  despite recent unit communication. Add a regression that requires this flag
  before establishing a session.
- Parse strict unit/configuration XML and unsigned raw registers; decode signed
  temperatures only at projection. Reject malformed data through library errors.
- Accept valid device timestamps without leading zeroes, as observed live
  (`17:7:32`), while retaining strict date/time and timezone validation.
- Publish atomic snapshots, enforce the strict 15-minute age boundary and allow
  at most 60 seconds of future clock skew. Discard snapshots on every write attempt.
- Add `RD5Configuration`, configuration-derived command/control mappings and exact
  unsigned 16-bit command encoding. Never execute downloaded configuration code.
- Add optional IANA `time_zone:`; `nil` retains process-local interpretation.
  Invalid zones and ambiguous/nonexistent DST timestamps raise `ProtocolError`.
- Add `set_power`/`set_mode` with verification enabled by default, a 30-second
  absolute budget and five-second polling. Verification requires caller-supplied,
  independently proven `verification_registers:`; no current cloud read-back
  profile is automatically trusted. Missing mappings fail before writing.
- Keep assignment setters unconfirmed (`verify: false`); HTTP success alone is
  not application acknowledgement. Verification timeout after dispatch reports
  unknown outcome through `WriteNotConfirmed`, without write retries.
- Add explicit login unit selection by `ident` (default: first listed unit), a
  five-minute total limit, one-second polling and bounded HTTP requests.
  Distinguish authentication, protocol, transport, timeout and configuration errors.
- Add `tzinfo ~> 2.0` for explicit IANA/DST handling. Keep Faraday/Net::HTTP as
  the sole HTTP transport, with standard-library total timeouts: login at most
  300 seconds, each HTTP operation at most 60 seconds. Remove the HTTPX dependency,
  custom transport plugin and socket/resolver machinery. Explicit timeout exception
  classes preserve Net::HTTP TLS cleanup. Automatic retries remain disabled.
- Verify live RD5 login, configuration, values, getters/JSON, three refreshes and
  expiry/recovery on 2026-10-25 after correcting the handshake. Validate command
  construction against the live configuration without dispatching writes.
  Acknowledgements, live writes and requested-value read-back remain unverified.
  Add an independent RuboCop CI job alongside the Ruby spec matrix.

### Security
- Remove credential-bearing response/URL/SID diagnostics and executable locale
  regeneration; validate XML without DTD/network resolution. Login diagnostics
  retain stage, status, elapsed time and poll counts without secrets.
- upgrade ruby 4.0.7
- upgrade gems

## [3.2.0] - 2026-04-16
### Security
- upgrade gems
- drop ruby <3.3 support

## [3.1.0] - 2025-11-14
### Changed
- upgrade dependencies
- replace RestClient by Faraday

## [3.0.1] - 2025-03-17
### Security
- upgrade gems
### Change
- update rubocop (plugins)

## [3.0.0] - 2025-01-25
### Removed
- selenium-based login procedure
### Added
- token / phpsessionid-based login in background
- "session" validity check & expiration (exception)
### Changed
- ruby version 3.3+

## [2.2.0] - 2024-10-20
### Added
- timestamp from atrea server
### Changed
- upgrade dependencies
- upgrade ruby version

## [2.2.0] - 2023-10-09
### Changed
- update dependencies

## [2.1.3] - 2023-02-04
### Fixed
- preheating is always boolean, so no need !! => which coused reverse right now...

## [2.1.2] - 2023-02-03
### Fixed
- selenium-webdriver deprecations
- some code-style/rubocop offenses
## [2.1.1] - 2022-08-21
### Fixed
- override "schedule program" by "temporary"
### Changed
- dependencies update

## [2.1.0] - 2022-02-28
### Added
- preheating  is ON ?
- heat temperature
- current input temperature
### Removed
- debug

## [2.0.2] - 2022-01-20
### Added
- debug unit values
- try token-based login (without success)

## [2.0.1] - 2021-12-26
### Fixed
- write correct arguments

## [2.0.0] - 2021-12-26
### Changed
- refactored codebase to more readable classes
- selenium used only for login and then close => obtain SID (and user with unit)
- login waiting mechanism
### Added
- found way how to change mode & power (tell unit to change)

## [1.4.1] - 2021-12-18
### Changed
- little refactor

## [1.4.0] - 2021-12-12
### Changed
- founded way to get config and data from Atrea server

## [1.3.1] - 2021-12-11
### Changed
- version of selenium

## [1.3.0] - 2021-12-11
### Changed
- store auth tokens outside
- minimize selenium only for login

## [1.2.1] - 2021-10-30
### Changed
- login procedure
- ensure logged user by window.user object

## [1.2.0] - 2021-10-26
### Changed
- use internal unit.php for read values
- reload login automatically if session expire
## [1.1.0] - 2021-10-22
### Added
- to_json

## [1.0.0] - 2021-09-13
- Initial release
