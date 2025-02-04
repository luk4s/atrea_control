# frozen_string_literal: true

require "nokogiri"
require "time"

module AtreaControl
  # Call RD5 unit ang get current sensors values
  #   parse it and return Hash
  class SensorParser
    include AtreaControl::Logger

    # @param [AtreaControl::Duplex::UserCtrl] user_ctrl
    def initialize(user_ctrl)
      @user_ctrl = user_ctrl
    end

    def values(xml)
      format_data(parse(xml))
    end

    def input(sensor, value)
      sensor + value.to_s.rjust(5, "0")
    end

    # @see scripts.php -> loadRD5Values(node, init)
    # @note
    #   if(values[key]>32767) values[key]-=65536;
    # 			if(params[key] && params[key].offset)
    # 				values[key]=values[key]-params[key].offset;
    # 			if(params[key] && params[key].coef)
    # 				values[key]=values[key]/params[key].coef;
    def parse(xml)
      xml = Nokogiri::XML xml
      parsed = @user_ctrl.sensors.transform_values do |id|
        # node = xml.xpath("//O[@I=\"#{id}\"]/@V").last
        node = xml.xpath("//O[@I=\"#{id}\"]").last
        # logger.debug node.to_s
        value = node.attribute("V").value.to_i
        value -= 65_536 if value > 32_767
        # value -= 0 if "offset"
        # value = value / coef if "coef"
        value
      end
      preheating = %w[C10200 C10202 C10215 C10217].any? do |i|
        xml.xpath("//O[@I=\"#{i}\"]/@V").last&.value == "1"
      end
      # @note timestamp seems to be localtime of creation of xml
      parsed["timestamp"] = xml.xpath("//RD5WEB").attribute("t").to_s
      parsed["preheating"] = preheating
      parsed
    end

    # @param [Hash] values
    # @return [Hash]
    def format_data(values)
      {
        "current_mode" => parse_current_mode(values),
        "current_power" => values["current_power"].to_f,
        "outdoor_temperature" => values["outdoor_temperature"].to_f / 10.0,
        "preheat_temperature" => values["preheat_temperature"].to_f / 10.0,
        "input_temperature" => values["input_temperature"].to_f / 10.0,
        "preheating" => values["preheating"],
        "timestamp" => Time.strptime(values["timestamp"], "%Y-%m-%d %H:%M:%S"),
      }
    end

    private

    # `current_mode_switch` = mode trigger by wall switch or something similar
    # `current_mode` = is common "builtin" mode
    def parse_current_mode(values)
      if values["current_mode_switch"].positive?
        @user_ctrl.user_modes[values["current_mode_switch"].to_s]
      else
        @user_ctrl.modes[values["current_mode"].to_s]
      end
    end
  end
end
