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

    # @param [String] login
    # @param [String] password
    # @param [Hash] sensors_map which box is related to sensor ID
    # @option sensors_map [String] :outdoor_temperature
    # @option sensors_map [String] :current_power
    # @option sensors_map [String] :current_mode
    def initialize(login:, password:, sensors_map: Config.default_sensors_map)
      @logged = false
      @login = login
      @password = password
      @sensors = sensors_map
    end

    # @return [Selenium::WebDriver::Firefox::Driver]
    def driver
      return @driver if defined?(@driver)

      options = Selenium::WebDriver::Firefox::Options.new
      options.headless! unless ENV["NO_HEADLESS"]
      @driver ||= Selenium::WebDriver.for :firefox, options: options
    end

    def logged?
      @logged
    end

    # Login into control
    def login
      driver.get CONTROL_URI
      form = driver.find_element(id: "loginFrm")
      username = form.find_element(name: "username")
      username.send_keys @login
      password = form.find_element(name: "password")
      password.send_keys @password

      submit = form.find_element(css: "input[type=submit]")
      submit.click
      finish_login
      inspect
    end

    # Retrieve dashboard URI from object tag and open it again
    def open_dashboard
      uri = driver.find_element(tag_name: "object").attribute "data"
      driver.get uri
      logger.debug "#{name} login success"
      @logged = true
      call_unit!
    end

    # @return [String]
    def name
      return unless logged?

      container = driver.find_element css: "div#pageTitle > h2"
      container.text
    end

    def unit_id
      user_unit["_unit"]
    end

    def user_id
      user_unit["_user"]
    end

    # @return [String]
    def user_auth
      return unless logged?

      @user_auth ||= driver.execute_script("return window.user")&.[] "auth"
    end

    # @return [Hash]
    def user_unit
      return {} unless logged?
      return @user_unit if @user_unit

      element = driver.find_element(css: "#msgBox + script")
      @user_unit = element.attribute(:innerHTML).strip.scan(/(\w+)='(\d+)'/).to_h
    end

    # @return [String]
    def current_mode_name
      return unless logged?

      element = sensor_element(@sensors[:current_mode])
      element.find_element(css: "div:first-child").text
    end

    # quit selenium browser
    def close
      @logged = false
      @user_unit = nil
      @user_auth = nil
      driver.quit
      remove_instance_variable :@driver
    end

    alias logout! close

    def as_json(_options = nil)
      {
        logged: logged?,
        current_mode: current_mode,
        current_power: current_power,
        outdoor_temperature: outdoor_temperature,
      }
    end

    def to_json(*args)
      as_json.to_json(*args)
    end

    def inspect
      "<AtreaControl name: '#{name}' outdoor_temperature: #{outdoor_temperature}°C current_power: #{current_power}% current_mode: '#{current_mode_name}' valid_for: #{@valid_for}>"
    end

    def call_unit!
      return false unless logged?

      parse_response(response_comm_unit)
      @valid_for = Time.now
      values
    rescue RestClient::Forbidden
      close
      login && call_unit!
    end

    # Current sensors values
    # @return [Hash]
    def values
      @sensors.keys.map { |key| [key, send(key)] }.to_h
    end

    private

    def parse_response(response)
      xml = Nokogiri::XML response.body
      sensors_values = @sensors.transform_values do |id|
        xml.xpath("//O[@I=\"#{id}\"]/@V").last&.value
      end
      refresh_data(sensors_values)
    end

    # @param [Hash] values
    # @return [Hash]
    def refresh_data(values)
      @outdoor_temperature = values[:outdoor_temperature].to_f / 10
      @current_power = values[:current_power].to_f
      @current_mode = mode_map[values[:current_mode]]

      values
    end

    def mode_map
      { "0" => "Vypnuto", "1" => "Automat", "2" => "Větrání", "6" => "Rozvážení" }
    end

    def logger
      @logger ||= ::Logger.new($stdout)
    end

    def finish_login
      13.times do |i|
        return true if open_dashboard
      rescue Selenium::WebDriver::Error::NoSuchElementError => _e
        t = [5 * (1 + i), 25].min
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
      params = {
        _user: user_id,
        _unit: unit_id,
        auth: user_auth,
        _t: "config/xml.xml",
      }
      autologin_token = CGI.escape([@login, @password].join("\b"))
      RestClient.get "https://control.atrea.eu/comm/sw/unit.php", { Cookie: "autoLogin=#{autologin_token}", params: params }
    end
  end
end
