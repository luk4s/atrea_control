# atrea_control
Ventilation systems by https://www.atrea.eu are build with web UI portal - but this portal did not provide any API interface...

This gem provide simple DSL by parsing content of https://control.atrea.eu with selenium webdriver.

## Highlights

* connect to portal, wait for login
* provide basic data
  * temperature
  * fan power
  * power mode
* allow change
  * power
  * mode

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'atrea_control'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install atrea_control

## Usage

At the begin you need obtain `user_id`, `unit_id` and `sid` (auth token). For this use "Login"
```ruby
tokens = AtreaControl::Duplex::Login.user_tokens login: "myhome", password: "sup3r-S3CR3T-kocicka"
tokens # => { user_id: "1234", unit_id: "85425324672", sid: 4012 }
```
I recommend to store then somewhere... 
Then you can call Unit for data...

Example usage:
```ruby
control = AtreaControl::Duplex::Unit.new user_id: "1234", unit_id: "85425324672", sid: 4012
control.values # => { current_power: 88.0, current_mode: "CO2" }
control.power # => 88.0 
```
### Dig deeper
`AtreaControl::Duplex::Unit` expect optional argument `user_ctrl` which should be object respond to 

`name` (String) = Name of unit
`sensors` (Hash) = Map of sensors, for example: `{ outdoor_temperature: "HI10208", current_power: "H10704" }`
`modes` (Hash) = Is a map of "changable" modes - in unit its something like "builtin?" modes. They are translated by unit lang - `{ "0" => "Vypnuto", "1" => "Automat" }` 
`user_modes` (Hash) = Is a map user specific modes, based on home switches / devices (D1, D2, D3, IN1, IN2 ...). They are translated by user texts - `{ "D1" => "Koupelna", "D2" => "CO2", "IN1" => "ovladač" }`

__Please check [lib/atrea_control/duplex/user_ctrl.rb](./lib/atrea_control/duplex/user_ctrl.rb) for more details !__

## Development / TODO
Login is currently done by selenium - fill login form. 
I found that Atrea submit form to BE, generate some "empty" HTML and JS which onLoad start doing request to queue for "login".

Re-login user, add login procedure into queue:
```bash
curl -X POST -d "comm=config%2Flogin.cgi" "https://control.atrea.eu/apps/rd5Control/handle.php?action=unitLogin&user=XXXX&unit=NNNNNNN&table=userUnits&idPwd=YYYYYYY&NFP"
```
Response is time in seconds when login will ready:
```xml
<root><sended time="264"/></root>
```
Based it su shown countdown ...


Request for current queue status
```bash
curl 'https://control.atrea.eu/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=XXXX&unit=NNNNNNN'
```
if queue is processed:
```xml
<root><login uconn="16395889" sid="010101" ver="3001009"/></root>
```
else
```xml
<root><login uconn="16390480" sid="0"/></root>
```

Goal is to obtain "SID".

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/luk4s/atrea_control. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/luk4s/atrea_control/blob/master/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the AtreaControl project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/luk4s/atrea_control/blob/master/CODE_OF_CONDUCT.md).
