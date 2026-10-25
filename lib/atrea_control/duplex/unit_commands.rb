# frozen_string_literal: true

require_relative "write_verification"

module AtreaControl
  module Duplex
    # RD5 command dispatch and opt-in requested-value verification for Unit.
    module UnitCommands
      %i[mode power].each do |setting|
        define_method(:"#{setting}=") { |value| public_send(:"set_#{setting}", value, verify: false) }
        define_method(:"set_#{setting}") do |value, verify: true, timeout: 30, poll_interval: 5|
          normalized = RD5Command.normalize(value)
          verification = WriteVerification.new(timeout: timeout, poll_interval: poll_interval)
          next command(setting, normalized) unless verify

          verification.run { verified_command(setting, normalized, verification) }
        end
      end

      private

      def verified_command(setting, normalized, verification)
        register = @verification_registers&.fetch(setting, nil)
        raise AtreaControl::UnsupportedConfiguration, "No verified readback mapping for #{setting}" unless register

        @snapshot_error = nil
        load_snapshot
        verification.remaining
        baseline = @snapshot.fetch("timestamp")
        raise AtreaControl::UnsupportedConfiguration, "Missing baseline readback register #{register}" unless @registers.key?(register)

        commands = RD5Command.new(configuration, @user_ctrl, parser).build(setting, normalized)
        verification.dispatch { write(*commands) }
        verification.confirm do
          load_snapshot
          raw = @registers.fetch(register) { raise AtreaControl::ProtocolError, "Missing readback register #{register}" }
          @snapshot.fetch("timestamp") > baseline && raw == normalized
        end
        normalized
      end

      def command(setting, normalized)
        commands = RD5Command.new(configuration, @user_ctrl, parser).build(setting, normalized)
        write(*commands)
      end

      # @param [Array<String>] values in format SENSOR0000VALUE
      def write(*values)
        inputs = values.to_h { |i| [i, nil] }
        logger.debug("set RD5 #{inputs}")
        # The device may apply a command even if its response fails or times out.
        # Discard prewrite data on every attempt; the next reader must fetch again.
        @snapshot = @configuration = @registers = @snapshot_error = nil
        params = { _t: "config/xml.cgi", _w: 1 }.merge(inputs)
        request.call(params)
      end
    end
  end
end
