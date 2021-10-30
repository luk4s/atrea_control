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
      submit_login_form if user.nil? || !logged?
      finish_login
      @login_in_progress = false
      inspect
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
      return unless logged?

      container = driver.find_element css: "div#pageTitle > h2"
      container.text
    end

    # @return [String] ID of logged user
    def user_id
      @user_id ||= driver.execute_script("return window._user")
    end

    # @return [String] ID of recuperation unit
    def unit_id
      @unit_id ||= driver.execute_script("return window._unit")
    end

    # Window.user object from atrea
    # @return [Hash, nil]
    def user
      driver.execute_script("return window.user")
    end

    # @return [String]
    def current_mode_name
      return current_mode unless logged?

      element = sensor_element(@sensors[:current_mode])
      element.find_element(css: "div:first-child").text
    end

    # quit selenium browser
    def close
      @user_auth = nil
      driver.quit
      remove_instance_variable :@driver
    end

    alias logout! close

    def as_json(_options = nil)
      {
        logged: logged?,
        current_mode: current_mode_name,
        current_power: current_power,
        outdoor_temperature: outdoor_temperature,
        valid_for: valid_for,
      }
    end

    alias values as_json

    def to_json(*args)
      as_json.to_json(*args)
    end

    def inspect
      "<AtreaControl name: '#{name}' outdoor_temperature: '#{outdoor_temperature}°C' current_power: '#{current_power}%' current_mode: '#{current_mode_name}' valid_for: '#{valid_for}'>"
    end

    def call_unit!
      return false if @login_in_progress

      logger.debug "call_unit!"
      parse_response(response_comm_unit)
      @valid_for = Time.now
      as_json
    rescue RestClient::Forbidden
      logger.debug "session expired..."
      close if @logged
      login && call_unit!
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

      as_json
    end

    # ? I10204 ?
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
      params = {
        _user: user_id,
        _unit: unit_id,
        auth: user&.[]("auth"),
        _t: "config/xml.xml",
      }
      autologin_token = CGI.escape([@login, @password].join("\b"))
      RestClient.get "https://control.atrea.eu/comm/sw/unit.php", { Cookie: "autoLogin=#{autologin_token}", params: params }
    end
  end
end
