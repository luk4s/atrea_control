# frozen_string_literal: true

require "faraday"
require "timeout"

module AtreaControl
  module Duplex
    # Process request with duplex unit itself. Handle response
    class Request
      include AtreaControl::Logger

      # @param [String, Integer] user_id
      # @param [String, Integer] unit_id
      # @param [String, Integer] sid
      # @note `ver` is done by atrea server
      def initialize(user_id:, unit_id:, sid:, timeout: 60, open_timeout: 10, read_timeout: 60) # rubocop:disable Metrics/ParameterLists
        { timeout:, open_timeout:, read_timeout: }.each do |key, value|
          raise ArgumentError, "#{key} must be positive and finite" unless value.is_a?(Numeric) && value.real? && value.finite? && value.positive?
        end
        raise ArgumentError, "timeout must not exceed 60 seconds" if timeout > 60

        @timeout = timeout
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @params = {
          _user: user_id.to_i,
          _unit: unit_id,
          auth: sid,
          ver: AtreaControl::Duplex::CONTROL_VERSION,
        }
      end

      # @param [Hash] params
      # @option params [String] :_t ("config/xml.xml") file name
      def call(params = nil, **keywords)
        params = keywords.merge(params.to_h)
        response = Timeout.timeout(@timeout, Timeout::Error) { connection.get("#{AtreaControl::Duplex::CONTROL_URI}/comm/sw/unit.php", @params.merge(params)) }
        logger.debug "stage=unit_request status=#{response.status}"
        raise AtreaControl::SessionExpired, cause: nil if [401, 403].include?(response.status)
        raise AtreaControl::TransportError, "Unit request failed (HTTP #{response.status})", cause: nil unless (200...300).cover?(response.status)

        response
      rescue Faraday::TimeoutError, Timeout::Error
        raise AtreaControl::UnitConnectionTimeout, "Unit request timed out", cause: nil
      rescue Faraday::Error => e
        raise AtreaControl::UnitConnectionTimeout, "Unit request timed out", cause: nil if e.wrapped_exception.is_a?(Timeout::Error)

        raise AtreaControl::TransportError, "Unit connection failed", cause: nil
      rescue IOError, SystemCallError, SocketError
        raise AtreaControl::TransportError, "Unit connection failed", cause: nil
      end

      private

      def connection
        @connection ||= Faraday.new do |f|
          f.options.open_timeout = @open_timeout
          f.options.timeout = @read_timeout
          f.request :url_encoded
          f.adapter(:net_http) { |http| http.max_retries = 0 }
        end
      end
    end
  end
end
