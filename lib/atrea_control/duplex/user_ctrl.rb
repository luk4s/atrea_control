# frozen_string_literal: true

require "nokogiri"

module AtreaControl
  module Duplex
    # Parse `userCtrl.xml`
    class UserCtrl # rubocop:disable Metrics/ClassLength
      # @param (see #initialize)
      def self.data(user_id:, unit_id:, sid:)
        user_ctrl = new(user_id: user_id, unit_id: unit_id, sid: sid)
        {
          name: user_ctrl.name,
          sensors: user_ctrl.sensors,
          modes: user_ctrl.modes,
          user_modes: user_ctrl.user_modes,
          input_temperature_source: user_ctrl.input_temperature_source,
        }
      end

      # @param [String, Integer] user_id
      # @param [String, Integer] unit_id
      # @param [String, Integer] sid
      def initialize(user_id:, unit_id:, sid:)
        @user_id = user_id
        @unit_id = unit_id
        @sid = sid
      end

      # Request to RD5
      def request
        @request ||= Request.new(user_id: @user_id, unit_id: @unit_id, sid: @sid)
      end

      # Get and parse XML with user/unit configuration source
      def user_ctrl
        return @user_ctrl if @user_ctrl

        response = read(_t: "lang/userCtrl.xml", _async: 1)
        xml = parse_xml(response.body)
        raise AtreaControl::ProtocolError, "Expected userCtrl layout XML" unless xml.at_xpath("/root/layout/body")

        @user_ctrl = xml
      end

      # User-defined name of home (RD5 unit)
      # @return [String]
      def name
        @name ||= user_texts["UnitName"]
      end

      # Gather ID of sensors based on userCtrl config file
      def sensors
        return @sensors if @sensors

        power = sensor_node("$currentPower")
        mode = sensor_node("$currentMode")
        power_command = RD5Command.discover(power.xpath("onchange").text, power: true)
        mode_command = RD5Command.discover(mode.xpath("onchange").text)
        @sensors = {
          "outdoor_temperature" => sensor_node("$outdoorTemp")["id"],
          "preheat_temperature" => sensor_node("$requiredTemp")["id"],
          "input_temperature" => sensor_node("$inletTemp", optional: true)&.[]("id"),
          "current_power" => power["id"],
          "current_mode" => mode["id"],
          "current_mode_switch" => mode.xpath("displayval").text[/values\.(\w+)/, 1], # "H10712"
          **power_command.transform_keys { |key| "power_#{key}" },
          **mode_command.transform_keys { |key| "mode_#{key}" },
        }.tap { |mappings| validate_sensors(mappings) }
      end

      # Persist the source-resolution rule with mappings, not the downloaded JavaScript.
      def input_temperature_source
        @input_temperature_source ||= RD5Configuration.input_temperature_source(user_ctrl.xpath("/root/layout/body/content/i[@title='$inletTemp']/displayval").text)
      end

      # Generic modes
      # @return [Hash]
      def modes
        @modes ||= mode_map("Mode")
      end

      # Modes by inputs - switches - named by user custom texts
      # @return [Hash]
      def user_modes
        @user_modes ||= mode_map("ModeText")
      end

      private

      def read(params)
        request.call(**params)
      end

      def sensor_node(title, optional: false)
        user_ctrl.at_xpath("/root/layout/body/content/i[@title='#{title}']") ||
          (raise(AtreaControl::UnsupportedConfiguration, "Missing sensor #{title}") unless optional)
      end

      def validate_sensors(mappings)
        mappings.except("input_temperature").each do |field, id|
          raise AtreaControl::UnsupportedConfiguration, "Missing or invalid #{field} mapping" unless id&.match?(/\A[A-Z]\d+\z/)
        end
        mappings
      end

      def mode_map(id)
        nodes = user_ctrl.xpath("/root/layout/options/op[@id='#{id}']/i")
        raise AtreaControl::UnsupportedConfiguration, "Missing #{id} definitions" if nodes.empty?

        nodes.to_h { |node| translate_mode(node) }
      end

      def parse_xml(body)
        xml = Nokogiri::XML(body) { |config| config.strict.nonet }
        raise AtreaControl::ProtocolError, "Unexpected configuration DTD" if xml.internal_subset

        xml
      rescue Nokogiri::XML::SyntaxError
        raise AtreaControl::ProtocolError, "Malformed configuration XML", cause: nil
      end

      # User defined texts in RD5 unit
      # @return [Hash]
      def user_texts
        return @user_texts if @user_texts

        response = read(_t: "config/texts.xml")
        xml = parse_xml(response.body)
        raise AtreaControl::ProtocolError, "Expected user texts XML" unless xml.at_xpath("/root/texts")

        @user_texts = xml.xpath("/root/texts/i").to_h do |node|
          value = node["value"]
          id = node["id"]
          raise AtreaControl::ProtocolError, "Invalid user text" if id.to_s.empty? || value.nil?

          [id, value.gsub(/%u([\dA-Z]{4})/) { |i| +"" << i[Regexp.last_match(1)].to_i(16) }]
        end
      end

      # @param [Nokogiri::XML::Element] mode
      # @return [Array(String, String)]
      def translate_mode(mode)
        id = mode["id"]
        title = mode["title"]
        raise AtreaControl::UnsupportedConfiguration, "Invalid mode definition" if id.to_s.empty? || title.to_s.empty?

        title = if title.start_with?("$")
                  I18n.t(title[/\w+/])
                else
                  user_texts[title]
                end
        [id, title]
      end
    end
  end
end
