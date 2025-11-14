# frozen_string_literal: true

require "faraday"

module AtreaControl
  module Duplex
    # Process request with duplex unit itself. Handle response
    class Request
      include AtreaControl::Logger

      # @param [String, Integer] user_id
      # @param [String, Integer] unit_id
      # @param [String, Integer] sid
      # @note `ver` is done by atrea server
      def initialize(user_id:, unit_id:, sid:)
        @params = {
          _user: user_id.to_i,
          _unit: unit_id,
          auth: sid,
          ver: AtreaControl::Duplex::CONTROL_VERSION,
        }
      end

      # @param [Hash] params
      # @option params [String] :_t ("config/xml.xml") file name
      def call(params)
        connection = Faraday.new do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
        end

        connection.get("#{AtreaControl::Duplex::CONTROL_URI}/comm/sw/unit.php", @params.merge(params))
      end
    end
  end
end
# https://control.atrea.eu/comm/sw/unit.php?ver=003001022&_user=2113&_unit=126399332270040&auth=49852&_t=config/xml.xml&_X=Ti&_async=1
