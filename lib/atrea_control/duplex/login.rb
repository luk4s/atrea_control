# frozen_string_literal: true

require "nokogiri"
require "rest-client"
require "securerandom"

module AtreaControl
  module Duplex
    # Process login into RD5 to get `sid` ( auth_token ) for direct API communication
    class Login
      include AtreaControl::Logger

      # @return [Hash] - user_id, unit_id, sid
      def self.user_tokens(login:, password:)
        instance = new(login: login, password: password)
        instance.call
      end

      # @param [String] login
      # @param [String] password
      def initialize(login:, password:)
        @login = login
        @password = password
      end

      # Perform login procedure for retrieve `sid` (auth_token)
      # @return [Hash] - user_id, unit_id, sid
      # @raise [AtreaControl::Error] if login failed
      def call
        @sid = sid
        if @sid == "0"
          re_login = RestClient.post "#{AtreaControl::Duplex::CONTROL_URI}/apps/rd5Control/handle.php?action=unitLogin&user=#{user_id}&unit=#{unit_id}&table=userUnits&idPwd=#{unit[:iid]}&#{SecureRandom.hex(2)}&_ts=#{SecureRandom.hex(4)}",
                                     { comm: "config/login.cgi?magic=" }, headers
          time = Nokogiri::XML(re_login.body).at_xpath("//sended")["time"].to_i
          logger.debug "Login in #{time} seconds..."
          time.times do
            @sid = sid
            break if @sid != "0"

            sleep 1
          end
          raise AtreaControl::Error, "Login failed" if @sid == "0"

          logger.debug "Login complete !"
        else
          logger.debug "Login is not necessary ! SID: #{@sid}"
        end
        { user_id:, unit_id:, sid: @sid }
      end

      private

      # @!group Login steps, order is important

      # Retrieve user details from RD5 core.php?action=init
      # @return [Hash] - user_id, name
      def user
        core_init = RestClient.get "#{AtreaControl::Duplex::CONTROL_URI}/core/core.php?action=init&_ts=#{SecureRandom.hex(4)}",
                                   headers
        client = Nokogiri::XML(core_init.body).at_xpath("//client")
        user_id = client["id"]
        name = client["name"]
        logger.debug "User ID: #{user_id}, User Name: #{name}"

        { user_id:, name: }
      end

      def user_id
        @user_id ||= user[:user_id]
      end

      # For some reason, this requests must be done before `unit_id` requested
      def run_rd5_app
        RestClient.post "#{AtreaControl::Duplex::CONTROL_URI}/core/core.php?Sync=1&action=run&object=app&lng=28&rVer=1&_ts=#{SecureRandom.hex(4)}",
                        { name: "rd5Control", path: "apps/rd5Control/" }, headers
        RestClient.post "#{AtreaControl::Duplex::CONTROL_URI}/core/core.php?Sync=1&action=load&object=setting&_ts=#{SecureRandom.hex(4)}",
                        { path: "apps/rd5Control" }, headers
      end

      # Retrieve overview of RD5 unit
      # @return [Hash] - unit_number (digit code/ID from list) and iid (unit salt?)
      def unit
        return @unit if @unit

        # run_rd5_app
        units_table = RestClient.get "#{AtreaControl::Duplex::CONTROL_URI}/_data/data.php?Sync=1&action=getdata&rH&rE&table=userUnits&ds=rd5&_ts=#{SecureRandom.hex(4)}",
                                     headers
        item = Nokogiri::XML(units_table.body).at_xpath("//i")
        unit_number = item["unit"]
        iid = item["id"]
        @unit ||= { unit_number:, iid: }
      end

      # With `unit_number` from `unit` method, get `unit_id` from RD5 unit records
      # @return [String] - unit_id
      def unit_id
        return @unit_id if @unit_id

        records = RestClient.get "#{AtreaControl::Duplex::CONTROL_URI}/_data/data.php?Sync=1&action=getrecord&id=#{unit[:unit_number]}&table=units&ds=rd5&_ts=#{SecureRandom.hex(4)}",
                                 headers
        @unit_id ||= Nokogiri::XML(records.body).at_xpath("//table/i")["ident"]
      end

      def sid
        data = RestClient.get "#{AtreaControl::Duplex::CONTROL_URI}/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=#{user_id}&unit=#{unit_id}&#{SecureRandom.hex(2)}&_ts=#{SecureRandom.hex(4)}",
                              headers
        logger.debug data.body
        Nokogiri::XML(data.body).at_xpath("//login")["sid"]
      end

      # @!group Private methods

      # @return [String] session ID from PHP BE
      def php_session_id
        return @php_session_id if @php_session_id

        payload = { username: @login, password: @password }
        RestClient.post "#{AtreaControl::Duplex::CONTROL_URI}?action=login", payload do |response|
          @php_session_id = response.cookies["PHPSESSID"]
        end
        @php_session_id
      end

      def headers
        { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control" }
      end
    end
  end
end
