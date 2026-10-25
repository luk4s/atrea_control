# frozen_string_literal: true

require "timeout"

module AtreaControl
  module Duplex
    # One monotonic budget, with an explicitly unknown outcome after command dispatch.
    class WriteVerification
      def self.registers(mapping)
        return nil if mapping.nil?

        valid = mapping.is_a?(Hash) && !mapping.empty? && mapping.all? { |key, id| valid_register?(key, id) }
        raise ArgumentError, "Expected verification register map with power/mode symbol keys and H plus five digits" unless valid

        mapping.transform_values { |id| id.dup.freeze }.freeze
      end

      def self.valid_register?(key, id)
        %i[power mode].include?(key) && id.is_a?(String) && id.match?(/\AH[0-9]{5}\z/)
      end
      private_class_method :valid_register?

      def initialize(timeout:, poll_interval:)
        { timeout: timeout, poll_interval: poll_interval }.each do |key, value|
          raise ArgumentError, "#{key} must be positive and finite" unless value.is_a?(Numeric) && value.real? && value.finite? && value.positive?
        end
        @deadline = monotonic_time + timeout
        @poll_interval = poll_interval
      end

      def remaining
        budget = @deadline - monotonic_time
        return budget if budget.positive?

        timeout!
      end

      def run(&)
        Timeout.timeout(remaining, AtreaControl::UnitConnectionTimeout, "Write verification timed out", &)
      rescue Timeout::Error, AtreaControl::UnitConnectionTimeout
        timeout!
      end

      def dispatch
        remaining
        @attempted = true
        yield
        remaining
      end

      def confirm
        loop do
          remaining
          matched = yield
          remaining
          return if matched

          Kernel.sleep([@poll_interval, remaining].min)
        end
      end

      private

      def timeout!
        raise AtreaControl::WriteNotConfirmed, "Write not confirmed; outcome unknown", cause: nil if @attempted

        raise AtreaControl::UnitConnectionTimeout, "Write verification baseline timed out", cause: nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
