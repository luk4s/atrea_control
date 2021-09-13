# atrea_control
Ventilation systems by https://www.atrea.eu are build with web UI portal - but this portal did not provide any API interface...

This gem provide simple DSL by parsing content of https://control.atrea.eu with selenium webdriver.

## Highlights

* connect to portal, wait for login
* provide basic data
  * temperature
  * fan power
  * power mode


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

UI map of sensors is required = each box have own ID contains sensor ID. Its required for correct element lookup.

Default sensor map:
```ruby
def default_sensors_map
  {
    outdoor_temperature: "I10208",
    current_power: "H10704",
    current_mode: "H10705",
  }
end
```
Example usage:
```ruby
control = AtreaControl::Duplex.new login: "myhome", password: "sup3r-S3CR3T-kocicka", sensors_map: { current_power: "H10704" }
control.login # => true (takes max 5.minutes)
control.current_mode # => "Bathroom"
control.current_power # => 37.0
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/atrea_control. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/luk4s/atrea_control/blob/master/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the AtreaControl project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/luk4s/atrea_control/blob/master/CODE_OF_CONDUCT.md).
