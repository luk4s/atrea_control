# RD5 Reliability Implementation Plan

> **For agentic workers:** Runtime Tasks 1–7 and Task 8 documentation/CI are implemented and reviewed. Independent checks and packaging verification passed. Live login/reads were subsequently verified after correcting the synchronous handshake. Hardware-dependent write acceptance remains open below. Future runtime changes should retain the failing-regression-first workflow used here.

**Goal:** Make the existing RD5 cloud client reliable for reading snapshots and writing power/mode requests, with configuration-aware validation and meaningful errors.

**Architecture:** Keep `Login` for portal/unit sessions, `Request` for cloud HTTP, `UserCtrl` for configuration discovery, `SensorParser` for decoding/encoding, and `Unit` for validated snapshots and commands. Add one small RD5 configuration policy object rather than putting all register rules into `Unit`. Keep cloud mappings tied to firmware/configuration evidence.

**Tech Stack:** Ruby, Faraday with its stock Net::HTTP adapter, standard-library `Timeout`, Nokogiri, I18n, RSpec, WebMock, RuboCop; TZInfo `~> 2.0` for explicit IANA time zones. User-requested simplification removed the extra HTTP transport and all custom socket/resolver machinery. Login is capped at 300 seconds total; each HTTP operation at 60 seconds; verified commands retain their aggregate 30-second default.

## Scope and evidence

- RD5-only is intentional. Improve the existing cloud transport; aMotion and a Modbus TCP backend are outside this implementation.
- Source: user-supplied **Communication MODBUS — RD5 and aMotion**, version 04, cover issue `2025_04_25`, especially sections 2.3.1 and 3.1, pages 7–13. The contents page also gives a different issue date; identify the source by version and cover issue.
- Public document: https://atrea.eu/_files/documents/modbus-comm-amot-rd5-cz-v04_834.pdf . If that URL changes, retain the supplied document's identity and page references.
- The PDF defines register semantics for Modbus, not cloud HTTP framing, HTTP acknowledgements, authentication, or cloud rate limits. RD5's five-second Modbus batch interval must not be presented as a documented HTTP constraint.
- Historical baseline before implementation: 22 specs passed; `bundle exec rake` failed on `Style/DirectiveScope` in `spec/atrea_control/duplex/unit_spec.rb`; parser spec was empty. These gaps are now addressed.
- Verification after timeout simplification and the live-discovered timestamp fix: 675 examples passed and 34 files were lint-clean on Ruby 4.0.7, 3.3.10 and 3.4.9. Independent review approved the simplification, including explicit timeout exception classes and three TLS-connect cleanup regressions. Transport-specific fake socket/resolver suites were replaced by smaller standard-timeout tests. CI's floating Ruby 3/4 entries were not run as separate environments beyond these installed versions.
- Follow-up live audit on 2026-10-25: after production-client shutdown, the old handshake still timed out despite a recent unit contact. Comparing current portal source identified missing `Sync=1` on the unit-login POST. Adding it obtained SID and valid readings after about 127 seconds; the corrected public API then logged in in 5.86 seconds and passed configuration/values/getters/JSON plus three refreshes. A further run passed command construction without dispatch and controlled-clock expiry/recovery using a live snapshot. Package `3001022` matches `CONTROL_VERSION=003001022`. Live writes, ACK and requested-value read-back semantics remain unverified. No credentials, names, unit IDs or SID values retained.
- Faraday-only follow-up: login completed in 1.45 seconds, with valid values and refresh using stock Net::HTTP for both clients; no HTTPX loaded and no control writes dispatched. An earlier read exposed valid unpadded timestamp components (`17:7:32`); normalize those fields before existing strict calendar/timezone validation. Regression coverage includes the actual format, other single-digit fields and invalid dates/times.
- Preserve existing getters, string-keyed configuration maps and symbol-keyed `Unit#values`. Document deliberate behavior changes: invalid setter inputs become errors; stale getters stop returning data; unavailable optional temperatures become `nil`; manual control no longer gets unconditionally switched to temporary control.

## What the PDF changes in the review

