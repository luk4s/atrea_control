# frozen_string_literal: true

require "nokogiri"
require "time"
require "tzinfo"

module AtreaControl
  # Call RD5 unit ang get current sensors values
  #   parse it and return Hash
  class SensorParser
    include AtreaControl::Logger

    # @param [AtreaControl::Duplex::UserCtrl] user_ctrl
    def initialize(user_ctrl, time_zone: nil)
      @user_ctrl = user_ctrl
      @time_zone = TZInfo::Timezone.get(time_zone) unless time_zone.nil?
    rescue TZInfo::InvalidTimezoneIdentifier
      raise AtreaControl::ProtocolError, "Invalid unit time zone", cause: nil
    end

    def values(xml)
      snapshot(xml).fetch(:values)
    end

    # Readings and policy share one validated register map, without mutable caches.
    def snapshot(xml)
      document = validated_document(xml)
      registers = extract_registers(document)
      configuration = Duplex::RD5Configuration.new(registers)
      { values: format_data(project(document, registers, configuration)), configuration: configuration, registers: registers.freeze }
    end

    def input(sensor, value)
      Duplex::RD5Command.encode(sensor, value)
    end

    # Validated register values stay unsigned until mapped to temperature fields.
    def raw_values(xml)
      extract_registers(validated_document(xml))
    end

    def parse(xml)
      document = validated_document(xml)
      registers = extract_registers(document)
      project(document, registers, Duplex::RD5Configuration.new(registers))
    end

    # @param [Hash] values
    # @return [Hash]
    def format_data(values)
      {
        "current_mode" => parse_current_mode(values),
        "current_power" => values["current_power"].to_f,
        "outdoor_temperature" => values["outdoor_temperature"].to_f / 10.0,
        "preheat_temperature" => values["preheat_temperature"].to_f / 10.0,
        "required_temperature" => values["preheat_temperature"].to_f / 10.0,
        "input_temperature" => values["input_temperature"]&.fdiv(10),
        "preheating" => values["preheating"],
        "timestamp" => timestamp_time(values["timestamp"]),
      }
    end

    private

    def project(document, registers, configuration)
      parsed = @user_ctrl.sensors.to_h do |field, id|
        value = field == "input_temperature" ? input_temperature(registers, configuration) : mapped_value(registers, field, id)
        value -= 65_536 if %w[outdoor_temperature preheat_temperature input_temperature].include?(field) && value.to_i > 32_767
        [field, value]
      end
      parsed["required_temperature"] = parsed["preheat_temperature"]
      # @note timestamp seems to be localtime of creation of xml
      parsed["timestamp"] = document.root["t"]
      parsed["preheating"] = %w[C10200 C10202 C10215 C10217].any? { |id| registers[id] == 1 }
      parsed
    end

    def input_temperature(registers, configuration)
      source = @user_ctrl.input_temperature_source if @user_ctrl.respond_to?(:input_temperature_source)
      return configuration.input_temperature if source.to_s == "rd5_standard"
      return nil unless source.nil?

      registers[@user_ctrl.sensors["input_temperature"]]
    end

    def mapped_value(registers, field, id)
      raise AtreaControl::UnsupportedConfiguration, "Invalid register mapping for #{field}" unless id.is_a?(String) && id.match?(/\A[A-Z]\d+\z/)
      return registers[id] if %w[power_input power_switch mode_input mode_switch].include?(field)

      registers.fetch(id) { raise AtreaControl::ProtocolError, "Missing required register #{id}" }
    end

    def validated_document(xml)
      document = Nokogiri::XML(xml) { |config| config.strict.nonet }
      raise AtreaControl::ProtocolError, "Expected RD5WEB/RD5 unit XML" if document.internal_subset || !document.at_xpath("/RD5WEB/RD5")

      validate_timestamp(document.root["t"])
      document
    rescue Nokogiri::XML::SyntaxError
      raise AtreaControl::ProtocolError, "Malformed unit XML", cause: nil
    end

    def validate_timestamp(timestamp)
      raise AtreaControl::SessionExpired if timestamp.to_s.strip.empty?

      timestamp_time(timestamp)
    end

    def timestamp_time(timestamp)
      timestamp = timestamp.strip if timestamp.is_a?(String)
      format = "%Y-%m-%d %H:%M:%S"
      raise AtreaControl::ProtocolError, "Invalid unit timestamp" unless timestamp.is_a?(String) && timestamp.match?(/\A[0-9]{4}-[0-9]{1,2}-[0-9]{1,2} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\z/)

      timestamp = timestamp.gsub(/[0-9]+/) { |component| component.rjust(2, "0") }
      local = Time.strptime("#{timestamp} +0000", "#{format} %z")
      raise AtreaControl::ProtocolError, "Invalid unit timestamp" unless local.strftime(format) == timestamp

      @time_zone ? @time_zone.local_to_utc(local, nil) : Time.strptime(timestamp, format)
    rescue ArgumentError, TZInfo::AmbiguousTime, TZInfo::PeriodNotFound
      raise AtreaControl::ProtocolError, "Invalid unit timestamp", cause: nil
    end

    def extract_registers(document)
      document.xpath("/RD5WEB/RD5/*/O").each_with_object({}) do |node, registers|
        id = node["I"].to_s
        value = node["V"].to_s
        raise AtreaControl::ProtocolError, "Invalid register #{id.inspect}" unless id.match?(/\A[A-Z]\d+\z/) && value.match?(/\A\d+\z/) && value.to_i <= 65_535

        registers[id] = Integer(value, 10)
      end
    end

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
