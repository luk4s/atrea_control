# frozen_string_literal: true

module AtreaControl
  module Duplex
    # Build one coherent command from discovered mappings and one fresh configuration.
    class RD5Command
      COMMAND_PROFILE = /
        send2Unit \s* \( \s* getUrlPar \s* \( \s* '(?<input>H[0-9]{5})' \s* , \s* val \s* \)
        \s* \+ \s* \( \s* values \s* \. \s* (?<switch>H[0-9]{5}) \s* == \s* 1 \s* \?
        \s* '&' \s* \+ \s* getUrlPar \s* \( \s* '\k<switch>' \s* , \s* 2 \s* \)
        \s* : \s* '' \s* \) \s* \) \s* ; \s*
      /x
      POWER_UI_TAIL = /
        (?: if \s* \( \s* val \s* > \s* 0 \s* && \s* values \s* \. \s* H10715 \s* == \s* 0 \s* \) \s* \{
          \s* flyDown \s* = \s* false \s* ; \s* this \s* \. \s* nextSibling \s* \. \s* nextSibling
          \s* \. \s* onmousedown \s* \( \s* \) \s* ; \s* \} \s*
        )?
      /x

      def self.normalize(value)
        integer = case value
                  when Integer then value
                  when Float then integral_float(value)
                  when String then Integer(value, 10) if value.match?(/\A[0-9]+\z/)
                  end
        raise ArgumentError, "Expected nonnegative integral command value" unless integer && integer >= 0

        integer
      end

      def self.integral_float(value)
        value.to_i if value.finite? && value == value.to_i
      end
      private_class_method :integral_float

      def self.encode(sensor, value)
        raise AtreaControl::UnsupportedConfiguration, "Invalid holding-register mapping" unless sensor.is_a?(String) && sensor.match?(/\AH[0-9]{5}\z/)
        raise ArgumentError, "Expected unsigned 16-bit integer" unless value.is_a?(Integer) && (0..65_535).cover?(value)

        sensor + format("%05d", value)
      end

      # Only supported, complete onchange forms; never execute or extract arbitrary JS.
      def self.discover(source, power: false)
        # Whitespace is allowed between tokens, never inside identifiers or quoted IDs.
        tail = power ? POWER_UI_TAIL : //
        match = source.match(/\A\s*function\s*\(\s*val\s*\)\s*\{\s*saved\s*=\s*true\s*;\s*#{COMMAND_PROFILE}#{tail}\}\s*\z/)
        raise AtreaControl::UnsupportedConfiguration, "Unsupported command profile" unless match

        { input: match[:input], switch: match[:switch] }
      end

      def initialize(configuration, user_ctrl, parser)
        @configuration = configuration
        @user_ctrl = user_ctrl
        @parser = parser
      end

      def build(setting, value)
        case setting
        when :power then @configuration.validate_power!(value)
        when :mode then @configuration.validate_mode!(value, @user_ctrl.modes)
        else raise ArgumentError, "Unknown command setting"
        end
        input = @parser.input(@user_ctrl.sensors["#{setting}_input"], value)
        switch = @user_ctrl.sensors["#{setting}_switch"]
        override = @parser.input(switch, 2)
        @configuration.temporary_control?(switch) ? [input, override] : [input]
      end
    end
  end
end