| Topic | RD5 evidence | Implementation consequence |
| --- | --- | --- |
| Power | `H10704` read, `H10708` write; `H10510` selects interpretation | Do not validate every unit as a simple 0–100 percentage device. |
| Modes | `H10705` read, `H10709` write, values 0–7 with equipment/season conditions | Validate against discovered modes and supported configuration. Do not confuse a user-input label with a requested numeric mode. |
| Scheduled control | `H10700` / `H10701`: 0 manual, 1 scheduled, 2 temporary | Add temporary override only for scheduled/temporary control, including power zero. Preserve manual control. |
| Temperature | `H10706` is requested temperature, 100–400 represents 10–40 °C | Historical `preheat_temperature` is not a measured preheater temperature. Add an accurately named alias, preserving the old key. |
| Temperature addresses | PDF calls `I10211` T-ODA; old portal fixtures use `I10208` | No blanket address substitution. Verify firmware/profile and preserve configuration-derived mappings. |
| Heating state | `C10200` is a water-heater pump, `C10215` a heat-pump heating signal | Existing OR of heating registers does not prove preheater operation. Document legacy meaning; do not invent a new preheater mapping. |
| Confirmation | Examples read the corresponding request value back after writing | Add explicit, bounded read-back verification; HTTP 200 alone is insufficient. |

## Design decisions

1. **Repair the cloud client in place (selected).** Small coherent changes, existing entrypoints retained. A generic multi-transport rewrite adds unnecessary scope; replacing cloud with Modbus would require LAN connectivity and unit setup that are not prerequisites today.
2. Keep `AtreaControl::Error` as the common base. Add `AuthenticationError`, `UnitConnectionTimeout`, `ProtocolError`, `TransportError`, `UnsupportedConfiguration` and `WriteNotConfirmed` subclasses. Keep `SessionExpired` for missing/stale snapshot timestamps as the existing recovery contract, while documenting that this is a freshness error rather than proof of failed authentication.
3. Make parsing, validity, command construction and transport distinct. A parser/configuration failure must never send a write or publish a partial snapshot.
4. No automatic write retries. A connection timeout can occur after the unit accepted a command. Verification timeout means outcome unknown, not proof of rejection.
5. Use runtime register data and declarative configuration; never evaluate downloaded JavaScript or Ruby. Existing locale-regeneration `eval` must be removed or replaced with a non-executing parser before that utility is used.

## Task 1 — Credential-safe diagnostics and transport errors

**Files:** `lib/atrea_control.rb`, `lib/atrea_control/logger.rb`, `lib/atrea_control/duplex/login.rb`, `lib/atrea_control/duplex/request.rb`; new `spec/atrea_control/duplex/request_spec.rb`, `spec/atrea_control/logger_spec.rb`; extend `spec/atrea_control/duplex/login_spec.rb`.

- [x] Add specs capturing a test logger during both successful and failed login. Use synthetic values `secret-password`, `secret-cookie`, `secret-sid`; assert none appears in captured output. Do not merely assert that DEBUG is disabled.
- [x] Remove SID interpolation and full response-body logging. Log stage, HTTP status, elapsed time and poll counts without user IDs, cookies, passwords, auth-bearing URLs or raw error bodies.
- [x] Add HTTP specs for successful responses, 401/403, 429/500, connect timeout and read timeout. Test the intentional login POST redirect separately from unit requests; do not globally reject the expected login 302.
- [x] Define the error subclasses above. For unit requests, map authentication status failures to `SessionExpired`, other failed HTTP responses/network errors to `TransportError`. For portal login, use `AuthenticationError` for positively identified rejected credentials. Timeouts specifically use `UnitConnectionTimeout < TransportError`.
- [x] Configure Faraday/Net::HTTP with 10-second connect and 60-second read defaults plus a 60-second total HTTP timeout; expose shorter overrides. Explicit standard-library timeout exceptions preserve socket cleanup. Error messages identify stage/status, not credentials. No automatic command retries.
- [x] Add regressions showing setters do not silently accept HTTP 403 or 500. A successful HTTP response only establishes transport success; Task 6 handles application/read-back confirmation.

Example request regression, using the existing `Request#call` API:

```ruby
request = AtreaControl::Duplex::Request.new(user_id: "1", unit_id: "unit", sid: "secret-sid")
stub_request(:get, %r{control\.atrea\.eu/+comm/sw/unit\.php})
  .to_return(status: 403, body: "denied")
expect { request.call(_t: "config/xml.cgi", _w: 1) }
  .to raise_error(AtreaControl::SessionExpired)
```

