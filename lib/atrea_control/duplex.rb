# frozen_string_literal: true

module AtreaControl
  # Controller for +control.atrea.eu+
  module Duplex
    CONTROL_URI = "https://control.atrea.eu/"
    CONTROL_VERSION = "003001022"

    autoload :Login, "atrea_control/duplex/login"
    autoload :Request, "atrea_control/duplex/request"
    autoload :RD5Configuration, "atrea_control/duplex/rd5_configuration"
    autoload :RD5Command, "atrea_control/duplex/rd5_command"
    autoload :Unit, "atrea_control/duplex/unit"
    autoload :UserCtrl, "atrea_control/duplex/user_ctrl"
  end
end
