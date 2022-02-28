require "nokogiri"

module AtreaControl
  module Duplex
    # Parse `userCtrl.xml`
    class UserCtrl
      # @param (see #initialize)
      def self.data(user_id:, unit_id:, sid:)
        user_ctrl = new(user_id: user_id, unit_id: unit_id, sid: sid)
        {
          name: user_ctrl.name,
          sensors: user_ctrl.sensors,
          modes: user_ctrl.modes,
          user_modes: user_ctrl.user_modes,
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
        response = request.call(_t: "lang/userCtrl.xml")
        Nokogiri::XML response.body
      end

      # User-defined name of home (RD5 unit)
      # @return [String]
      def name
        @name ||= user_texts["UnitName"]
      end

      # Gather ID of sensors based on userCtrl config file
      def sensors
        return @sensors if @sensors

        power = user_ctrl.xpath("//body/content/i[@title='$currentPower']")
        mode = user_ctrl.xpath("//body/content/i[@title='$currentMode']")
        outdoor_temp = user_ctrl.xpath("//body/content/i[@title='$outdoorTemp']")

        switch_mode = mode.xpath("displayval").text[/values\.(\w+)/, 1]

        power_input = power.xpath("onchange").text[/getUrlPar\('(\w+)',val\)/, 1]
        m = mode.xpath("onchange").text.match(/getUrlPar\('(\w+)',val\).*getUrlPar\(.(\w+).,2\)/)

        preheat_temperature = user_ctrl.xpath("//body/content/i[@title='$requiredTemp']")

        input_temp = user_ctrl.xpath("//body/content/i[@title='$inletTemp']") # "I10200"
        input_temperature = input_temp.xpath("displayval").text[/val=values\.(\w\d+);/, 1]
        @sensors = {
          "outdoor_temperature" => outdoor_temp.attribute("id").value, # "I10208"
          "preheat_temperature" => preheat_temperature.attribute("id").value, # "H10706"
          "input_temperature" => input_temperature,
          "current_power" => power.attribute("id").value, # "H10704"
          "current_mode" => mode.attribute("id").value, # "H10705"
          "current_mode_switch" => switch_mode, # "H10712"
          "power_input" => power_input, # "H10708"
          "mode_input" => m[1], # "H10709"
          "mode_switch" => m[2], # "H10701"
        }
      end

      # Generic modes
      # @return [Hash]
      def modes
        return @modes if @modes

        @modes = {}
        user_ctrl.xpath("//op[@id='Mode']/i").each do |mode|
          m = translate_mode(mode)
          @modes[m[:id]] = m[:value]
        end
        @modes
      end

      # Modes by inputs - switches - named by user custom texts
      # @return [Hash]
      def user_modes
        return @user_modes if @user_modes

        @user_modes = {}
        user_ctrl.xpath("//op[@id='ModeText']/i").each do |mode|
          m = translate_mode(mode)
          @user_modes[m[:id]] = m[:value]
        end
        @user_modes
      end

      private

      # User defined texts in RD5 unit
      # @return [Hash]
      def user_texts
        return @user_texts if @user_texts

        response = request.call(_t: "config/texts.xml")
        xml = Nokogiri::XML response.body
        @user_texts = xml.xpath("//i").to_h do |node|
          value = node.attributes["value"].value
          id = node.attributes["id"].value
          [id, value.gsub(/%u([\dA-Z]{4})/) { |i| +"" << i[Regexp.last_match(1)].to_i(16) }]
        end
      end

      # @param [Nokogiri::XML::Element] mode
      # @return [Hash{Symbol->String}]
      def translate_mode(mode)
        id = mode.attributes["id"].value
        title = mode.attributes["title"].value
        title = if title.start_with?("$")
                  I18n.t(title[/\w+/])
                else
                  user_texts[title]
                end
        { id: id, value: title }
      end

      # Re-generate copy of locale files
      # @note internal use only
      def update_locales_files!
        { cs: "0", de: "1", en: "2" }.each do |name, atrea_id|
          response = request.call(_t: "lang/texts_#{atrea_id}.xml")

          xml = Nokogiri::XML response.body
          # `eval` JS object (= hash)
          locale = eval xml.xpath("//words/text()")[0].text
          yaml = { name.to_s => JSON.parse(locale.to_json) }.to_yaml
          File.write(File.expand_path("../../../config/locales/#{name}.yml", __dir__), yaml)
        end
      end
    end
  end
end