**Verify:** `bundle exec rspec spec/atrea_control/duplex/request_spec.rb spec/atrea_control/duplex/login_spec.rb spec/atrea_control/logger_spec.rb`.

## Task 2 — Parse validated snapshots, not incidental XML

**Files:** `lib/atrea_control/sensor_parser.rb`, `lib/atrea_control/duplex/user_ctrl.rb`, `lib/atrea_control.rb`; `spec/atrea_control/sensor_parser_spec.rb`, `spec/atrea_control/duplex/user_ctrl_spec.rb`; fixtures under `spec/fixtures/files/`.

- [x] Populate the empty parser spec. Derive XML variants in examples with Nokogiri rather than maintaining multiple copies of the large `unit.xml` fixture.
- [x] Test missing `RD5WEB`, missing/blank/invalid `t`, absent required registers, missing `V`, non-numeric `V`, malformed XML and an HTML login response.
- [x] Validate XML structure and timestamp before sensor extraction. Missing timestamp raises `SessionExpired`; an invalid timestamp or malformed/non-unit payload raises `ProtocolError`. Never leak accidental `NoMethodError`/`ArgumentError` or silently convert malformed numbers to zero.
- [x] Introduce `SensorParser#raw_values(xml)`: validated register ID → unsigned integer map. Keep existing `parse`/`values` entrypoints as projections for compatibility; decode signed temperature values only when applying the temperature field definition, not indiscriminately to configuration registers.
- [x] Test signed temperature boundaries: 65535 → -0.1 °C, 65036 → -50.0 °C, 0 → 0.0 °C, 1300 → 130.0 °C. Test a non-temperature raw register above 32767 stays unsigned.
- [x] Preserve documented last-occurrence behavior for duplicate register IDs and test it explicitly.
- [x] Memoize successfully parsed `UserCtrl#user_ctrl` XML per instance. Test one HTTP fetch for configuration discovery and no cached invalid XML; recreating the object refreshes configuration.
- [x] Remove the unused private `update_locales_files!` executable-evaluation utility; keep checked-in locale files.

**Verify:** `bundle exec rspec spec/atrea_control/sensor_parser_spec.rb spec/atrea_control/duplex/user_ctrl_spec.rb`.

## Task 3 — Atomic cache, consistent getters and explicit time zones

**Files:** `lib/atrea_control/duplex/unit.rb`, `lib/atrea_control/sensor_parser.rb`, `atrea_control.gemspec`, `Gemfile.lock`; `spec/atrea_control/duplex/unit_spec.rb`, `spec/atrea_control/sensor_parser_spec.rb`.

- [x] Add end-to-end Unit specs with the real parser and a controlled clock. Locally override the existing global `valid?` stub with `and_call_original` for these examples.
- [x] Cover an initially stale response; a valid snapshot that ages; a failed refresh after a valid snapshot; and false/zero values. Exercise `values`, `parsed`, `power`, `mode`, temperature readers, `preheating?`, `timestamp`, `as_json` and `to_json`.
- [x] Store one validated snapshot. Parse and validate before publication. If refresh fails, invalidate publicly accessible data; no accessor may expose the old snapshot as current. No last-known snapshot is exposed as current.
- [x] Implement validity against snapshot state directly, avoiding `timestamp → values → valid? → timestamp` recursion. A cached getter checks age without an implicit network refresh; `refresh!` remains the explicit fetch operation. Initial getter access may fetch once, preserving current convenience.
- [x] Preserve the strict 15-minute boundary: timestamp equal to `now - 900` is invalid. Reject timestamps more than 60 seconds in the future; allow up to 60 seconds of clock skew. Test these boundaries with a frozen/stubbed clock.
- [x] Add optional `time_zone:` to `Unit` and parser initialization. Use TZInfo `~> 2.0` for an explicit IANA zone; `nil` retains process-local interpretation for compatibility. Do not mutate process-global `ENV["TZ"]` in runtime code or hardcode every device to Czech time.
- [x] Test explicit `Europe/Prague` timestamps in winter and summer while the process uses UTC. Ambiguous/nonexistent DST-local times raise `ProtocolError`, rather than silently choosing a different instant. Document that an explicit zone is required to remove deployment-zone ambiguity.

