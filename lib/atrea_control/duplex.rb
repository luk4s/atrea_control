# frozen_string_literal: true

require "logger"
require "selenium-webdriver"

module AtreaControl
  # Controller for +control.atrea.eu+
  class Duplex
    CONTROL_URI = "https://control.atrea.eu/"

    attr_reader :driver

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

      options = Selenium::WebDriver::Firefox::Options.new
      options.headless! unless ENV["NO_HEADLESS"]
      @driver = Selenium::WebDriver.for :firefox, options: options
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
    end

    # @return [String]
    def name
      return unless logged?

      container = driver.find_element css: "div#pageTitle > h2"
      container.text
    end

    def unit_id
      return unless logged?

      element = driver.find_element css: "div#pageTitle > a"
      element.attribute(:href) =~ /unit=(\d+)/
      Regexp.last_match(1)
    end

    # @return [Float]
    def outdoor_temperature
      return unless logged?

      element = sensor_element(@sensors[__method__])
      element.find_element(css: "div").text.to_f
    end

    # @return [Float] in %
    def current_power
      return unless logged?

      # element = driver.find_element id: "contentBox#{@sensors[__method__]}"
      element = sensor_element(@sensors[__method__])
      element.find_element(css: "div:first-child").text.to_f
    end

    # @return [String]
    def current_mode
      return unless logged?

      element = sensor_element(@sensors[__method__])
      element.find_element(css: "div:first-child").text
    end

    def inspect
      "<AtreaControl name: '#{name}' outdoor_temperature: #{outdoor_temperature}°C current_power: #{current_power}% current_mode: '#{current_mode}>'"
    end

    def close
      @logged = false
      driver.quit
    end

    private

    def logger
      @logger ||= ::Logger.new($stdout)
    end

    def sensor_element(sensor_id)
      driver.find_element id: "contentBox#{sensor_id}"
    end

    def finish_login
      8.times do |i|
        return true if open_dashboard
      rescue Selenium::WebDriver::Error::NoSuchElementError => _e
        t = 5 * (1 + i)
        logger.debug "waiting #{t}s for login..."
        sleep t
      end
      raise Error, "unable to login"
    end
  end
end
