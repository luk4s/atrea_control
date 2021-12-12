# frozen_string_literal: true

require "logger"
require "nokogiri"
require "rest-client"
require "selenium-webdriver"

module AtreaControl
  # Controller for +control.atrea.eu+
  class Duplex
    CONTROL_URI = "https://control.atrea.eu/"

    attr_reader :current_mode, :current_power, :outdoor_temperature
    # @return [DateTime] store time of last update
    attr_reader :valid_for

    attr_accessor :user_id, :unit_id, :auth_token
    attr_writer :user_texts, :user_modes, :modes

    # @param [String] login
    # @param [String] password
    # @param [Hash] sensors_map which box is related to sensor ID
    # @option sensors_map [String] :outdoor_temperature
    # @option sensors_map [String] :current_power
    # @option sensors_map [String] :current_mode
    def initialize(login:, password:, sensors_map: Config.default_sensors_map)
      @login = login
      @password = password
      @sensors = sensors_map
    end

    # @return [Selenium::WebDriver::Firefox::Driver]
    def driver
      return @driver if defined?(@driver)

      options = Selenium::WebDriver::Firefox::Options.new
      options.headless! unless ENV["NO_HEADLESS"]
      @driver ||= Selenium::WebDriver.for :firefox, capabilities: [options]
    end

    def logged?
      user&.[] "loged"
    end

    def login_in_progress?
      @login_in_progress
    end

    # Login into control
    def login
      @login_in_progress = true
      logger.debug "start new login"
      driver.get CONTROL_URI
      submit_login_form unless logged?
      finish_login
      refresh!
      inspect
    ensure
      @login_in_progress = false
    end

    # Submit given credentials and proceed login
    def submit_login_form
      form = driver.find_element(id: "loginFrm")
      username = form.find_element(name: "username")
      username.send_keys @login
      password = form.find_element(name: "password")
      password.send_keys @password

      submit = form.find_element(css: "input[type=submit]")
      submit.click
    end

    # Retrieve dashboard URI from object tag and open it again
    def open_dashboard
      uri = driver.find_element(tag_name: "object").attribute "data"
      driver.get uri
      logger.debug "#{name} login success"
    end

    # @return [String]
    def name
      @name ||= user_texts["UnitName"]
    end

    # Window.user object from atrea
    # @return [Hash, nil]
    def user
      driver.execute_script("return window.user")
    end

    # quit selenium browser
    def close
      driver.quit
    ensure
      remove_instance_variable :@driver
    end

    alias logout! close

    def as_json(_options = nil)
      {
        current_mode: current_mode,
        current_power: current_power,
        outdoor_temperature: outdoor_temperature,
        valid_for: valid_for,
      }
    end

    alias values as_json

    def to_json(*args)
      as_json.to_json(*args)
    end

    def call_unit!
      return false if @login_in_progress

      logger.debug "call_unit!"
      parse_values(response_comm_unit)
      @valid_for = Time.now
      as_json
    end

    def modes
      return @modes if @modes

      @modes = {}
      user_ctrl.xpath("//op[@id='Mode']/i").each do |mode|
        m = translate_mode(mode)
        @modes[m[:id]] = m[:value]
      end
      @modes
    end

    def user_modes
      return @user_modes if @user_modes

      @user_modes = {}
      user_ctrl.xpath("//op[@id='ModeText']/i").each do |mode|
        m = translate_mode(mode)
        @user_modes[m[:id]] = m[:value]
      end
      @user_modes
    end

    # User defined texts in RD5 unit
    # @return [Hash]
    def user_texts
      return @user_texts if @user_texts

      response = rd5_request(params_comm_unit.merge(_t: "config/texts.xml"))
      xml = Nokogiri::XML response.body
      @user_texts = xml.xpath("//i").map do |node|
        value = node.attributes["value"].value
        id = node.attributes["id"].value
        [id, value.gsub(/%u([\dA-Z]{4})/) { |i| +'' << i[$1].to_i(16) }]
      end.to_h
    end

    private

    # @see scripts.php -> loadRD5Values(node, init)
    # @note
    #   if(values[key]>32767) values[key]-=65536;
    # 			if(params[key] && params[key].offset)
    # 				values[key]=values[key]-params[key].offset;
    # 			if(params[key] && params[key].coef)
    # 				values[key]=values[key]/params[key].coef;
    def parse_values(response)
      xml = Nokogiri::XML response.body
      sensors_values = @sensors.transform_values do |id|
        value = xml.xpath("//O[@I=\"#{id}\"]/@V").last&.value.to_i
        value -= 65_536 if value > 32_767
        # value -= 0 if "offset"
        # value -= 0 if "coef"
        value
      end
      refresh_data(sensors_values)
    end

    # @param [Hash] values
    # @return [Hash]
    def refresh_data(values)
      @outdoor_temperature = values[:outdoor_temperature].to_f / 10.0
      @current_power = values[:current_power].to_f
      @current_mode = if values[:current_mode_switch].positive?
                        user_modes[values[:current_mode_switch].to_s]
                      else
                        modes[values[:current_mode].to_s]
                      end
      # @current_mode = mode_map[values[:current_mode_name] > 0 ? values[:current_mode_name] : values[:current_mode]]

      as_json
    end

    def logger
      @logger ||= ::Logger.new($stdout)
    end

    def finish_login
      13.times do |i|
        return true if open_dashboard
      rescue Selenium::WebDriver::Error::NoSuchElementError => _e
        t = [3 * (1 + i), 25].min
        logger.debug "waiting #{t}s for login..."
        sleep t
      end
      raise Error, "unable to login"
    end

    def sensor_element(sensor_id)
      driver.find_element id: "contentBox#{sensor_id}"
    end

    # @return [RestClient::Response]
    def response_comm_unit
      rd5_request(params_comm_unit.merge(_t: "config/xml.xml"))
    end

    def rd5_request(params)
      RestClient.get "https://control.atrea.eu/comm/sw/unit.php", { Cookie: "autoLogin=#{autologin_token}", params: params }
    end

    def user_ctrl
      response = rd5_request(params_comm_unit.merge(_t: "lang/userCtrl.xml"))
      xml = Nokogiri::XML response.body
    end

    def autologin_token
      @autologin_token ||= CGI.escape([@login, @password].join("\b"))
    end

    # @note `ver` is done by atrea server
    def params_comm_unit
      {
        _user: user_id.to_i,
        _unit: unit_id,
        auth: auth_token || "null",
        ver: "003001009",
      }
    end

    # Update tokens based on current state
    def refresh!
      @user_id = driver.execute_script("return window._user")
      @unit_id = driver.execute_script("return window._unit")
      @auth_token = user&.[]("auth")
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
        response = rd5_request(params_comm_unit.merge(_t: "lang/texts_#{atrea_id}.xml", auth: nil))

        xml = Nokogiri::XML response.body
        locale = eval xml.xpath("//words/text()")[0].text
        yaml = { name.to_s => JSON.parse(locale.to_json) }.to_yaml
        File.write(File.expand_path("../../config/locales/#{name}.yml", __dir__), yaml)
      end
    end

  end
end