**Regression acceptance:** after `unit.values` rejects an old XML snapshot, `unit.power` must also raise `SessionExpired`, rather than return the fixture's `88.0`.

**Verify:** `bundle exec rspec spec/atrea_control/duplex/unit_spec.rb spec/atrea_control/sensor_parser_spec.rb`.

## Task 4 — RD5 configuration and truthful sensor semantics

**Files:** new `lib/atrea_control/duplex/rd5_configuration.rb`, `spec/atrea_control/duplex/rd5_configuration_spec.rb`; update `lib/atrea_control/duplex.rb`, `lib/atrea_control/duplex/user_ctrl.rb`, `lib/atrea_control/sensor_parser.rb`, `lib/atrea_control/duplex/unit.rb`, `spec/support/user_ctrl.rb` and related specs.

- [x] Add an autoloaded `RD5Configuration` policy object consuming the decoded raw register map (accepted class-name adjustment from the original `Rd5Configuration` design). It reads configuration only; it never writes service registers.
- [x] Capture and test fixture-derived `H10510`, `H10501`, `H11300`, `H11700`, `C10508`, `C10509`, `I11401` and the power/mode schedule-control registers. Missing configuration needed for a command raises `UnsupportedConfiguration`; do not guess a safe default. Follow-up live discovery confirmed this unit's available subset and successful direct-speed power/mode command construction without dispatch.
- [x] Replace the first-match inlet-temperature regex with an explicit resolver for the supported `userCtrl` profile. For the existing fixture: `H11300=0` selects M1/M2 temperature using `H10501`, fan state and the 126.0 sentinel; `H11300=1` uses `I10204`; unsupported/unavailable cases return `nil` for that optional temperature.
- [x] Test every branch from `userCtrl.xml:448–463`, including stopped fans, missing optional temperature registers and sentinel values. Do not use `eval` to reproduce JavaScript.
- [x] Keep outdoor-temperature mapping derived from `UserCtrl`. Add a synthetic configuration with a different outdoor ID and assert the parser follows it. PDF page 11 alone does not authorize replacing fixture `I10208` with `I10211`.
- [x] Add `required_temperature` as an alias for the value historically exposed as `preheat_temperature`; keep the old reader and hash key. Explain the alias in README/CHANGELOG. Adding a hash key is additive but must be noted for consumers matching exact key sets.
- [x] Keep the legacy `preheating` behavior documented as a heating-related aggregate until a dedicated RD5 preheater mapping is captured. PDF page 11 is insufficient evidence to relabel water-pump/heat-pump status as preheater operation. No fabricated replacement register.

**Verify:** `bundle exec rspec spec/atrea_control/duplex/rd5_configuration_spec.rb spec/atrea_control/duplex/user_ctrl_spec.rb spec/atrea_control/sensor_parser_spec.rb spec/atrea_control/duplex/unit_spec.rb`.

## Task 5 — Correctly encoded, configuration-aware commands

**Files:** `lib/atrea_control/sensor_parser.rb`, `lib/atrea_control/duplex/rd5_configuration.rb`, `lib/atrea_control/duplex/unit.rb`, `lib/atrea_control/duplex/user_ctrl.rb`; parser/configuration/Unit specs.

- [x] Specify accepted setter types: integer, finite integral Float, or an ASCII decimal-digit string. Normalize `88`, `88.0`, `"88"` to integer 88. Reject `nil`, booleans, fractional values, infinities, NaN, negative numbers and strings such as `"88.0"` before HTTP. Never silently truncate or clamp.
- [x] The low-level encoder checks a valid discovered holding-register ID and a nonnegative 16-bit integer, then emits exactly five decimal digits after the register ID. Command-specific range checks belong in `RD5Configuration`.
- [x] Test exact encoder output, not only the destination endpoint. Low-level `SensorParser#input` intentionally requires an Integer; normalization of accepted Float/String inputs occurs at the Unit setter boundary:

```ruby
expect(parser.input("H10708", 88)).to eq("H1070800088")
expect { parser.input("H10708", 88.0) }.to raise_error(ArgumentError)
expect { parser.input("H10708", nil) }.to raise_error(ArgumentError)
expect { parser.input("H10708", 88.5) }.to raise_error(ArgumentError)
```

