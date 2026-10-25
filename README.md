# atrea_control

Ruby client for ATREA DUPLEX ventilation units with **RD5 regulation**, using
the [RD5 cloud portal](https://control.atrea.eu/). RD5-only support is intentional:
this unofficial gem uses cloud HTTP/XML, not aMotion Cloud or Modbus TCP.

**Login and end-to-end reads were verified against a live RD5 unit on 2026-10-25:**
configuration discovery, fresh snapshots, getters/JSON and repeated refreshes
succeeded. A missing `Sync=1` parameter in the unit-login request was corrected
after comparison with the current portal. Live writes and requested-value
read-back semantics remain unverified. See [protocol evidence and limitations](docs/rd5-cloud-protocol.md).

## Installation

```ruby
gem "atrea_control"
```

Run `bundle install`, or install directly with `gem install atrea_control`.

## Login and snapshots

Supply credentials through your application's environment. The library does not
load `.env` files automatically. Never log credentials or returned tokens.

```ruby
require "atrea_control"

tokens = AtreaControl::Duplex::Login.user_tokens(
  login: ENV.fetch("ATREA_USERNAME"),
  password: ENV.fetch("ATREA_PASSWORD"),
  unit_id: ENV.fetch("ATREA_UNIT_IDENT"),
  timeout: 300,
  poll_interval: 1,
  open_timeout: 10,
  read_timeout: 60
)

control = AtreaControl::Duplex::Unit.new(**tokens, time_zone: "Europe/Prague")
values = control.values
values[:current_power] # Numeric configured power value, not universally percent.
values[:current_mode]  # Translated label; may describe a user input such as CO2.
control.refresh!      # Explicitly fetch and validate a new snapshot.
```

`Login.new(...).call` accepts the same keywords. `unit_id:` selects the unit's
`ident`, **not** its portal row ID. Omit it to select the first listed unit.
Returned tokens contain `user_id`, `unit_id` and secret `sid`.

Account authentication and unit-session acquisition are separate stages. Defaults
are `timeout: 300`, `poll_interval: 1`, `open_timeout: 10`, `read_timeout: 60`, in
seconds. The entire login, including authentication, discovery and polling, must
finish within five minutes; shorter `timeout:` values are allowed, larger ones
are rejected. Each HTTP operation has a separate 60-second total limit covering
connection, writing and reading, also bounded by the outer login limit. Both use
Faraday's Net::HTTP adapter and standard-library `Timeout`, without a custom
transport. Server ETA is advisory, not a loop count. Timeout does not establish
that credentials were rejected or the unit is offline.

Ordinary unit requests also have a 60-second total limit, not just a per-read
timeout. `Duplex::Request.new(..., timeout: ...)` accepts shorter total limits;
`open_timeout:` and `read_timeout:` can independently shorten connection/read
waits. The adapter never automatically retries requests.

### Snapshot lifetime and temperature semantics

* First reading fetches one complete snapshot; later getters reuse it without
  implicit network refresh. `refresh!` explicitly replaces it.
* Every current-value getter and serializer checks freshness: timestamp must be
  newer than `now - 900` seconds and no later than `now + 60` seconds. Exactly
  15 minutes old is expired. `valid?` inspects cached state without fetching.
* Failed refresh invalidates current data and preserves the failure until another
  `refresh!`. A write attempt also discards the pre-write snapshot, even when its
  response fails; next reading fetches again. No stale fallback is exposed.
* `values`/`as_json` use symbol keys; `parsed` uses string keys. Readers include
  `power`/`current_power`, `mode`/`current_mode`, `outdoor_temperature`,
  `required_temperature`, `preheat_temperature`, `input_temperature`, `preheating`
  / `preheating?`, and `timestamp`. Temperatures are degrees Celsius.
* `required_temperature` is the requested temperature. Historical
  `preheat_temperature` reader and hash key remain aliases in meaning; both keys
  are present. This is **not** a measured preheater temperature.
* Optional `input_temperature` is `nil` when unavailable or its discovered logic
  is unsupported. It is not fabricated as zero.
* Legacy `preheating` is an aggregate of heating-related signals, not a verified
  dedicated preheater state.
* Optional `time_zone:` accepts an IANA identifier (also on `SensorParser.new`).
  `nil` preserves process-local timestamp interpretation. Set the actual unit's
  zone explicitly to remove deployment-zone ambiguity. Invalid zones and
  ambiguous/nonexistent DST-local timestamps raise `ProtocolError`.
* Device timestamps may omit leading zeroes (for example, `17:7:32`). These are
  normalized while invalid calendar dates and times are still rejected.

Loading the gem registers translations and sets global `I18n.default_locale` to
`:cs`. Sensor/mode maps use string keys. `user_modes` keys are numeric strings,
not input names such as `"D1"`.

### Configuration discovery

`Unit.new` accepts `user_ctrl:` to reuse a `Duplex::UserCtrl` for the **same unit**.
It caches successfully validated layout/text configuration per instance; recreate
it after configuration changes. `UserCtrl.data` exports JSON-safe configuration,
including `input_temperature_source`: `"rd5_standard"` selects the recognized
device source-selection rule; `"unsupported"` keeps inlet temperature unavailable.
Persist this field alongside the sensor/mode maps and expose it when reconstructing
a custom `user_ctrl:` object, such as an ActiveRecord model. Without it, only the
legacy direct sensor mapping can be used. Missing/nil metadata retains that legacy
behavior; explicit unknown metadata returns `nil`, without guessing a sensor.

Custom objects supply `name`, `sensors`, `modes`, `user_modes` and the persisted
`input_temperature_source`. Sensor interpretation stays inside the gem, not the
application UI. Command mappings must include discovered `power_input`, `power_switch`,
`mode_input` and `mode_switch` fields. Derive mappings from the unit's `UserCtrl`,
not fixture addresses. `control.configuration` returns the fresh snapshot's
`Duplex::RD5Configuration` policy (`[]`, `fetch`, `to_h`).

## Power and mode commands

Setter values must be nonnegative integers, finite integral Floats, or ASCII
decimal-digit strings: `88`, `88.0`, `"88"` normalize to 88. `nil`, booleans,
negative/fractional numbers, NaN/infinity, whitespace, signs and `"88.0"` raise
`ArgumentError`. Values are never silently truncated or clamped. Commands also
require a supported configuration and discovered register mapping.

Power semantics follow RD5 `H10510` in the vendor's
[Communication MODBUS — RD5 and aMotion, version 04](https://atrea.eu/_files/documents/modbus-comm-amot-rd5-cz-v04_834.pdf),
section 3.1, page 9:

| `H10510` | Configuration | Accepted power values |
| --- | --- | --- |
| 0 | Direct speed | 0 or integers 12–100 |
| 1 | Constant flow | Integers 0–100 (configured flow scale) |
| 2 | Constant pressure | 0, 1, 2 (levels) |
| 3 | External input | No power writes; `UnsupportedConfiguration` |
| 4 | Multiport | 0, 10–12, 20–22, 30–38 (enumerated settings) |
| Missing/unknown | Unsupported | `UnsupportedConfiguration` |

These are not universal fan-speed percentages or measured airflow. Modes must be
discovered numeric IDs 0–7 and satisfy equipment prerequisites: 0/2 unrestricted;
1/6/7 require `C10508=0`; 3 additionally requires `C10509=1`; 4 additionally
requires `H11700=1`; 5 requires `I11401=1`. Missing prerequisites fail explicitly.
Translated current-mode labels are not command values.

Schedule policy uses the discovered control register: manual 0 sends only the
setpoint; scheduled 1 or temporary 2 sends the setpoint plus temporary control 2,
including for power zero. It does not permanently disable schedules. A temporary
request lasts until the next scheduled interval under the documented RD5 policy.

### Unconfirmed writes

```ruby
response = control.set_power(88, verify: false)
response = control.set_mode(2, verify: false)
control.power = 88
control.mode = 2
```

`verify: false` returns the HTTP response, without application/read-back
confirmation. `power=` and `mode=` delegate with `verify: false`. Ruby assignment
expressions evaluate to their right-hand value, **not** confirmation. HTTP success
alone does not establish that the unit accepted or applied the request. Writes
are never automatically retried.

### Verified writes require an independently proven mapping

`set_power(value, verify: true, timeout: 30, poll_interval: 5)` and `set_mode`
default to verification. **The default configuration has no proven requested-value
read-back profile:** verified calls raise `UnsupportedConfiguration` before writing.
Neither the PDF's current-value fields nor old fixture `idw` fields are selected
automatically.

Only supply `verification_registers:` after independently verifying requested-value
semantics for that exact unit/profile. It accepts a nonempty Hash with symbol keys
`:power` and/or `:mode`, and String values matching `H` plus exactly five digits.
Syntax validation does not establish register semantics. This example deliberately
supplies no literal register address:

```ruby
# These environment values must come from your independently verified profile.
verified_control = AtreaControl::Duplex::Unit.new(
  **tokens,
  time_zone: "Europe/Prague",
  verification_registers: {
    power: ENV.fetch("ATREA_VERIFIED_POWER_REQUEST_REGISTER"),
    mode: ENV.fetch("ATREA_VERIFIED_MODE_REQUEST_REGISTER")
  }
)
confirmed_power = verified_control.set_power(88, timeout: 30, poll_interval: 5)
confirmed_mode = verified_control.set_mode(2, timeout: 30, poll_interval: 5)
```

Verification fetches a fresh baseline, writes once, then polls for the normalized
request in a snapshot **newer than the baseline**. One absolute budget includes
baseline, lazy discovery, dispatch, read-back and sleeps. It confirms a requested
setpoint, not physical airflow, effective mode or override of safety functions.
`WriteNotConfirmed` means outcome unknown after dispatch; do not blindly retry.

## Errors and migration

All library errors inherit `AtreaControl::Error`; invalid caller command inputs
raise standard `ArgumentError`.

| Error | Meaning |
| --- | --- |
| `AuthenticationError` | Portal rejected authentication. |
| `SessionExpired` | Unit HTTP 401/403, or missing/stale/future snapshot timestamp. Freshness failure alone does not prove authentication expired. |
| `ProtocolError` | Malformed/unexpected XML, invalid register/timestamp or DST ambiguity. |
| `TransportError` | Failed HTTP response or connection. |
| `UnitConnectionTimeout` | Transport timeout or exhausted login/verification-baseline budget; subclass of `TransportError`. |
| `UnsupportedConfiguration` | Missing/unsupported configuration, command profile or proven verification mapping. |
| `WriteNotConfirmed` | Verification budget exhausted after dispatch; outcome unknown. |

Migration from 3.2.x: `nil` formerly could become zero; it now raises
`ArgumentError`. Other malformed inputs no longer silently coerce. All cached
getters/serializers can now raise freshness or refresh errors. Handle optional
inlet temperature `nil`, the additional `required_temperature` hash key, strict
configuration/mode validation, and preserved manual schedule control. Explicit
`set_power`/`set_mode` default to verification; existing assignment setters remain
unconfirmed. These changes require a **major-version upgrade** from 3.2.x.

## Protocol reference and development

See [RD5 cloud protocol evidence](docs/rd5-cloud-protocol.md) for supported
declarative discovery forms, fixture/PDF differences and current integration blocker.
The PDF describes **Modbus TCP**, not cloud framing, acknowledgements or rate
limits. Port 502, enabling Modbus and its five-second batch interval are not
prerequisites or established HTTP constraints for this gem.

Run `bin/setup` to install dependencies. `bundle exec rake` runs specs then
RuboCop. CI retains the Ruby spec matrix and runs a separate RuboCop job. Focused
test: `bundle exec rspec spec/atrea_control/duplex/unit_spec.rb`, optionally with
`:LINE`. WebMock/local fixtures need no portal credentials or physical unit.
Use `bin/console` for an interactive prompt.

Gem contents come from `git ls-files`; new runtime files must be tracked before
packaging. `bundle exec rake build` builds locally. Publishing requires a separate
release decision: `bundle exec rake release` pushes commits/tags and publishes to
RubyGems; it is not a verification command.

## Contributing

Bug reports and pull requests are welcome at https://github.com/luk4s/atrea_control.
Participants must follow the [code of conduct](CODE_OF_CONDUCT.md).
