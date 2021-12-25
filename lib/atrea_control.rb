# frozen_string_literal: true

require_relative "atrea_control/version"
require "i18n"
require "yaml"

module AtreaControl
  class Error < StandardError; end

  autoload :Duplex, "atrea_control/duplex"
  autoload :Logger, "atrea_control/logger"
  autoload :SensorParser, "atrea_control/sensor_parser"

  I18n.load_path.concat Dir["#{File.expand_path("../config/locales", __dir__)}/*.yml"]
  I18n.default_locale = :cs

end
