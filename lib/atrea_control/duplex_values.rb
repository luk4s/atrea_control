module AtreaControl
  # Call RD5 unit ang get current sensors values
  #   parse it and return Hash
  class DuplexValues

    attr_reader :duplex

    # @param [AtreaControl::Duplex] duplex
    def initialize(duplex)
      @duplex = duplex
    end

    def call
      response = duplex.rd5_unit_request(duplex.params_comm_unit.merge(_t: "config/xml.xml"))
      raw_sensor_values = parse(response)
      process_data(raw_sensor_values)
    end

    # @see scripts.php -> loadRD5Values(node, init)
    # @note
    #   if(values[key]>32767) values[key]-=65536;
    # 			if(params[key] && params[key].offset)
    # 				values[key]=values[key]-params[key].offset;
    # 			if(params[key] && params[key].coef)
    # 				values[key]=values[key]/params[key].coef;
    def parse(response)
      xml = Nokogiri::XML response.body
      duplex.sensors.transform_values do |id|
        value = xml.xpath("//O[@I=\"#{id}\"]/@V").last&.value.to_i
        value -= 65_536 if value > 32_767
        # value -= 0 if "offset"
        # value -= 0 if "coef"
        value
      end
    end

    # @param [Hash] values
    # @return [Hash]
    def process_data(values)
      {
        current_mode: parse_current_mode(values),
        current_power: values[:current_power].to_f,
        outdoor_temperature: values[:outdoor_temperature].to_f / 10.0,
        valid_for: Time.now,
      }
    end

    # `current_mode_switch` = mode trigger by wall switch or something similar
    # `current_mode` = is common "builtin" mode
    def parse_current_mode(values)
      if values[:current_mode_switch].positive?
        duplex.user_modes[values[:current_mode_switch].to_s]
      else
        duplex.modes[values[:current_mode].to_s]
      end
    end

  end
end
