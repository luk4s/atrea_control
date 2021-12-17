# frozen_string_literal: true

require_relative "atrea_control/version"
require "i18n"
require "yaml"

module AtreaControl
  class Error < StandardError; end

  autoload :Duplex, "atrea_control/duplex"
  autoload :DuplexValues, "atrea_control/duplex_values"

  I18n.load_path.concat Dir["#{File.expand_path("../config/locales", __dir__)}/*.yml"]
  I18n.default_locale = :cs

  # Provide map sensor to element ID
  module Config
    module_function

    def default_sensors_map
      {
        outdoor_temperature: "I10208",
        current_power: "H10704",
        current_mode: "H10705",
        current_mode_switch: "H10712",
      }
    end
  end
end
