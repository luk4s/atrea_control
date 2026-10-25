# frozen_string_literal: true

require "nokogiri"
require "faraday"
require "http/cookie"
require "faraday-cookie_jar"
require "securerandom"
require "timeout"
require_relative "login_session"

module AtreaControl
  # RD5 portal authentication and direct unit communication.
  module Duplex
    # Authenticate to RD5 within one monotonic budget, returning direct API tokens.
    class Login
      include AtreaControl::Logger

      HTTP_TIMEOUT = 60

      def self.user_tokens(login:, password:, **)
        new(login: login, password: password, **).call
      end

      # Explicit keywords keep authentication, selection and independent budgets discoverable.
      def initialize(login:, password:, unit_id: nil, timeout: 300, poll_interval: 1, open_timeout: 10, read_timeout: 60) # rubocop:disable Metrics/ParameterLists
        { timeout:, poll_interval:, open_timeout:, read_timeout: }.each do |key, value|
          raise ArgumentError, "#{key} must be positive and finite" unless value.is_a?(Numeric) && value.real? && value.finite? && value.positive?
        end
        raise ArgumentError, "timeout must not exceed 300 seconds" if timeout > 300

        @login = login
        @password = password
        @unit_id = unit_id
        @timeout = timeout
        @poll_interval = poll_interval
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @jar = HTTP::CookieJar.new
      end

      # @return [Hash] user_id, unit_id (ident), sid
      def call
        @started_at = monotonic_time
        @deadline = @started_at + @timeout
        @poll_count = 0
        Timeout.timeout(@timeout, Timeout::Error) do
          authenticate
          tokens = LoginSession.new(unit_id: @unit_id, request: method(:portal_request), wait: method(:wait_for_poll), diagnostic: method(:diagnostic)).call
          remaining_budget
          tokens
        end
      rescue Timeout::Error
        fail_request(AtreaControl::UnitConnectionTimeout, "Portal login deadline exceeded", "deadline_exceeded")
      end

      private

      def authenticate
        @stage = "authentication"
        response = http_request(:post, "#{CONTROL_URI}?action=login", { username: @login, password: @password }, allow_redirect: true)
        fail_request(AtreaControl::AuthenticationError, "Portal authentication rejected", response.status) if Nokogiri::HTML(response.body).at_css("form#loginFrm")

        cookies = @jar.cookies(URI.parse(CONTROL_URI))
        @php_session_id = cookies.find { |cookie| cookie.name == "PHPSESSID" }&.value
        LoginXML.value(@php_session_id, "session cookie")
      end

      def portal_request(stage, method, path, params, body = nil)
        @stage = stage
        @poll_count += 1 if stage == "session_query"
        url = "#{CONTROL_URI}#{path}?#{URI.encode_www_form(params.merge(_ts: SecureRandom.hex(4)))}"
        http_request(method, url, body) do |request|
          request.headers["Cookie"] = "PHPSESSID=#{@php_session_id}"
          request.headers["App-name"] = "rd5Control"
        end.body
      end

      def connection
        @connection ||= Faraday.new do |faraday|
          faraday.options.open_timeout = @open_timeout
          faraday.options.timeout = @read_timeout
          faraday.request :url_encoded
          faraday.use :cookie_jar, jar: @jar
          faraday.adapter(:net_http) { |http| http.max_retries = 0 }
        end
      end

      def http_request(method, url, payload = nil, allow_redirect: false, &)
        budget = [HTTP_TIMEOUT, remaining_budget].min
        connection.options.open_timeout = [@open_timeout, budget].min
        connection.options.timeout = [@read_timeout, budget].min
        # The outer flow timeout already enforces the remaining login budget.
        response = Timeout.timeout(HTTP_TIMEOUT, Timeout::Error) { connection.public_send(method, url, payload, &) }
        remaining_budget
        diagnostic(@stage, response.status)
        fail_request(AtreaControl::AuthenticationError, "Portal authentication rejected", response.status) if [401, 403].include?(response.status)

        accepted = (200...300).cover?(response.status) || (allow_redirect && response.status == 302)
        fail_request(AtreaControl::TransportError, "Portal request failed (HTTP #{response.status})", response.status) unless accepted

        response
      rescue Faraday::Error, Timeout::Error, IOError, SystemCallError, SocketError => e
        transport_failure(e)
      end

      def transport_failure(error)
        remaining_budget
        wrapped = error.wrapped_exception if error.is_a?(Faraday::Error)
        timed_out = [Faraday::TimeoutError, Timeout::Error].any? { |type| error.is_a?(type) || wrapped.is_a?(type) }
        fail_request(AtreaControl::UnitConnectionTimeout, "Portal request timed out", "timeout") if timed_out

        fail_request(AtreaControl::TransportError, "Portal connection failed", "connection_failed")
      end

      def fail_request(error_class, message, status)
        diagnostic(@stage, status, level: :warn)
        raise error_class, "#{message} (stage=#{@stage} status=#{status})", cause: nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def remaining_budget
        remaining = @deadline - monotonic_time
        return remaining if remaining.positive?

        fail_request(AtreaControl::UnitConnectionTimeout, "Portal login deadline exceeded", "deadline_exceeded")
      end

      def wait_for_poll
        Kernel.sleep([@poll_interval, remaining_budget].min)
        remaining_budget
      end

      def diagnostic(stage, status = nil, level: :debug)
        logger.public_send(level, "stage=#{stage} status=#{status || "none"} elapsed=#{(monotonic_time - @started_at).round(3)} pollcount=#{@poll_count}")
      end
    end

    private_constant :LoginXML, :LoginDiscovery, :LoginSession
  end
end
