# frozen_string_literal: true

require_relative "atrea_control/version"

module AtreaControl
  class Error < StandardError; end

  autoload :Duplex, "atrea_control/duplex"

  # Provide map sensor to element ID
  module Config
    module_function

    def default_sensors_map
      {
        outdoor_temperature: "I10208",
        current_power: "H10704",
        current_mode: "H10705",
      }
    end
  end
end
