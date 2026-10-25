# frozen_string_literal: true

require_relative "../../support/user_ctrl"

RSpec.describe AtreaControl::Duplex::Request do
  subject(:request) { described_class.new(user_id: "1234", unit_id: "unit", sid: "secret-sid") }

  let(:endpoint) { %r{/comm/sw/unit.php} }

  [200, 204].each do |status|
    it "returns HTTP #{status} responses" do
      stub_request(:get, endpoint).to_return(status: status, body: "response")

      expect(request.call(_t: "config/xml.xml").status).to eq(status)
    end
  end

  { 401 => :SessionExpired, 403 => :SessionExpired,
    429 => :TransportError, 500 => :TransportError, 302 => :TransportError, }.each do |status, error|
    it "rejects HTTP #{status} without exposing response secrets" do
      stub_request(:get, endpoint).to_return(status: status, body: "secret-sid secret-cookie")

      expect { request.call(_t: "config/xml.xml") }.to raise_error(AtreaControl.const_get(error)) { |failure|
        expect(failure.full_message).not_to match(/secret-sid|secret-cookie|auth=/)
        expect(failure.cause).to be_nil
      }
    end
  end

  [Faraday::ConnectionFailed, Faraday::TimeoutError].each do |error|
    it "sanitizes #{error} and discards its cause" do
      stub_request(:get, endpoint).to_raise(error.new("https://portal/?auth=secret-sid secret-password"))

      expect { request.call(_t: "config/xml.xml") }.to raise_error(AtreaControl::TransportError) { |failure|
        expect(failure.full_message).not_to match(/secret-|auth=/)
        expect(failure.cause).to be_nil
      }
    end
  end

  it "classifies timeouts separately" do
    stub_request(:get, endpoint).to_timeout

    expect { request.call(_t: "config/xml.xml") }.to raise_error(AtreaControl::UnitConnectionTimeout)
  end

  [Net::OpenTimeout, Net::ReadTimeout].each do |timeout|
    it "classifies adapter #{timeout} without retrying writes" do
      failed_request = stub_request(:get, endpoint).to_raise(timeout.new("secret-sid"))

      expect { request.call(_t: "config/xml.cgi", _w: 1) }
        .to raise_error(AtreaControl::UnitConnectionTimeout) { |error| expect(error.cause).to be_nil }
      expect(failed_request).to have_been_requested.once
    end
  end

  it "configures finite default timeouts" do
    stub_request(:get, endpoint).to_return(status: 200)
    request.call(_t: "config/xml.xml")

    expect(request.instance_variable_get(:@connection).options.to_h)
      .to include(open_timeout: 10, timeout: 60)
  end

  it "accepts timeout overrides" do
    client = described_class.new(user_id: 1, unit_id: "unit", sid: "secret-sid", open_timeout: 2, read_timeout: 5)
    stub_request(:get, endpoint).to_return(status: 200)
    client.call(_t: "config/xml.xml")

    expect(client.instance_variable_get(:@connection).options.to_h)
      .to include(open_timeout: 2, timeout: 5)
  end

  describe "unit setters" do
    include_context "userCtrl"

    let(:unit) { AtreaControl::Duplex::Unit.new(user_id: 1234, unit_id: "unit", sid: "secret-sid", user_ctrl: user_ctrl) }

    before do
      xml = Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/unit.xml")))
      xml.root["t"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      xml.at_xpath("//O[@I='H10510']")["V"] = "1"
      xml.at_xpath("//O[@I='C10508']")["V"] = "0"
      stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_return(body: xml.to_xml)
    end

    [403, 500].each do |status|
      %i[power mode].each do |setting|
        it "rejects #{setting}= on HTTP #{status} without retrying" do
          failed_request = stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_return(status: status)

          error = status == 403 ? AtreaControl::SessionExpired : AtreaControl::TransportError
          expect { unit.public_send(:"#{setting}=", 1) }.to raise_error(error)
          expect(failed_request).to have_been_requested.once
        end
      end
    end

    %i[power mode].each do |setting|
      it "does not retry #{setting}= after a write timeout" do
        failed_request = stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_timeout
        expect { unit.public_send(:"#{setting}=", 1) }.to raise_error(AtreaControl::UnitConnectionTimeout)
        expect(failed_request).to have_been_requested.once
      end

      [nil, "1.0", 1.5, 65_536].each do |value|
        it "makes no HTTP write for #{setting}=#{value.inspect}" do
          write = stub_request(:get, endpoint).with(query: hash_including("_w" => "1"))
          expect { unit.public_send(:"#{setting}=", value) }.to raise_error(ArgumentError)
          expect(write).not_to have_been_requested
        end
      end
    end
  end
end
