# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Blocking HTTP total budgets" do # rubocop:disable RSpec/DescribeClass
  let(:endpoint) { "#{AtreaControl::Duplex::CONTROL_URI}/comm/sw/unit.php" }
  let(:request_options) { { user_id: 1, unit_id: 2, sid: "private-token" } }

  it "interrupts a blocked unit response within a shorter total timeout" do # rubocop:disable RSpec/ExampleLength
    stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_return do
      Kernel.sleep(0.5)
      { body: "late" }
    end
    request = AtreaControl::Duplex::Request.new(**request_options, timeout: 0.02)
    expect { request.call(_w: 1) }.to raise_error(AtreaControl::UnitConnectionTimeout)
    expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_w" => "1")).once
  end

  it "interrupts blocked authentication within the whole login budget" do # rubocop:disable RSpec/ExampleLength
    stub_request(:post, /action=login/).to_return do
      Kernel.sleep(0.5)
      { status: 403 }
    end
    login = AtreaControl::Duplex::Login.new(login: "private", password: "private", timeout: 0.02)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { login.call }.to raise_error(AtreaControl::UnitConnectionTimeout)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.4
  end

  it "rejects login budgets above five minutes" do
    expect { AtreaControl::Duplex::Login.new(login: "private", password: "private", timeout: 301) }.to raise_error(ArgumentError, /300/)
  end

  it "caps each login HTTP operation independently of the five-minute flow" do # rubocop:disable RSpec/ExampleLength
    stub_const("AtreaControl::Duplex::Login::HTTP_TIMEOUT", 0.02)
    stub_request(:post, /action=login/).to_return do
      Kernel.sleep(0.5)
      { status: 403 }
    end
    login = AtreaControl::Duplex::Login.new(login: "private", password: "private")
    expect { login.call }.to raise_error(AtreaControl::UnitConnectionTimeout, /status=timeout/)
  end

  it "wraps default unit operations in a sixty-second total budget" do
    stub_request(:get, endpoint).with(query: hash_including("_user" => "1")).to_return(body: "ok")
    expect(Timeout).to receive(:timeout).with(60, Timeout::Error).and_call_original
    expect(AtreaControl::Duplex::Request.new(**request_options).call.body).to eq("ok")
  end

  it "rejects unit budgets above sixty seconds" do
    expect { AtreaControl::Duplex::Request.new(**request_options, timeout: 61) }.to raise_error(ArgumentError, /60/)
  end

  %i[timeout open_timeout read_timeout].each do |key|
    [0, -1, Float::INFINITY, Float::NAN, nil, "1"].each do |value|
      it "rejects invalid unit #{key}=#{value.inspect}" do
        expect { AtreaControl::Duplex::Request.new(**request_options, key => value) }.to raise_error(ArgumentError)
      end
    end
  end

  it "uses stock net_http and finite adapter defaults for both clients" do # rubocop:disable RSpec/ExampleLength
    clients = [AtreaControl::Duplex::Request.new(**request_options), AtreaControl::Duplex::Login.new(login: "private", password: "private")]
    clients.each do |client|
      expect(client.send(:connection).builder.adapter).to eq(Faraday::Adapter::NetHttp)
      expect(client.send(:connection).options.open_timeout).to eq(10)
      expect(client.send(:connection).options.timeout).to eq(60)
    end
  end

  context "with blocked TLS setup through real Faraday and Net::HTTP" do
    let(:tcp) { instance_double(TCPSocket, setsockopt: 0) }
    let(:tls) { instance_double(OpenSSL::SSL::SSLSocket, :sync_close= => nil, :hostname= => nil) }

    before do
      WebMock::HttpLibAdapters::NetHttpAdapter.disable!
      allow(TCPSocket).to receive(:open).and_return(tcp)
      allow(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp, instance_of(OpenSSL::SSL::SSLContext)).and_return(tls)
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap do |http|
          allow(http).to receive(:ssl_socket_connect) { Kernel.sleep(0.2) }
        end
      end
    end

    after { WebMock::HttpLibAdapters::NetHttpAdapter.enable! }

    %i[unit login_flow login_http].each do |operation|
      context "when #{operation} total timeout interrupts TLS connect" do
        let(:client) do
          if operation == :unit
            AtreaControl::Duplex::Request.new(**request_options, timeout: 0.02)
          else
            AtreaControl::Duplex::Login.new(login: "private", password: "private", timeout: operation == :login_flow ? 0.02 : 300)
          end
        end

        before do
          stub_const("AtreaControl::Duplex::Login::HTTP_TIMEOUT", 0.02) if operation == :login_http
          client.logger = Logger.new(nil)
        end

        it "closes the unassigned TLS socket immediately on timeout" do
          expect(tls).to receive(:close).once
          expect { client.call }.to raise_error(AtreaControl::UnitConnectionTimeout)
        end
      end
    end
  end
end
