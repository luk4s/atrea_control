# frozen_string_literal: true

module AtreaControl
  module Duplex
    # Strict portal XML validation. Never include response data or parser causes in errors.
    module LoginXML
      def self.document(body)
        document = Nokogiri::XML(body) { |config| config.strict.nonet }
        raise AtreaControl::ProtocolError, "Unexpected portal XML document", cause: nil if document.internal_subset || document.root&.name != "root"

        document
      rescue Nokogiri::XML::SyntaxError
        raise AtreaControl::ProtocolError, "Malformed portal XML", cause: nil
      end

      def self.node(body, path)
        nodes = document(body).xpath(path)
        raise AtreaControl::ProtocolError, "Missing or ambiguous portal response node", cause: nil unless nodes.size == 1

        nodes.first
      end

      def self.value(value, label)
        raise AtreaControl::ProtocolError, "Missing or invalid #{label}", cause: nil if value.nil? || value.empty? || value.match?(/\s/)

        value
      end
    end

    # Resolve account list references to unit identifiers, caching each listed record.
    class LoginDiscovery
      def initialize(request:, unit_id:)
        @request = request
        @requested_ident = unit_id&.to_s
        @records = {}
      end

      def user_id
        @user_id ||= LoginXML.value(LoginXML.node(@request.call("client", :get, "/core/core.php", { action: "init" }), "/root/client")["id"], "client ID")
      end

      def unit
        @unit ||= select_unit
      end

      private

      def select_unit
        entries = listed_units
        return resolve(entries.first) unless @requested_ident

        matches = entries.map { |entry| resolve(entry) }.select { |record| record[:ident] == @requested_ident }
        raise AtreaControl::ProtocolError, "No matching unit in account list", cause: nil if matches.empty?
        raise AtreaControl::ProtocolError, "Multiple matching units in account list", cause: nil if matches.size > 1

        matches.first
      end

      def listed_units
        body = @request.call("unit_list", :get, "/_data/data.php", { Sync: 1, action: "getdata", rH: "", rE: "", table: "userUnits", ds: "rd5" })
        table = LoginXML.node(body, "/root/data/table")
        entries = table.xpath("./i")
        raise AtreaControl::ProtocolError, "No units in account list", cause: nil if entries.empty?

        entries.each do |entry|
          LoginXML.value(entry["unit"], "unit record reference")
          LoginXML.value(entry["id"], "account unit row")
        end
        entries
      end

      def resolve(entry)
        reference = entry["unit"]
        ident = @records[reference] ||= begin
          body = @request.call("unit_record", :get, "/_data/data.php", { Sync: 1, action: "getrecord", id: reference, table: "units", ds: "rd5" })
          LoginXML.value(LoginXML.node(body, "/root/datarecord/table/i")["ident"], "unit ident")
        end
        { ident: ident, iid: entry["id"] }
      end
    end
  end
end