- [x] Implement the PDF page 9 power matrix:

| `H10510` | Allowed command values |
| --- | --- |
| 0, direct speed | 0 or integers 12–100 |
| 1, constant flow | integers 0–100 |
| 2, constant pressure | 0, 1, 2 |
| 3, external input | no power writes; raise `UnsupportedConfiguration` |
| 4, multiport | 0, 10–12, 20–22, 30–38 |
| missing/unknown | raise `UnsupportedConfiguration` |

- [x] Validate modes against discovered choices and PDF page 10 prerequisites: 0/2 unrestricted; 1/6/7 need `C10508=0`; 3 also needs `C10509=1`; 4 also needs `H11700=1`; 5 needs `I11401=1`. Unknown prerequisites fail explicitly. Preserve numeric mode IDs independently of translated labels.
- [x] Derive both the power input and its control-switch register from the unit configuration, as already done for mode. Accept only complete matched/tested command forms; remove the unconditional literal `H1070000002` shortcut.
- [x] Construct one command request: manual control 0 → setpoint only; scheduled/temporary 1/2 → setpoint plus switch=2. Test both power/mode and all three control states. Crucially, scheduled `power=0` still includes `H10700=2`.
- [x] Never force `H10700..H10703=0` merely because the PDF recommends manual operation for BMS. Changing permanent schedule policy is a separate user action, outside these setters.
- [x] Assert invalid inputs/configuration generate no write request. Invalidate on every write attempt, including failures, so subsequent reads cannot report the pre-write cache as current.

**Verify:** `bundle exec rspec spec/atrea_control/sensor_parser_spec.rb spec/atrea_control/duplex/rd5_configuration_spec.rb spec/atrea_control/duplex/unit_spec.rb`.

## Task 6 — Explicit confirmation without claiming actual airflow

**Files:** `lib/atrea_control/duplex/unit.rb`, `lib/atrea_control/duplex/request.rb`, `lib/atrea_control/duplex/user_ctrl.rb`; Unit/request specs; sanitized response fixtures from Task 8.

- [x] Add explicit `set_power(value, verify: true, timeout: 30, poll_interval: 5)` and `set_mode` methods returning the confirmed normalized requested value when verification succeeds; `verify: false` returns the unconfirmed HTTP response. Existing `power=`/`mode=` delegate with `verify: false` to retain non-polling setter behavior, but still perform input and HTTP error checks. Document that Ruby assignment expressions themselves evaluate to the assigned value, not a confirmation result.
- [ ] Use captured cloud responses to identify any documented/observed acknowledgement. Do not invent an `<ok>` shape or treat arbitrary HTTP 200 HTML as success. If no application acknowledgement exists, only read-back can claim confirmation.
- [x] Implement fresh, newer-than-baseline requested-value verification with numeric comparisons, not translated mode/actual fan speed. Accepted adjustment: `Unit.new(verification_registers: ...)` takes a nonempty Hash with only symbol keys `:power`/`:mode` and `H` plus five-digit String values. Caller must independently prove semantics. No PDF or fixture address is trusted by default; requested-value mapping and live write acceptance remain deferred despite successful live reads.
- [x] If a cloud profile lacks a proven requested-value mapping, verified methods raise `UnsupportedConfiguration` before writing. Transport-only setters remain documented as unconfirmed.
- [x] Test delayed propagation, matching stale cache, external-input override, rejected requests and timeout using a fake monotonic clock; no real sleeping. Polling never resends the write. A stale matching snapshot must not satisfy verification.
- [x] On verification timeout, raise `WriteNotConfirmed` with a redacted message indicating unknown outcome. Document that setpoint confirmation does not prove physical airflow or override safety functions. One standard `Timeout` wrapper covers baseline, lazy configuration discovery, dispatch and read-back; pre-dispatch expiry uses `UnitConnectionTimeout`. No deadline callbacks are threaded through Unit/UserCtrl/Request.

**Verify:** `bundle exec rspec spec/atrea_control/duplex/unit_spec.rb spec/atrea_control/duplex/request_spec.rb`.

## Task 7 — Bounded login, explicit unit choice and version evidence

