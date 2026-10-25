# frozen_string_literal: true

require_relative "login_discovery"

module AtreaControl
  module Duplex
    # Discover account tokens, then poll until a usable unit session or deadline.
    class LoginSession
      def initialize(unit_id:, request:, wait:, diagnostic:)
        @request = request
        @wait = wait
        @diagnostic = diagnostic
        @discovery = LoginDiscovery.new(request: request, unit_id: unit_id)
      end

      def call
        @user_id = @discovery.user_id
        @unit = @discovery.unit
        sid = query
        if sid == "0"
          connect
          sid = poll
          @diagnostic.call("login_complete")
        else
          @diagnostic.call("session_reused")
        end
        { user_id: @user_id, unit_id: @unit[:ident], sid: sid }
      end

      private

      def query
        body = @request.call("session_query", :get, "/apps/rd5Control/handle.php", { Sync: 1, action: "unitQuery", query: "loged", user: @user_id, unit: @unit[:ident] })
        LoginXML.value(LoginXML.node(body, "/root/login")["sid"], "session SID")
      end

      def connect
        params = { Sync: 1, action: "unitLogin", user: @user_id, unit: @unit[:ident], table: "userUnits", idPwd: @unit[:iid] }
        body = @request.call("unit_login", :post, "/apps/rd5Control/handle.php", params, { comm: "config/login.cgi?magic=" })
        LoginXML.node(body, "/root/sended")
      end

      def poll
        loop do
          sid = query
          return sid unless sid == "0"

          @wait.call
        end
      end
    end
  end
end
