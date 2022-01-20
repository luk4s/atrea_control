require "digest"
require "rest-client"
require "selenium-webdriver"

module AtreaControl
  module Duplex
    # Process login into RD5 with selenium to get `sid` ( auth_token ) for direct API communication
    class Login

      include AtreaControl::Logger

      # @return [Hash] - user_id, unit_id, sid
      def self.user_tokens(login:, password:)
        i = new(login: login, password: password)
        tokens = i.user

        tokens
      ensure
        i.close
      end

      # @param [String] login
      # @param [String] password
      def initialize(login:, password:)
        @login = login
        @password = password
      end
      #
      # def crypto_password
      #   md5 = Digest::MD5.new
      #   md5 << "\r\n"
      #   md5 << @password
      #   md5.hexdigest
      # end
      #
      # def token
      #   RestClient.get "#{AtreaControl::Duplex::CONTROL_URI}/config/login.cgi", params: { magic: crypto_password }
      # end

      def user
        raise AtreaControl::Error, "Must be logged in" unless login

        logger.debug "refresh user data based on session"
        @user_id = driver.execute_script("return window._user")
        @unit_id = driver.execute_script("return window._unit")
        @auth_token = driver.execute_script("return window.user")&.[]("auth") # sid

        { user_id: @user_id, unit_id: @unit_id, sid: @auth_token }
      end

      # @return [Selenium::WebDriver::Firefox::Driver]
      def driver
        return @driver if defined?(@driver)

        options = Selenium::WebDriver::Firefox::Options.new
        options.headless! unless ENV["NO_HEADLESS"]
        @driver ||= Selenium::WebDriver.for :firefox, capabilities: [options]
      end

      # Login into control
      def login
        return driver if @logged

        @login_in_progress = true
        logger.debug "start new login..."
        driver.get "#{AtreaControl::Duplex::CONTROL_URI}?action=logout"
        submit_login_form
        finish_login
        driver
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
        logger.debug "Submit login form..."

        submit = form.find_element(css: "input[type=submit]")
        submit.click
      end

      # Retrieve dashboard URI from object tag and open it again
      def open_dashboard
        uri = driver.find_element(tag_name: "object").attribute "data"
        # Open "iframe" with atrea dashboard - it propagate window objects...
        driver.get uri
        logger.debug "login success"
        @logged = true
      end

      # quit selenium browser
      def close
        driver.quit rescue nil
        logger.debug "driver closed & destroyed"
      ensure
        remove_instance_variable :@driver
      end

      private

      def finish_login
        30.times do |i|
          return true if open_dashboard
        rescue Selenium::WebDriver::Error::NoSuchElementError => e
          logger.debug e.message
          logger.debug "#{i + 1}/30 attempt for login..."
          sleep 10
        end
        File.write("/tmp/failed_login-#{@login}.html", driver.page_source)
        raise AtreaControl::Error, "unable to login"
      end

    end
  end
end