**Files:** `lib/atrea_control/duplex/login.rb`, `lib/atrea_control/duplex/request.rb`, `lib/atrea_control/duplex/unit.rb`; login/request specs and sanitized fixtures.

- [x] Validate required cookies, nonempty client ID, unit records, `ident`, login/sended nodes and nonempty nonzero SID. Rejected credentials use `AuthenticationError`; invalid response shapes use `ProtocolError`; exhausted unit connection wait uses `UnitConnectionTimeout`.
- [x] Add optional `unit_id:` selection by unit `ident` to `Login.user_tokens` and `Login.new`. Preserve first-unit behavior when omitted. Use listed unit records to resolve ownership; test no matches and multiple units without leaking identifiers into logs.
- [x] Replace `time.times` with a monotonic polling deadline and `timeout: 300`, `poll_interval: 1`. Login's entire flow is wrapped in standard `Timeout`; larger-than-300-second budgets are rejected. Each HTTP operation is independently capped at 60 seconds, and the outer flow timer also applies. Server ETA does not control iteration or termination. Test last-permitted-poll success, perpetual zero SID and blocked HTTP using fake clocks/short standard timeouts.
- [x] Interpret server ETA as a wait estimate, not proof of incorrect credentials or an offline unit. Test successful account login followed by an unavailable unit as a separate failure stage.
- [x] Compare advertised package with `CONTROL_VERSION` using successful unit-record discovery: `3001022` normalizes to `003001022`. Retain the constant; no dynamic `version:` API was added. This is package evidence only, not successful SID/configuration/read-back compatibility.
- [x] Do not reinstate `run_rd5_app` based only on its old comment; request remains absent without evidence.
- [x] Compare the current browser application's source request sequence. Its `sendSync` helper adds `Sync=1`; RD5 `setUnit` uses it for `unitLogin`. Add that parameter and a regression requiring it before SID establishment. Public-API live success confirms the fix; no application-launch request was needed or reinstated. No GUI browser capture was performed.

**Verify:** `bundle exec rspec spec/atrea_control/duplex/login_spec.rb spec/atrea_control/duplex/request_spec.rb`.

## Task 8 — Integration evidence, documentation and release readiness

**Files:** `README.md`, `CHANGELOG.md`, `.github/workflows/main.yml`, `spec/atrea_control/duplex/unit_spec.rb`; new `docs/rd5-cloud-protocol.md` and sanitized fixtures.

- [x] With an available RD5 unit, verify account login, SID acquisition, configuration discovery, `values`, three `refresh!` calls, getters/JSON, unit-name reader and a getter after controlled cache expiry/recovery. Record sanitized package/mapping/configuration metadata, without credentials, names, IDs or SID.
- [x] Diagnose the failed handshake against current portal source and confirm the minimal `Sync=1` correction with live reads. A GUI browser replay was not required; keep fixture suite independent of hardware.
- [x] Record declarative profiles and the follow-up live evidence in `docs/rd5-cloud-protocol.md`: discovery forms, unsigned raw registers, inlet resolver, request/effective distinction, schedule policy and temperature/legacy heating limitations. Live reads are confirmed for this profile; ACK/read-back/write acceptance remains unverified. No invented preheater mapping.
- [ ] For a separately agreed live write test, record original request values and schedule-control states; change one ordinary power/mode setting, verify via the portal and fresh snapshot, then restore the originals and confirm restoration. Restoring the numeric setpoint alone is insufficient if the command also changed manual/schedule/temporary state. Do not change service configuration.
- [x] Resolve the existing `Style/DirectiveScope` offense (already fixed by earlier runtime work; prior full lint clean, no further spec edit needed). Add a separate RuboCop CI job while retaining the Ruby test matrix and existing action versions.
- [x] Update README with implemented APIs, explicit zone handling, errors, power domains, aliases, schedule behavior and verified/unconfirmed writes. Include migration notes for `nil` rejection, stale getters and added hash key; update plan statuses.
- [x] Require a major upgrade from 3.2.x because rejected historical inputs, getter errors and schedule policy change behavior. Preserve the working tree's version choice; publishing requires a separate request.
- [x] Run `bundle exec rake` on Ruby 4.0.7; full RSpec and RuboCop on Ruby 3.3.10 and 3.4.9. After timeout simplification and the timestamp fix, all three environments: 675 examples passed, 34 files lint-clean. Only these installed versions were tested, not every patch-level Ruby installation or a remote CI run.
- [x] Verify initial packaging through a temporary `GIT_INDEX_FILE` containing intended runtime/docs files, leaving the real staging index untouched. `bundle exec rake build` produced `pkg/atrea_control-3.2.1.gem`; all 20 runtime/locale files then matched source, including new helpers; no specs or `.env` included. Unpacked gem loaded entrypoint, classes, dependencies and locales outside workspace. Original root archive was backed up/restored byte-for-byte. Sources were subsequently staged for the separately requested gem PR; normal builds must include all new runtime files. No release command run.
- [x] Rebuild after the `Sync=1` fix and verify the unpacked gem outside the workspace against the live RD5 portal: login in 5.9 seconds, valid eight-field snapshot and successful refresh. No control writes dispatched.

