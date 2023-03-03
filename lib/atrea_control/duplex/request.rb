# frozen_string_literal: true

require "rest-client"

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
        RestClient.get "#{AtreaControl::Duplex::CONTROL_URI}/comm/sw/unit.php", params: @params.merge(params)
      end
    end
  end
end
