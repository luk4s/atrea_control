# frozen_string_literal: true

module AtreaControl
  module Duplex
    # Communication with RD5 unit (read/write)
    class Unit
      include AtreaControl::Logger

      attr_reader :current_mode, :current_power, :outdoor_temperature, :preheat_temperature, :input_temperature
      # @return [Boolean] preheating air is ON ?
      attr_reader :preheating
      # @return [UserCtrl]
      attr_reader :user_ctrl
      # @return [Time, DateTime]
      attr_writer :timestamp

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

      def timestamp
        @timestamp ||= values[:timestamp]
      end

      def preheating?
        preheating || values[:preheating]
      end

      # @param [String] value 0 - power-off; 1 - automat
      def mode=(value)
        v = [parser.input(@user_ctrl.sensors["mode_input"], value.to_s)]
        v << parser.input(@user_ctrl.sensors["mode_switch"], "2")
        write(*v)
      end

      def power=(value)
        v = [parser.input(@user_ctrl.sensors["power_input"], value.to_s)]
        # overtake schedule control
        v << "H1070000002" if value.to_i.positive?
        write(*v)
      end

      def parsed
        @parsed ||= parser.values(read.body)
      end

      def values
        parsed.each do |name, value|
          instance_variable_set :"@#{name}", value
        end
        raise AtreaControl::SessionExpired unless valid?

        as_json
      end

      def as_json(_options = nil)
        {
          current_mode: current_mode,
          current_power: current_power,
          outdoor_temperature: outdoor_temperature,
          preheat_temperature: preheat_temperature,
          input_temperature: input_temperature,
          preheating: preheating,
          timestamp: timestamp,
        }
      end

      def to_json(*)
        values.to_json(*)
      end

      # Expire cached data and fetch them again
      # @return [Hash] new values
      def refresh!
        remove_instance_variable(:@parsed) if defined?(@parsed)
        values
      end

      # Data are valid if timestamp within 15.minutes
      def valid?
        return false unless timestamp

        timestamp > (Time.now - (15 * 60.0))
      end

      private

      # Additional "parameters" for each sensor
      # @note it's changed in time ?
      def params
        response = request.call(_t: "user/params.xml")
        Nokogiri::XML response.body
      end

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
        logger.debug("set RD5 #{inputs}")
        request.call({ _t: "config/xml.cgi", _w: 1 }.merge(inputs))
      end
    end
  end
end