**Task 8 verification ownership:** documentation worker validated workflow YAML,
compiled README Ruby snippets without running them, cross-checked source APIs and
ran `git diff --check`. Parent completed independent checks on three Ruby versions,
temporary-index build/content/load inspection and whole-code review. Implementation
verification preceded the separately requested PR/staging step; no publishing was
performed. Read-only live login was
parent-owned; no live device-control writes occurred.

**Documentation verification evidence:** Psych safe-load validated workflow
structure, including YAML 1.1's possible boolean `on` key, retained spec matrix
and separate lint command; all four README Ruby snippets compiled without
execution. Focused `bundle exec rubocop --only Style/DirectiveScope
spec/atrea_control/duplex/unit_spec.rb` inspected one file with no offenses.
Source APIs/errors and original fixture forms were cross-checked locally.

## Follow-up: persisted inlet-source metadata

- Replace the unreleased `input_temperature_profile` accessor with JSON-safe
  `input_temperature_source` (`"rd5_standard"` / `"unsupported"`) and include it
  in `UserCtrl.data`. Keep conditional sensor interpretation entirely in the gem.
- Verify discovery → JSON → persisted-fields object → Unit/parser, including
  distinct M1/M2/direct readings and unavailable/unsupported cases.
- In `home_control`, expose the metadata through its existing JSON store, refresh
  older caches on next control access, and discard cached Unit on login refresh.
  No schema migration or hardware-selection rules in the UI are needed.
- Update the consumer to `atrea_control ~> 4.0`; validate with a locally built and
  installed 4.0.0 gem. Publish/provide that gem before deploying the consumer.
  Render unavailable readings as an em dash, omit them from InfluxDB fields, and
  preserve valid zero-degree readings.
- Verification: gem 689 examples passed on Ruby 4.0.7, 3.3.10 and 3.4.9; full gem
  lint clean across 35 files. Home 44 Rails examples and three Node rendering
  tests passed; all seven changed Ruby files are lint-clean. Full Home lint still
  reports 15 existing offenses in untouched files. No cloud/control calls made
  during this integration work; staging and commits were deferred until the
  separately requested gem PR.

## Execution order and acceptance

Tasks 1 → 2 → 3 establish trustworthy errors and snapshots. Task 4 → 5 makes writes configuration-aware. Task 7 follows transport work. Task 6 implementation is complete with explicit caller-proven `verification_registers:`; default verified operations deliberately fail closed. Current live login/read acceptance passed after the synchronous-handshake fix; requested-value mapping, ACK and actual control writes still require separate evidence.

Completion requires:

- No secrets in successful or failed login logs.
- No invalid/old snapshot accessible through current-value readers or serializers.
- Parser errors belong to the library's error hierarchy, with no fabricated zero readings.
- Exact five-digit command encoding and all five RD5 power configurations tested.
- Manual schedule policy preserved; temporary overrides correct for zero and nonzero power.
- Request acceptance distinguished from confirmed setpoint and from physical operation.
- Current RD5 end-to-end read verified, or the remaining hardware/protocol blocker stated explicitly.
- Full specs and lint pass; newly introduced runtime files included in the build.

Future extensions such as temperature/zone setters, alarm APIs, flow telemetry, external temperature injection and Modbus transport are separate work. In particular, external temperature injection's 90-second refresh requirement must not be confused with ordinary power/mode writes, which the PDF says need not be repeated periodically.
