# frozen_string_literal: true

require "stringio"
require_relative "../../support/login_clock"

FIXTURE_CORE_INIT_PATH = File.join(__dir__, "../../fixtures/files/core.php-init.xml")
FIXTURE_UNITS_TABLE_PATH = File.join(__dir__, "../../fixtures/files/data.php-getdata.xml")
FIXTURE_UNIT_RECORD_PATH = File.join(__dir__, "../../fixtures/files/data.php-getrecord.xml")
FIXTURE_UNIT_QUERY_PATH_0 = File.join(__dir__, "../../fixtures/files/handle.php-unitQuery_0.xml")
FIXTURE_UNIT_QUERY_PATH = File.join(__dir__, "../../fixtures/files/handle.php-unitQuery_009.xml")

RSpec.describe AtreaControl::Duplex::Login do
  subject(:duplex) { described_class.new login: "myhome", password: "secret" }

  include_context "with login clock"

  before do
    stub_request(:post, /\?action=login/)
      .to_return(headers: { "Set-Cookie" => "PHPSESSID=12345" })

    stub_request(:get, %r{.*core/core.php\?.*action=init})
      .with(headers: { "Cookie" => "PHPSESSID=12345", "App-name" => "rd5Control" })
      .to_return(body: File.read(FIXTURE_CORE_INIT_PATH))

    stub_request(:post, %r{/core/core.php\?Sync=1&action=run&object=app&lng=28&rVer=1})
      .to_return(status: 200)

    stub_request(:post, %r{/core/core.php\?Sync=1&action=load&object=setting})
      .to_return(status: 200)

    stub_request(:get, %r{/_data/data.php\?.*action=getdata.*&ds=rd5})
      .to_return(body: File.read(FIXTURE_UNITS_TABLE_PATH))

    stub_request(:get, %r{/_data/data.php\?.*action=getrecord})
      .to_return(body: File.read(FIXTURE_UNIT_RECORD_PATH))

    stub_request(:get, %r{/apps/rd5Control/handle.php\?.*action=unitQuery})
      .to_return(body: File.read(FIXTURE_UNIT_QUERY_PATH_0))
  end

  describe ".user_tokens" do
    it "returns user tokens" do
      stub_request(:get, %r{/apps/rd5Control/handle.php\?.*action=unitQuery})
        .to_return(body: File.read(FIXTURE_UNIT_QUERY_PATH))

      tokens = described_class.user_tokens(login: "myhome", password: "secret")
      expect(tokens).to include(:user_id, :unit_id, :sid)
    end
  end

  describe "#call" do
    it "raise error when login failed" do
      duplex.logger = Logger.new(StringIO.new, level: Logger::INFO)
      stub_request(:post, %r{/apps/rd5Control/handle.php.*action=unitLogin})
        .to_return(status: 200, body: "<root><sended time='1'></sended></root>")

      expect { duplex.call }.to raise_error(AtreaControl::Error)
    end
  end

  describe "safe transport" do
    subject(:login) { described_class.new(login: "secret-user", password: "secret-password") }

    let(:output) { StringIO.new }

    before do
      login.logger = Logger.new(output, level: Logger::DEBUG)
      stub_request(:post, /\?action=login/)
        .to_return(status: 302, headers: { "Set-Cookie" => "PHPSESSID=secret-cookie" })
      stub_request(:get, %r{core/core.php\?.*action=init})
        .to_return(body: '<root><client id="987654321" name="secret-name"/></root>')
      stub_request(:get, /handle.php\?.*action=unitQuery/)
        .to_return(body: '<root><login sid="secret-sid"/>secret-password secret-cookie</root>')
    end

    it "accepts the portal login redirect without leaking secrets at DEBUG" do
      expect(login.call[:sid]).to eq("secret-sid")
      expect(output.string).not_to match(/secret-|987654321|auth=|PHPSESSID/)
    end

    context "when unit login is required" do
      before do
        stub_request(:get, /handle.php\?.*action=unitQuery/)
          .to_return(body: '<root><login sid="0"/></root>')
          .then.to_return(body: '<root><login sid="secret-sid"/>secret-password secret-cookie</root>')
        stub_request(:post, /handle.php.*action=unitLogin/).to_return(body: '<root><sended time="1"/></root>')
      end

      it "preserves successful polling without logging secrets" do
        expect(login.call[:sid]).to eq("secret-sid")
        expect(output.string).not_to match(/secret-|987654321|auth=|PHPSESSID/)
      end
    end

    context "when the server requires the browser's synchronous handshake" do
      before do
        connected = false
        stub_request(:get, /handle.php\?.*action=unitQuery/).to_return do
          { body: connected ? '<root><login sid="secret-sid"/></root>' : '<root><login sid="0"/></root>' }
        end
        stub_request(:post, /handle.php.*action=unitLogin/).to_return(body: '<root><sended time="1"/></root>')
        stub_request(:post, /handle.php.*action=unitLogin/)
          .with(query: hash_including("Sync" => "1"), body: { "comm" => "config/login.cgi?magic=" },
                headers: { "App-name" => "rd5Control", "Cookie" => "PHPSESSID=secret-cookie" })
          .to_return do
            connected = true
            { body: '<root><sended time="1"/></root>' }
          end
      end

      it "establishes the unit session before the deadline" do
        expect(login.call[:sid]).to eq("secret-sid")
      end
    end

    it "logs no secrets when unit login fails" do
      stub_request(:get, /handle.php\?.*action=unitQuery/).to_return(body: '<root><login sid="0"/>secret-sid secret-cookie secret-password</root>')
      stub_request(:post, /handle.php.*action=unitLogin/)
        .to_return(body: '<root><sended time="0"/></root>')

      expect { login.call }.to raise_error(AtreaControl::Error)
      expect(output.string).not_to match(/secret-|987654321|auth=|PHPSESSID/)
    end

    [401, 403].each do |status|
      it "classifies portal HTTP #{status} as rejected authentication" do
        stub_request(:post, /\?action=login/).to_return(status: status, body: "secret-password")

        expect { login.call }.to raise_error(AtreaControl::AuthenticationError) { |error|
          expect(error.full_message).not_to include("secret-")
          expect(error.cause).to be_nil
        }
      end
    end

    [429, 500, 302].each do |status|
      it "rejects HTTP #{status} outside the credential POST" do
        stub_request(:get, %r{core/core.php\?.*action=init}).to_return(status: status, body: "secret-cookie")

        expect { login.call }.to raise_error(AtreaControl::TransportError)
        expect(output.string).not_to include("secret-")
      end
    end

    [Faraday::ConnectionFailed, Faraday::TimeoutError].each do |failure|
      it "sanitizes login #{failure}" do
        stub_request(:post, /\?action=login/).to_raise(failure.new("secret-password secret-cookie secret-sid"))

        expect { login.call }.to raise_error(AtreaControl::TransportError) { |error|
          expect(error.full_message).not_to include("secret-")
          expect(error.cause).to be_nil
        }
      end
    end

    it "configures finite default timeouts" do
      login.call

      expect(login.send(:connection).options.to_h).to include(open_timeout: 10, timeout: 60)
    end

    it "classifies portal connect timeouts without leaking their cause" do
      stub_request(:post, /\?action=login/).to_timeout

      expect { login.call }.to raise_error(AtreaControl::UnitConnectionTimeout) { |error|
        expect(error.cause).to be_nil
      }
    end

    it "exposes timeout overrides through user_tokens" do
      client = described_class.new(login: "user", password: "password", open_timeout: 2, read_timeout: 5)
      expect(client.send(:connection).options.to_h).to include(open_timeout: 2, timeout: 5)
      expect(described_class.user_tokens(login: "user", password: "password", open_timeout: 2, read_timeout: 5))
        .to include(sid: "secret-sid")
    end
  end
end
