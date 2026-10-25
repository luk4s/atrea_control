# RD5 cloud protocol: evidence and supported profiles

This client intentionally targets RD5 cloud HTTP/XML only. It is neither aMotion
Cloud nor a Modbus TCP implementation. Local fixture coverage establishes parser
and policy behavior, not current firmware compatibility.

## Evidence ledger

1. **Older portal fixtures:** `spec/fixtures/files/userCtrl.xml` and `unit.xml`,
   plus login response fixtures. These support declarative layout discovery and
   register parsing. The unit fixture timestamp is historical, not a live sample.
2. **Vendor PDF:** *Communication MODBUS — RD5 and aMotion*, version 04, cover
   issue `2025_04_25`, sections 2.3.1 and 3.1 (especially pages 9–13),
   [public source](https://atrea.eu/_files/documents/modbus-comm-amot-rd5-cz-v04_834.pdf).
   The contents page has a different issue date; use version and cover issue as
   identity. It establishes RD5 register semantics, not cloud framing, login,
   acknowledgements or HTTP rate limits. Modbus's five-second batch interval is
   not evidence of a cloud HTTP limit.
3. **Initial read-only audits:** account authentication and unit-record discovery
   succeeded. Advertised package
   `3001022`, normalized with leading zeroes, matches `CONTROL_VERSION`
   `003001022`. SID remained zero. The full 360-second budget ended exactly with
   `AtreaControl::UnitConnectionTimeout`, `stage=session_query`.

4. **Successful live audit on 2026-10-25, after production client shutdown:** the
   unmodified handshake still timed out. Unit metadata reported a server contact
   about 101 seconds earlier, so zero SID alone did not establish disconnection.
   Inspection of current portal source identified a missing `Sync=1` on the
   unit-login POST. Adding only this parameter obtained a SID in about 127 seconds
   and allowed valid reads. After applying the fix, a separate public-API run
   logged in in 5.86 seconds, read values/configuration, serialized getters/JSON,
   and completed three refreshes with advancing timestamps and data roughly five
   seconds old. Another run checked the unit-name reader, constructed power/mode
   commands from the actual configuration without sending them, rejected an aged
   live snapshot under a process-local controlled clock, and recovered via refresh.
   The rebuilt `pkg/atrea_control-3.2.1.gem` was then unpacked outside the workspace
   and used for another real login (5.9 seconds), valid read and successful refresh;
   this checked the packaged runtime, not only the working-tree source.
5. **Faraday-only follow-up:** after removing the extra transport, live login
   completed in 1.45 seconds. Both Login and Request used `Faraday::Adapter::NetHttp`;
   HTTPX was not loaded. Values and refresh passed, with refreshed data roughly
   five seconds old. This audit also exposed unpadded timestamp components
   (`2026-10-25 17:7:32 `); the parser now accepts those valid fields after
   normalization. No control writes were dispatched.

**Remaining integration boundary:** current login, configuration discovery and
reads are proven for this unit/package. Cloud acknowledgement shape, actual
writes and requested-value read-back semantics are not. No live control writes
were run; those need separate agreement. No credentials, account names, unit
identifiers or SID values are retained here.

## Cloud sequence implemented

`Login` posts credentials to the portal (`?action=login`), accepts its expected
302, requires the session cookie, obtains a client ID from `core/core.php`, lists
`userUnits`, and resolves the `units` record to its `ident`. Explicit `unit_id:`
matches that ident through the account list; otherwise the first unit is selected.

`apps/rd5Control/handle.php` with `action=unitQuery`, `query=loged` returns a
`/root/login` SID. A zero SID triggers `Sync=1&action=unitLogin` with the unit's
account row reference and `comm=config/login.cgi?magic=`, requiring `/root/sended`, then
polling the session query. Server wait estimates do not shorten or extend the
absolute budget. A nonempty, nonzero SID is required for success. No browser
application-launch request is needed in the verified library sequence.

The current portal's `core/start.js` shared `sendSync` implementation prepends
`Sync=1` to its requests. The RD5 app's `setUnit` function, returned by
`core/core.php?action=run&object=app`, invokes that synchronous helper for
`unitLogin`. This source comparison, followed by live success, supports the
parameter fix without executing downloaded application code in the gem. A
`/root/sended` response alone had not proved successful session establishment.

`Request` sends unit requests through `comm/sw/unit.php` with authentication and
version parameters. These parameters are secret-bearing: do not retain full URLs.
Targets include:

| Target | Purpose |
| --- | --- |
| `lang/userCtrl.xml`, `_async=1` | Layout and declarative discovery |
| `config/texts.xml` | User-defined labels |
| `config/xml.xml` | Register snapshot |
| `config/xml.cgi`, `_w=1` | Command request |

No cloud application ACK shape has been proven. A successful HTTP response is
transport success only, including on an unconfirmed write. The client never
automatically retries a write whose outcome may already be unknown.

Login's default and maximum total limit is 300 seconds; polling is one second.
Every HTTP operation has a separate 60-second total limit, including connection,
write and response read. The outer login timer can stop a request earlier.
Default connect/read waits are 10/60 seconds; shorter overrides are supported.
Faraday's stock Net::HTTP adapter is the sole transport and disables retries.
Standard-library `Timeout.timeout` wrappers use explicit `StandardError`-derived
exception classes to preserve Net::HTTP's TLS-connect cleanup. No custom socket,
resolver or transport plugin is needed. Verification keeps its own aggregate
30-second default limit, including lazy configuration discovery and read-back.
The earlier 360-second audit timings above predate this simplification.

## Snapshot and raw register interpretation

Snapshots require strict XML with `/RD5WEB/RD5`, no DTD and a valid root `t`
timestamp: a four-digit year and one- or two-digit month/day/hour/minute/second
fields (`YYYY-M-D H:M:S` or zero-padded equivalents), allowing surrounding
whitespace. Fields are normalized before strict calendar/timezone validation.
Registers are `/RD5WEB/RD5/*/O` elements with
`I` identifiers and decimal `V` values in 0–65535. Last occurrence wins for a
duplicate identifier. Missing required mapped readings, malformed numbers and
unexpected XML fail explicitly; no partial snapshot is published.

`SensorParser#raw_values` preserves unsigned integers. Temperature projection
alone applies signed 16-bit conversion then tenths-of-degree scaling: 65535 is
−0.1 °C, 65036 is −50.0 °C. A high configuration value stays unsigned.
`RD5Configuration` consumes the same raw snapshot without changing service
configuration. `Unit` checks freshness at every getter/serialization, publishes
atomically and invalidates on failed refresh or any attempted write.

## Declarative discovery: fixture profile confirmed on the live unit

`UserCtrl` looks up `/root/layout/body/content/i` by title, rather than treating
fixture IDs as universal:

| Title | Discovery |
| --- | --- |
| `$outdoorTemp` | `id` for outdoor temperature |
| `$requiredTemp` | `id` for requested temperature, both public alias names |
| `$inletTemp` | Optional `id` and recognized `displayval` logic |
| `$currentPower` | `id` for current power; `onchange` for input/control fields |
| `$currentMode` | `id` for current mode; `displayval` reference for user-input selector; `onchange` for input/control fields |

`Mode` and `ModeText` option lists define numeric-string-keyed labels; translated
labels never replace numeric command IDs. Successful layout/text discovery is
cached per `UserCtrl` instance. Unknown command scripts raise
`UnsupportedConfiguration`; downloaded JavaScript is never evaluated.

`RD5Command.discover` accepts this **complete** function shape, with whitespace
between tokens and register IDs matching `H` plus five decimal digits:

```javascript
function(val) {
  saved=true;
  send2Unit(getUrlPar('INPUT',val)+(values.SWITCH==1?'&'+getUrlPar('SWITCH',2):''));
}
```

`INPUT` and `SWITCH` above are notation, not literal accepted IDs. Both `SWITCH`
references must be identical. Actual older fixture forms are:

```javascript
function(val) {
  saved=true;
  send2Unit(getUrlPar('H10708',val)+(values.H10700==1?'&'+getUrlPar('H10700',2):''));
  if(val>0 && values.H10715==0) {
    flyDown=false;
    this.nextSibling.nextSibling.onmousedown();
  }
}
function(val) {
  saved=true;
  send2Unit(getUrlPar('H10709',val)+(values.H10701==1?'&'+getUrlPar('H10701',2):''));
}
```

The power-only UI tail is optional, but if present must match that specific
recognized form; arbitrary extra statements are unsupported. Input/control IDs
can differ when the complete supported form matches. The resulting string-keyed
maps contain `power_input`, `power_switch`, `mode_input`, `mode_switch`.

The successful live run discovered outdoor `I10208`, requested temperature
`H10706`, current power/mode `H10704`/`H10705`, selector `H10712`, power
input/switch `H10708`/`H10700`, and mode input/switch `H10709`/`H10701`.
Observed configuration included direct-speed control `H10510=0`, orientation
`H10501=1`, inlet profile `H11300=0`, `C10508=0`, `I11401=0`, and scheduled
power/mode control states of 1. These observations establish this unit's profile,
not universal addresses or behavior for every RD5 firmware.

Commands concatenate a discovered holding-register ID and exactly five decimal
digits (e.g. the older fixture's `H10708` plus 88 becomes `H1070800088`). One
write request carries the setpoint and, when needed, its control switch. Unlike
the UI's conditional, library policy treats **both** scheduled 1 and temporary 2
as temporary-control writes; manual 0 stays manual. Zero power follows the same
policy. Unknown/missing control state fails before dispatch. Permanent schedule
disable is outside these setters.

## Temperature profile and heating limitations

Supported inlet logic is `RD5Configuration::INLET_SOURCE_RULE`, matched as a complete
declarative form after whitespace removal:

* `H11300=0`, `H10501=1`: use `I10200` only when `H10200>0` and temperature is
  not 126.0 °C (unsigned raw sentinel 1260).
* `H11300=0`, `H10501=2`: use `I10201` only when `H10201>0` and not sentinel.
* `H11300=1`: use `I10204` if present.
* Missing required optional sensor, stopped fan, other configuration or unknown
  inlet script: return `nil`, without inventing a reading.

`UserCtrl.data` exports `input_temperature_source` as a JSON-safe string:
`"rd5_standard"` for the recognized rule, `"unsupported"` otherwise. Applications
that persist this data must also expose that field on reconstructed `user_ctrl:`
objects. The field selects device interpretation, not UI presentation; M1/M2/direct
selection continues to use the current raw snapshot inside the gem.

Legacy custom objects without `input_temperature_source` (or with nil metadata)
can supply a direct inlet mapping; callers own its correctness. Explicit unknown
metadata keeps the optional reading unavailable. Refresh previously cached metadata
on upgrade rather than interpreting the new map as a legacy direct source.
Outdoor mapping always comes
from `UserCtrl`: old fixture uses `I10208`, whereas PDF page 11 calls `I10211`
T-ODA. No blanket substitution is justified.

PDF `H10706` means requested temperature, not measured preheater temperature.
`required_temperature` and retained `preheat_temperature` reader/hash key expose
that same reading. Legacy `preheating` ORs `C10200`, `C10202`, `C10215`, `C10217`
when equal to 1. PDF descriptions include water-heater pump/heat-pump signals;
this aggregate does not establish dedicated preheater operation. No replacement
mapping has been fabricated.

## Requested versus effective values and verification

The PDF lists power/mode read fields `H10704`/`H10705` and write inputs
`H10708`/`H10709`. Older layout fixtures separately label `idw=H10714`/`H10715`
as requested power/mode while `id` fields are current readings. This difference
is unresolved for current firmware. Neither pair is automatically chosen as a
proven cloud requested-value read-back profile.

Verified `Unit#set_power` / `set_mode` default to `verify: true`, timeout 30
seconds and polling every five seconds. Without an explicit proven mapping they
raise `UnsupportedConfiguration` **before writing**. Trusted callers may provide
`Unit.new(..., verification_registers: mapping)` after independently establishing
semantics for the exact unit/profile. Mapping is a nonempty Hash with only symbol
keys `:power` and/or `:mode`, each mapped to a String matching `\AH[0-9]{5}\z`.
Validation checks syntax, not truth of the caller's profile.

Verification loads a fresh baseline containing the mapped raw register, builds
and sends one command, and polls fresh snapshots until the timestamp is strictly
newer than baseline and the raw requested value equals the normalized command.
A stale matching value cannot confirm. Budget includes all baseline/discovery,
HTTP, dispatch and sleep work. Baseline deadline failure raises
`UnitConnectionTimeout`; verification timeout after dispatch raises
`WriteNotConfirmed` with unknown outcome. Confirmation would establish a requested
setpoint only, not effective operation or physical airflow. No current live ACK
or read-back profile has been captured.

## Remaining integration acceptance

* Establish requested-value mappings and any application ACK from actual evidence.
* Only with separate agreement, test one ordinary write and restore both original
  setpoint and original manual/scheduled/temporary control state. Do not alter
  service configuration.

These remain hardware/protocol acceptance items, independent of fixture-suite
success. Temperature/zone setters, alarms, flow telemetry, external temperature
injection and Modbus transport remain deferred. External temperature injection's
90-second refresh rule must not be applied to ordinary power/mode requests.
