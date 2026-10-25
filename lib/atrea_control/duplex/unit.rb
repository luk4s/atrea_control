# frozen_string_literal: true

require "json"
require_relative "unit_commands"

module AtreaControl
  module Duplex
    # Communication with RD5 unit (read/write)
    class Unit
      include AtreaControl::Logger
      include UnitCommands

      CURRENT_FIELDS = %w[current_mode current_power outdoor_temperature preheat_temperature required_temperature input_temperature preheating timestamp].freeze

      CURRENT_FIELDS.each do |field|
        define_method(field) { parsed[field] }
      end
      # @return [UserCtrl]
      attr_reader :user_ctrl

      # @param [String, Integer] user_id
      # @param [String, Integer] unit_id
      # @param [String, Integer] sid
      # @param [AtreaControl::Duplex::UserCtrl] user_ctrl
      def initialize(user_id:, unit_id:, sid:, user_ctrl: nil, time_zone: nil, verification_registers: nil) # rubocop:disable Metrics/ParameterLists
        @user_id = user_id
        @unit_id = unit_id
        @sid = sid
        @time_zone = time_zone
        @verification_registers = WriteVerification.registers(verification_registers)
        @user_ctrl = user_ctrl || UserCtrl.new(user_id: user_id, unit_id: unit_id, sid: sid)
      end

      def name
        @user_ctrl.name
      end

      def mode
        current_mode
      end

      def power
        current_power
      end

      # Preserve the writer for loaded, valid snapshots without sharing mutable Time objects.
      def timestamp=(value)
        candidate = parsed.merge("timestamp" => value.dup.freeze).freeze
        raise AtreaControl::SessionExpired unless valid?(candidate)

        @snapshot = candidate
      end

      def preheating?
        preheating
      end

      def parsed
        raise @snapshot_error if @snapshot_error

        load_snapshot unless @snapshot
        raise AtreaControl::SessionExpired unless valid?

        @snapshot
      end

      def values
        parsed.transform_keys(&:to_sym)
      end

      # Configuration belongs to the same fresh snapshot as parsed readings.
      def configuration
        parsed && @configuration
      end

      def as_json(_options = nil)
        values
      end

      def to_json(*)
        values.to_json(*)
      end

      # Expire cached data and fetch them again
      # @return [Hash] new values
      def refresh!
        @snapshot_error = nil
        load_snapshot
        values
      end

      # Inspect the snapshot directly: no lazy fetch and no timestamp-reader recursion.
      def valid?(snapshot = @snapshot)
        timestamp = snapshot && snapshot["timestamp"]
        return false unless timestamp.is_a?(Time)

        now = Time.now
        timestamp > now - 900 && timestamp <= now + 60
      end

      private

      # Publish only a complete, fresh snapshot. A failed attempt stays failed until refresh!.
      def load_snapshot
        @snapshot = nil
        @configuration = nil
        @registers = nil
        bundle = parser.snapshot(read.body)
        candidate = bundle.fetch(:values).transform_values { |value| value.dup.freeze }.freeze
        raise AtreaControl::SessionExpired unless valid?(candidate)

        @configuration = bundle.fetch(:configuration)
        @registers = bundle[:registers]
        @snapshot = candidate
      rescue StandardError => e
        @snapshot_error = e
        raise
      end

      # Additional "parameters" for each sensor
      # @note it's changed in time ?
      def params
        response = request.call(_t: "user/params.xml")
        Nokogiri::XML response.body
      end

      def parser
        @parser ||= ::AtreaControl::SensorParser.new(@user_ctrl, time_zone: @time_zone)
      end

      # Request to RD5
      def request
        @request ||= Request.new(user_id: @user_id, unit_id: @unit_id, sid: @sid)
      end

      def read
        request.call(_t: "config/xml.xml")
      end
    end
  end
end
