# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require_relative "../../support/user_ctrl"
require_relative "../../support/login_clock"

RSpec.describe AtreaControl::Duplex::Unit do
  subject(:unit) { described_class.new(user_id: 1234, unit_id: "private-unit", sid: "private-sid", user_ctrl: user_ctrl, verification_registers: mapping) }

  include_context "userCtrl"
  include_context "with login clock"

  let(:mapping) { { power: "H19990", mode: "H19991" } }
  let(:now) { Time.local(2026, 1, 15, 12) }
  let(:reads) { [xml, xml(offset: 1, power: 40, mode: 2)] }
  let(:endpoint) { "#{AtreaControl::Duplex::CONTROL_URI}/comm/sw/unit.php" }
  let(:ack) { "unconfirmed application response" }

  def xml(offset: 0, power: 0, mode: 0)
    document = Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/unit.xml")))
    document.root["t"] = (now + offset).strftime("%Y-%m-%d %H:%M:%S")
    { "H10510" => 1, "C10508" => 0, "C10509" => 1, "H11700" => 1, "I11401" => 1,
      "H19990" => power, "H19991" => mode, }.each do |id, value|
      node = document.at_xpath("//O[@I='#{id}']") || document.at_xpath("/RD5WEB/RD5/*").add_child("<O I='#{id}'/>").first
      node["V"] = value.to_s
    end
    document.to_xml
  end

  before do
    allow(Time).to receive(:now) { now + clock.first }
    stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_return { { body: reads.size > 1 ? reads.shift : reads.first } }
    stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_return(body: ack)
  end

  def expect_one_write
    expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_w" => "1")).once
  end

  def expect_no_write
    expect(WebMock).not_to have_requested(:get, endpoint).with(query: hash_including("_w" => "1"))
  end

  %i[power mode].each do |setting|
    it "returns normalized #{setting} only after fresh raw requested readback" do
      expect(unit.public_send(:"set_#{setting}", setting == :power ? "040" : 2.0)).to eq(setting == :power ? 40 : 2)
      expect_one_write
      expect(unit.mode).to eq("CO2")
    end

    it "keeps default #{setting} verification unsupported before write" do
      plain = described_class.new(user_id: 1, unit_id: 2, sid: 3, user_ctrl: user_ctrl)
      expect { plain.public_send(:"set_#{setting}", 2) }.to raise_error(AtreaControl::UnsupportedConfiguration)
      expect_no_write
    end

    it "returns transport response for unverified #{setting} without polling" do
      expect(unit.public_send(:"set_#{setting}", 2, verify: false).body).to eq(ack)
      expect_one_write
      expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).once
    end

    it "delegates legacy #{setting}= to unverified API" do
      expect(unit).to receive(:"set_#{setting}").with(2, verify: false).and_call_original # rubocop:disable RSpec/SubjectStub
      expect(unit.public_send(:"#{setting}=", 2).body).to eq(ack)
    end
  end

  [{}, { unknown: "H19990" }, { "power" => "H19990" }, { power: "H1234" }, { power: "I19990" }, { power: nil }, []].each do |invalid|
    it "rejects invalid explicit register map #{invalid.inspect}" do
      expect { described_class.new(user_id: 1, unit_id: 2, sid: 3, verification_registers: invalid) }.to raise_error(ArgumentError)
    end
  end

  it "copies caller map and register strings without freezing caller objects" do # rubocop:disable RSpec/ExampleLength
    register = +"H19990"
    mapping[:power] = register
    unit
    register.replace("H19992")
    mapping.clear
    expect(unit.set_power(40)).to eq(40)
    expect(register).not_to be_frozen
    expect(mapping).not_to be_frozen
  end

  it "requires capability for requested setting in partial map" do
    mapping.delete(:power)
    expect { unit.set_power(40) }.to raise_error(AtreaControl::UnsupportedConfiguration)
    expect_no_write
  end

  { timeout: [0, -1, Float::INFINITY, Float::NAN, "1", nil], poll_interval: [0, -1, Float::INFINITY, Float::NAN, "1", nil] }.each do |key, invalids|
    invalids.each do |invalid|
      it "rejects #{key}=#{invalid.inspect} before requests" do
        expect { unit.set_power(40, **{ key => invalid }) }.to raise_error(ArgumentError)
        expect(WebMock).not_to have_requested(:get, endpoint)
      end
    end
  end

  %i[timeout poll_interval].each do |key|
    it "rejects invalid #{key} even with verification disabled before writing" do
      expect { unit.set_power(40, verify: false, **{ key => 0 }) }.to raise_error(ArgumentError)
      expect_no_write
    end
  end

  it "rejects a mode outside domain before writing" do
    expect { unit.set_mode(8) }.to raise_error(ArgumentError)
    expect_no_write
  end

  it "uses baseline schedule policy instead of cached configuration" do
    unit.values
    reads.replace([xml.sub('I="C10508" V="0"', 'I="C10508" V="1"')])
    expect { unit.set_mode(1) }.to raise_error(AtreaControl::UnsupportedConfiguration)
    expect_no_write
  end

  it "reports baseline timeout without claiming a dispatched command" do
    stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_timeout
    expect { unit.set_power(40) }.to raise_error(AtreaControl::UnitConnectionTimeout)
    expect_no_write
  end

  it "rejects missing readback register after write as protocol error" do
    reads.replace([xml, xml(offset: 1).gsub(%r{<O I="H19990"[^>]*/>}, "")])
    expect { unit.set_power(40) }.to raise_error(AtreaControl::ProtocolError)
    expect_one_write
  end

  it "propagates readback authentication rejection without replay" do
    stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_return(body: xml).then.to_return(status: 403)
    expect { unit.set_power(40) }.to raise_error(AtreaControl::SessionExpired)
    expect_one_write
  end

  it "rejects domain before write" do
    expect { unit.set_power(101) }.to raise_error(ArgumentError)
    expect_no_write
  end

  it "rejects malformed command before reads" do
    expect { unit.set_power("40&x") }.to raise_error(ArgumentError)
    expect(WebMock).not_to have_requested(:get, endpoint)
  end

  it "takes fresh baseline even when cached snapshot matches" do
    reads.unshift(xml(offset: -1, power: 40))
    unit.values
    expect(unit.set_power(40)).to eq(40)
    expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).times(3)
  end

  it "does not confirm matching baseline timestamp" do
    reads.replace([xml(power: 40)])
    expect { unit.set_power(40, timeout: 7, poll_interval: 5) }.to raise_error(AtreaControl::WriteNotConfirmed, /outcome unknown/)
    expect(clock.first).to eq(7)
    expect_one_write
  end

  it "polls delayed propagation and external override without replaying command" do
    reads.replace([xml, xml(offset: 1, power: 88), xml(offset: 2, power: 40)])
    expect(unit.set_power(40)).to eq(40)
    expect(clock.first).to eq(5)
    expect_one_write
  end

  it "does not confuse actual airflow with requested power" do
    reads.replace([xml, xml(offset: 1)])
    expect { unit.set_power(88, timeout: 2) }.to raise_error(AtreaControl::WriteNotConfirmed)
    expect_one_write
  end

  it "rejects missing readback capability in baseline before writing" do
    mapping[:power] = "H19992"
    expect { unit.set_power(40) }.to raise_error(AtreaControl::UnsupportedConfiguration)
    expect_no_write
  end

  { "malformed" => AtreaControl::ProtocolError, "" => AtreaControl::ProtocolError }.each do |body, error|
    it "propagates #{error} from readback without replay" do
      reads.replace([xml, body])
      expect { unit.set_power(40) }.to raise_error(error)
      expect_one_write
    end
  end

  it "rejects expired readback even when value matches" do
    reads.replace([xml, xml(offset: -901, power: 40)])
    expect { unit.set_power(40) }.to raise_error(AtreaControl::SessionExpired)
    expect_one_write
  end

  [403, 500].each do |status|
    it "propagates write HTTP #{status} without replay" do
      stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_return(status: status)
      expect { unit.set_power(40) }.to raise_error(status == 403 ? AtreaControl::SessionExpired : AtreaControl::TransportError)
      expect_one_write
    end
  end

  it "reports unknown outcome on write timeout without leaking tokens or retrying" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_timeout
    expect { unit.set_power(40) }.to raise_error(AtreaControl::WriteNotConfirmed) do |error|
      expect(error.message).to include("outcome unknown")
      expect(error.message).not_to include("private")
      expect(error.cause).to be_nil
    end
    expect_one_write
  end

  it "shares one budget across baseline, write, readback and waits" do # rubocop:disable RSpec/ExampleLength
    stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_return do
      clock[0] += 1
      { body: xml }
    end
    stub_request(:get, endpoint).with(query: hash_including("_w" => "1")).to_return do
      clock[0] += 1
      { body: ack }
    end
    expect { unit.set_power(40, timeout: 4, poll_interval: 5) }.to raise_error(AtreaControl::WriteNotConfirmed)
    expect(clock.first).to eq(4)
    expect_one_write
  end

  context "with blocked HTTP responses" do
    before { allow(Kernel).to receive(:sleep).and_call_original }

    def block_response(query, body)
      stub_request(:get, endpoint).with(query: hash_including(query)).to_return do
        Kernel.sleep(0.5)
        { body: body }
      end
    end

    it "interrupts baseline and retains failure until explicit refresh" do
      block_response({ "_t" => "config/xml.xml" }, xml).then.to_return(body: xml(offset: 1, power: 40))
      expect { unit.set_power(40, timeout: 0.1) }.to raise_error(AtreaControl::UnitConnectionTimeout)
      expect { unit.values }.to raise_error(AtreaControl::UnitConnectionTimeout)
      expect(unit.refresh![:current_power]).to eq(88)
      expect_no_write
    end

    it "interrupts write response with unknown outcome and no replay" do
      block_response({ "_w" => "1" }, ack)
      expect { unit.set_power(40, timeout: 0.1) }.to raise_error(AtreaControl::WriteNotConfirmed)
      expect_one_write
    end

    it "interrupts readback with unknown outcome and no replay" do # rubocop:disable RSpec/ExampleLength
      count = 0
      stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_return do
        count += 1
        Kernel.sleep(0.5) if count > 1
        { body: xml(offset: count - 1, power: 40) }
      end
      expect { unit.set_power(40, timeout: 0.1) }.to raise_error(AtreaControl::WriteNotConfirmed)
      expect_one_write
    end

    context "with lazy configuration discovery" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:user_ctrl) { AtreaControl::Duplex::UserCtrl.new(user_id: 1234, unit_id: "private-unit", sid: "private-sid") }

      it "includes discovery in the aggregate baseline budget" do
        stub_request(:get, endpoint).with(query: hash_including("_t" => "config/texts.xml")).to_return(body: File.read(File.join(__dir__, "../../fixtures/files/texts.xml")))
        block_response({ "_t" => "lang/userCtrl.xml" }, File.read(File.join(__dir__, "../../fixtures/files/userCtrl.xml")))
        expect { unit.set_power(40, timeout: 0.1) }.to raise_error(AtreaControl::UnitConnectionTimeout)
        expect_no_write
      end
    end
  end
end
