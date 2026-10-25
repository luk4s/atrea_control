# frozen_string_literal: true

require "stringio"
require_relative "../../support/login_clock"

RSpec.describe AtreaControl::Duplex::Login do
  include_context "with login clock"

  let(:options) { {} }
  let(:client) { described_class.new(login: "private-user", password: "private-password", **options) }
  let(:output) { StringIO.new }

  def query_url = /handle.php\?.*action=unitQuery/
  def connect_url = /handle.php\?.*action=unitLogin/
  def list_url = /data.php\?.*action=getdata/
  def record_url = /data.php\?.*action=getrecord/
  def auth_url = /\?action=login/
  def init_url = %r{core/core.php\?.*action=init}

  before do
    client.logger = Logger.new(output, level: Logger::INFO)
    stub_request(:post, auth_url).to_return(headers: { "Set-Cookie" => "PHPSESSID=private-cookie" })
    stub_request(:get, init_url).to_return(body: '<root><client id="123"/></root>')
    stub_request(:get, list_url).to_return(body: '<root><data><table><i unit="11" id="71"/><i unit="22" id="72"/></table></data></root>')
    stub_request(:get, /[?&]id=11&/).to_return(body: '<root><datarecord><table><i ident="first"/></table></datarecord></root>')
    stub_request(:get, /[?&]id=22&/).to_return(body: '<root><datarecord><table><i ident="second"/></table></datarecord></root>')
    stub_request(:get, query_url).to_return(body: '<root><login sid="ready"/></root>')
    stub_request(:post, connect_url).to_return(body: '<root><sended time="1"/></root>')
  end

  describe "offline HTTP bootstrap" do
    it "blocks unstubbed Faraday requests through WebMock" do
      expect { Faraday.get("https://offline.invalid") }.to raise_error(WebMock::NetConnectNotAllowedError)
    end

    it "blocks raw sockets even when an HTTP adapter is not intercepted" do
      expect { Socket.new(Socket::AF_INET, :STREAM, 0) }.to raise_error(RuntimeError, "Unstubbed network socket")
    end
  end

  describe "failure diagnostics without DEBUG" do
    [[:post, :auth_url, "authentication"], [:get, :init_url, "client"], [:get, :list_url, "unit_list"],
     [:get, :record_url, "unit_record"], [:get, :query_url, "session_query"], [:post, :connect_url, "unit_login"]].each do |method, endpoint, stage|
      context "when #{stage} fails" do
        before do
          stub_request(:get, query_url).to_return(body: '<root><login sid="0"/></root>') if endpoint == :connect_url
        end

        [[Faraday::ConnectionFailed, AtreaControl::TransportError, "connection_failed"],
         [Faraday::TimeoutError, AtreaControl::UnitConnectionTimeout, "timeout"]].each do |failure, error_class, status|
          it "includes fixed stage and #{status} in exception with no raw cause" do
            stub_request(method, public_send(endpoint)).to_raise(failure.new("private-password private-cookie https://private.invalid"))

            expect { client.call }.to raise_error(error_class, /stage=#{stage} status=#{status}/) { |error|
              expect(error.cause).to be_nil
              expect(error.full_message).not_to match(/private-|https?:|PHPSESSID/)
            }
          end

          it "emits sanitized #{status} diagnostic at INFO logger level" do
            stub_request(method, public_send(endpoint)).to_raise(failure.new("private-password private-cookie https://private.invalid"))

            expect { client.call }.to raise_error(error_class)
            expect(output.string).to include("WARN", "stage=#{stage} status=#{status}", "elapsed=", "pollcount=")
            expect(output.string).not_to match(/private-|https?:|PHPSESSID/)
          end
        end

        [[500, AtreaControl::TransportError], [403, AtreaControl::AuthenticationError]].each do |status, error_class|
          it "retains stage and HTTP #{status} when response is rejected" do
            stub_request(method, public_send(endpoint)).to_return(status: status, body: "private-password")

            expect { client.call }.to raise_error(error_class, /stage=#{stage} status=#{status}/) { |error| expect(error.cause).to be_nil }
            expect(output.string).to include("WARN", "stage=#{stage} status=#{status}")
          end
        end
      end
    end
  end

  describe "account validation" do
    [nil, "PHPSESSID=", "OTHER=private-cookie"].each do |cookie|
      it "rejects missing or empty session cookie #{cookie.inspect}" do
        stub_request(:post, auth_url).to_return(headers: cookie ? { "Set-Cookie" => cookie } : {})

        expect { client.call }.to raise_error(AtreaControl::ProtocolError, /session cookie/)
      end
    end

    it "classifies an explicitly returned login form as authentication rejection" do
      stub_request(:post, auth_url).to_return(body: '<html><form id="loginFrm"></form></html>')

      expect { client.call }.to raise_error(AtreaControl::AuthenticationError, /stage=authentication status=200/)
    end

    ["<root/>", "<root><client/></root>", '<root><client id=" "/></root>', '<root><client id=" 123 "/></root>', '<root><client id="123"></root>'].each do |body|
      it "rejects malformed client response #{body}" do
        stub_request(:get, init_url).to_return(body: body)

        expect { client.call }.to raise_error(AtreaControl::ProtocolError) { |error| expect(error.cause).to be_nil }
      end
    end

    it "rejects external entity documents without exposing source text" do
      stub_request(:get, init_url).to_return(body: '<!DOCTYPE root [<!ENTITY x SYSTEM "file:///private-secret">]><root><client id="&x;"/></root>')

      expect { client.call }.to raise_error(AtreaControl::ProtocolError) { |error|
        expect(error.full_message).not_to include("private-secret")
      }
    end
  end

  describe "listed unit selection" do
    it "defaults to first listed entry and caches discovery" do
      expect(client.call).to eq(user_id: "123", unit_id: "first", sid: "ready")
      expect(WebMock).to have_requested(:get, /[?&]id=11&/).once
      expect(WebMock).not_to have_requested(:get, /[?&]id=22&/)
    end

    context "with requested ident" do
      let(:options) { { unit_id: "second" } }

      before do
        stub_request(:get, query_url).to_return(body: '<root><login sid="0"/></root>').then.to_return(body: '<root><login sid="ready"/></root>')
        stub_request(:post, connect_url).with(query: hash_including("unit" => "second", "idPwd" => "72")).to_return(body: '<root><sended time="1"/></root>')
      end

      it "resolves list primary keys and uses matching ident and account row" do
        expect(client.call[:unit_id]).to eq("second")
        expect(WebMock).to have_requested(:get, /[?&]id=11&/).once
        expect(WebMock).to have_requested(:get, /[?&]id=22&/).once
      end
    end

    context "with unlisted ident" do
      let(:options) { { unit_id: "private-unlisted" } }

      it "fails safely after resolving only listed records" do
        expect { client.call }.to raise_error(AtreaControl::ProtocolError, /No matching unit/) { |error|
          expect(error.message).not_to include("private-unlisted")
        }
        expect(WebMock).to have_requested(:get, record_url).twice
      end
    end

    context "with ambiguous matching ident" do
      let(:options) { { unit_id: "first" } }

      before do
        stub_request(:get, list_url).to_return(body: '<root><data><table><i unit="11" id="71"/><i unit="11" id="72"/></table></data></root>')
      end

      it "rejects ambiguity while fetching repeated record only once" do
        expect { client.call }.to raise_error(AtreaControl::ProtocolError, /Multiple matching units/)
        expect(WebMock).to have_requested(:get, /[?&]id=11&/).once
      end
    end

    it "does not discover units after positively rejected authentication" do
      stub_request(:post, auth_url).to_return(status: 403)

      expect { client.call }.to raise_error(AtreaControl::AuthenticationError)
      expect(WebMock).not_to have_requested(:get, list_url)
    end

    ["<root/>", "<root><data><table/></data></root>", '<root><data><table><i id="71"/></table></data></root>',
     '<root><data><table><i unit="11"/></table></data></root>'].each do |body|
      it "rejects missing unit list entries or attributes #{body}" do
        stub_request(:get, list_url).to_return(body: body)

        expect { client.call }.to raise_error(AtreaControl::ProtocolError)
      end
    end

    ["<root/>", "<root><datarecord><table><i/></table></datarecord></root>", '<root><datarecord><table><i ident=" "/></table></datarecord></root>',
     '<root><datarecord><table><i ident=" first "/></table></datarecord></root>'].each do |body|
      it "rejects missing record ident #{body}" do
        stub_request(:get, record_url).to_return(body: body)

        expect { client.call }.to raise_error(AtreaControl::ProtocolError)
      end
    end
  end

  describe "session response validation" do
    ["<root/>", "<root><login/></root>", '<root><login sid=" "/></root>', '<root><login sid=" 0 "/></root>', '<root><login sid="ready"></root>'].each do |body|
      it "rejects malformed login response #{body}" do
        stub_request(:get, query_url).to_return(body: body)

        expect { client.call }.to raise_error(AtreaControl::ProtocolError)
      end
    end

    it "requires sended node when connecting" do
      stub_request(:get, query_url).to_return(body: '<root><login sid="0"/></root>')
      stub_request(:post, connect_url).to_return(body: "<root/>")

      expect { client.call }.to raise_error(AtreaControl::ProtocolError)
    end
  end

  describe "whole-flow deadline" do
    let(:options) { { timeout: 2.5, poll_interval: 1 } }

    before do
      stub_request(:get, query_url).to_return(body: '<root><login sid="0"/></root>')
    end

    ["0", "invalid", "999999", nil].each do |estimate|
      it "ignores diagnostic ETA #{estimate.inspect} and succeeds on last permitted poll" do
        stub_request(:post, connect_url).to_return(body: "<root><sended #{"time='#{estimate}'" if estimate}/></root>")
        stub_request(:get, query_url).to_return(body: '<root><login sid="0"/></root>').times(3).then.to_return(body: '<root><login sid="ready"/></root>')

        expect(client.call[:sid]).to eq("ready")
        expect(clock.first).to eq(2.0)
      end
    end

    it "times out perpetual SID zero without calling it bad credentials" do
      expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout)
      expect(clock.first).to eq(2.5)
      expect(WebMock).to have_requested(:get, query_url).times(4)
    end

    it "logs stage, elapsed time and poll count at deadline without identifiers" do
      output = StringIO.new
      client.logger = Logger.new(output, level: Logger::INFO)

      expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout, /stage=session_query status=deadline_exceeded/)
      expect(output.string).to include("stage=session_query status=deadline_exceeded elapsed=2.5 pollcount=4")
      expect(output.string).not_to match(/private-|https?:|PHPSESSID|unit=|user=/)
    end

    context "with interval larger than budget" do
      let(:options) { { timeout: 0.5, poll_interval: 100 } }

      it "clamps sleep to remaining budget" do
        expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout)
        expect(clock.first).to eq(0.5)
      end
    end

    context "when polling sleep blocks" do
      let(:options) { { timeout: 0.02, poll_interval: 1 } }

      it "interrupts sleep using the whole-flow timeout" do
        allow(Kernel).to receive(:sleep).and_call_original
        expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout, /deadline_exceeded/)
        expect(clock.first).to eq(0)
      end
    end

    { auth_url: "authentication", init_url: "client", list_url: "unit_list", record_url: "unit_record", connect_url: "unit_login" }.each do |endpoint, stage|
      context "when budget expires during #{endpoint}" do
        before do
          expire_during(endpoint)
        end

        it "stops before further requests" do
          expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout, /stage=#{stage} status=deadline_exceeded/) { |error| expect(error.cause).to be_nil }
          expect(WebMock).to have_requested(:get, query_url).times(endpoint == :connect_url ? 1 : 0)
        end
      end
    end

    def expire_during(endpoint)
      method = %i[auth_url connect_url].include?(endpoint) ? :post : :get
      stub_request(method, public_send(endpoint)).to_return do
        clock[0] += 3
        { body: "<root/>", headers: { "Set-Cookie" => "PHPSESSID=private-cookie" } }
      end
    end

    it "rejects successful SID arriving beyond deadline" do
      stub_request(:get, query_url).to_return do
        clock[0] += 3
        { body: '<root><login sid="ready"/></root>' }
      end

      expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout)
    end

    [Net::OpenTimeout, Net::ReadTimeout].each do |failure|
      it "classifies lower adapter #{failure} without exposing cause" do
        stub_request(:post, auth_url).to_raise(failure.new("private-password private-cookie"))

        expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout) { |error|
          expect(error.cause).to be_nil
          expect(error.full_message).not_to include("private-")
        }
      end
    end

    [SocketError, EOFError].each do |failure|
      it "sanitizes native transport #{failure}" do
        stub_request(:post, auth_url).to_raise(failure.new("private-user private-cookie"))

        expect { client.call }.to raise_error(AtreaControl::TransportError) { |error|
          expect(error.cause).to be_nil
          expect(error.full_message).not_to include("private-")
        }
      end
    end

    context "when authentication consumes most of budget" do
      before do
        stub_request(:post, auth_url).to_return do
          clock[0] += 2
          { headers: { "Set-Cookie" => "PHPSESSID=private-cookie" } }
        end
        stub_request(:get, query_url).to_return(body: '<root><login sid="ready"/></root>')
      end

      it "clamps HTTP open and read timeouts to current remaining budget" do
        client.call
        expect(client.send(:connection).options.open_timeout).to be <= 0.5
        expect(client.send(:connection).options.timeout).to be <= 0.5
      end
    end
  end

  describe "configuration" do
    it "defaults the whole login flow to five minutes" do
      stub_request(:get, query_url).to_return(body: '<root><login sid="0"/></root>')
      expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout)
      expect(clock.first).to eq(300)
    end

    %i[timeout poll_interval open_timeout read_timeout].each do |key|
      [0, -1, Float::INFINITY, Float::NAN, nil, "1"].each do |value|
        it "rejects invalid #{key}=#{value.inspect} before network" do
          expect { described_class.user_tokens(login: "user", password: "password", key => value) }.to raise_error(ArgumentError)
          expect(WebMock).not_to have_requested(:post, auth_url)
        end
      end
    end

    it "exposes selection and polling settings through user_tokens" do
      expect(described_class.user_tokens(login: "user", password: "password", unit_id: "second", timeout: 3, poll_interval: 0.2))
        .to eq(user_id: "123", unit_id: "second", sid: "ready")
    end
  end
end
