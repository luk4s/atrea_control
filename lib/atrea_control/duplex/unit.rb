# frozen_string_literal: true

module AtreaControl
  module Duplex
    # Communication with RD5 unit (read/write)
    class Unit
      include AtreaControl::Logger

      attr_reader :current_mode, :current_power, :outdoor_temperature
      # @return [DateTime] store time of last update
      attr_reader :valid_for
      # @return [UserCtrl]
      attr_reader :user_ctrl

      # @param [String, Integer] user_id
      # @param [String, Integer] unit_id
      # @param [String, Integer] sid
      # @param [AtreaControl::Duplex::UserCtrl] user_ctrl
      def initialize(user_id:, unit_id:, sid:, user_ctrl: nil)
        @user_id = user_id
        @unit_id = unit_id
        @sid = sid
        @user_ctrl = user_ctrl || UserCtrl.new(user_id: user_id, unit_id: unit_id, sid: sid)
      end

      def name
        @user_ctrl.name
      end

      def mode
        current_mode || values[:current_mode]
      end

      def power
        current_power || values[:current_power]
      end

      # @param [String] value 0 - power-off; 1 - automat
      def mode=(value)
        v = parser.input(@user_ctrl.sensors["mode_input"], value.to_s)
        write(v)
      end

      def power=(value)
        v = [parser.input(@user_ctrl.sensors["power_input"], value.to_s)]
        v << parser.input(@user_ctrl.sensors["mode_switch"], "2")
        write(v)
      end

      def values
        parser.values(read.body).each do |name, value|
          instance_variable_set :"@#{name}", value
        end
        as_json
      end

      def as_json(_options = nil)
        {
          current_mode: current_mode,
          current_power: current_power,
          outdoor_temperature: outdoor_temperature,
          valid_for: valid_for,
        }
      end

      def to_json(*args)
        values.to_json(*args)
      end

      private

      def parser
        @parser ||= ::AtreaControl::SensorParser.new(@user_ctrl)
      end

      # Request to RD5
      def request
        @request ||= Request.new(user_id: @user_id, unit_id: @unit_id, sid: @sid)
      end

      def read
        request.call(_t: "config/xml.xml")
      end

      # @param [Array<String>] values in format SENSOR0000VALUE
      def write(*values)
        inputs = values.to_h { |i| [i, nil] }
        logger.debug("set RD5 #{inputs.keys}")
        request.call({ _t: "config/xml.cgi", _w: 1 }.merge(inputs))
      end
    end
  end
end
