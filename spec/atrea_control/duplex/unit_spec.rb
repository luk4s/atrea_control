# frozen_string_literal: true

require_relative "../../support/user_ctrl"

RSpec.describe AtreaControl::Duplex::Unit do
  subject(:unit) { described_class.new user_id: user_id, unit_id: unit_id, sid: sid, user_ctrl: user_ctrl }

  include_context "userCtrl"

  let(:user_id) { "1234" }
  let(:unit_id) { "123456789" }
  let(:sid) { "4012" }
  let(:request) { instance_double(AtreaControl::Duplex::Request) }

  before do
    allow(unit).to receive(:request).and_return(request)
    allow(unit).to receive(:valid?).and_return(true)
  end

  describe "#name" do
    it "delegate to userCtrl" do
      expect(unit.name).to eq "Byt 007"
    end
  end

  describe "#values" do
    before do
      fixture = File.join(__dir__, "../../fixtures/files/unit.xml")
      expect(request).to receive(:call).with(_t: "config/xml.xml").and_return spy(body: File.read(fixture))
    end

    it "stub xml" do
      expect(unit.values).to include current_power: 88.0, outdoor_temperature: 9.3
    end

    describe "#to_json" do
      it "parsed json" do
        json = JSON.parse(unit.to_json)
        expect(json).to include("current_power" => 88.0, "outdoor_temperature" => 9.3)
      end
    end

    it "#power" do
      expect(unit.power).to eq 88.0
    end

    it "#mode" do
      expect(unit.mode).to eq "CO2"
    end

    it "preheating?" do
      expect(unit.preheating?).to be true
    end

    describe "#timestamp" do
      subject(:timestamp) { unit.timestamp }

      it { is_expected.to be_a Time }
      it { is_expected.to eq Time.parse("2021-10-26 21:45:51") }
    end
  end

  describe "validated commands" do
    let(:xml) { Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/unit.xml"))) }

    def register(id, value)
      node = xml.at_xpath("//O[@I='#{id}']")
      unless node
        node = Nokogiri::XML::Node.new("O", xml)
        node["I"] = id
        xml.at_xpath("/RD5WEB/RD5/*").add_child(node)
      end
      value.nil? ? node.remove : node["V"] = value.to_s
    end

    before do
      register("H10510", 1)
      register("C10508", 0)
      register("C10509", 1)
      register("H11700", 1)
      register("I11401", 1)
      allow(request).to receive(:call).with(_t: "config/xml.xml") { double(body: xml.to_xml) }
    end

    { power: [88, "H10708", "H10700"], mode: [1, "H10709", "H10701"] }.each do |setting, (value, input, switch)|
      [0, 1, 2].each do |state|
        (setting == :mode ? (0..7).to_a : [value, 0]).each do |setpoint|
          it "sends exact #{setting}=#{setpoint} request in control state #{state}" do
            register(switch, state)
            expected = { _t: "config/xml.cgi", _w: 1, "#{input}#{format("%05d", setpoint)}" => nil }
            expected["#{switch}00002"] = nil unless state.zero?
            expect(request).to receive(:call).with(expected).once
            unit.public_send(:"#{setting}=", setpoint)
          end
        end
      end

      [value, value.to_f, value.to_s, "00#{value}"].each do |accepted|
        it "normalizes #{setting} input #{accepted.inspect}" do
          register(switch, 0)
          expect(request).to receive(:call).with({ _t: "config/xml.cgi", _w: 1, "#{input}#{format("%05d", value)}" => nil })
          unit.public_send(:"#{setting}=", accepted)
        end
      end

      [nil, true, false, -1, -1.0, 1.5, Float::NAN, Float::INFINITY, -Float::INFINITY,
       "", "88.0", " 1", "1 ", "+1", "-1", "1e0", "１", "1\n", "1&x"].each do |invalid|
        it "rejects #{setting} syntax #{invalid.inspect} before any request or discovery" do
          expect(request).not_to receive(:call)
          expect(user_ctrl).not_to receive(:sensors)
          expect { unit.public_send(:"#{setting}=", invalid) }.to raise_error(ArgumentError)
        end
      end

      [nil, 3, 65_535].each do |state|
        it "does not write #{setting} with unknown control state #{state.inspect}" do
          register(switch, state)
          expect(request).not_to receive(:call).with(hash_including(_w: 1))
          expect { unit.public_send(:"#{setting}=", value) }.to raise_error(AtreaControl::UnsupportedConfiguration)
        end
      end

      [input, switch].each do |id|
        it "rejects invalid discovered #{id} without writing" do
          sensors[setting.to_s + (id == input ? "_input" : "_switch")] = "I12345"
          expect(request).not_to receive(:call).with(hash_including(_w: 1))
          expect { unit.public_send(:"#{setting}=", value) }.to raise_error(AtreaControl::UnsupportedConfiguration)
        end
      end

      it "rejects stale configuration before writing #{setting}" do
        unit.values
        allow(unit).to receive(:valid?).and_return(false)
        expect(request).not_to receive(:call)
        expect { unit.public_send(:"#{setting}=", value) }.to raise_error(AtreaControl::SessionExpired)
      end

      [nil, AtreaControl::UnitConnectionTimeout, AtreaControl::TransportError, AtreaControl::SessionExpired].each do |failure|
        it "invalidates prewrite #{setting} snapshot on #{failure || "success"} without retry" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
          previous = unit.configuration
          response = expect(request).to receive(:call).with(hash_including(_w: 1)).once
          failure ? response.and_raise(failure) : response.and_return(double(body: "ok"))
          if failure
            expect { unit.public_send(:"#{setting}=", value) }.to raise_error(failure)
          else
            unit.public_send(:"#{setting}=", value)
          end
          register("H10510", 2)
          expect(unit.configuration.fetch("H10510")).to eq(2)
          expect(previous.fetch("H10510")).to eq(1)
        end
      end
    end

    it "uses alternate discovered power setpoint and control switch from the same snapshot" do
      sensors.merge!("power_input" => "H10710", "power_switch" => "H10702")
      register("H10702", 1)
      expect(request).to receive(:call).with({ _t: "config/xml.cgi", _w: 1, "H1071000000" => nil, "H1070200002" => nil })
      unit.power = 0
    end

    [0, 2, 3, 4, nil, 5].each do |profile|
      it "does not write disallowed power 9 for profile #{profile.inspect}" do
        register("H10510", profile)
        expect(request).not_to receive(:call).with(hash_including(_w: 1))
        error = [nil, 3, 5].include?(profile) ? AtreaControl::UnsupportedConfiguration : ArgumentError
        expect { unit.power = 9 }.to raise_error(error)
      end
    end

    it "does not write an unavailable mode" do
      register("C10508", 1)
      expect(request).not_to receive(:call).with(hash_including(_w: 1))
      expect { unit.mode = 1 }.to raise_error(AtreaControl::UnsupportedConfiguration)
    end

    it "does not write an undiscovered mode" do
      modes.delete("2")
      expect(request).not_to receive(:call).with(hash_including(_w: 1))
      expect { unit.mode = 2 }.to raise_error(AtreaControl::UnsupportedConfiguration)
    end

    it "retains a valid snapshot when command validation rejects the value" do
      previous = unit.configuration
      expect { unit.power = 101 }.to raise_error(ArgumentError)
      expect(request).not_to receive(:call)
      expect(unit.configuration).to equal(previous)
    end
  end

  describe "#refresh!" do
    let(:parser) { instance_double(AtreaControl::SensorParser) }

    before do
      allow(unit).to receive(:read).and_return spy(body: "<xml></xml>")
      allow(unit).to receive(:parser).and_return parser
      allow(parser).to receive(:snapshot).and_return(
        { values: { "timestamp" => 1 }, configuration: nil },
        { values: { "timestamp" => 2 }, configuration: nil }
      )
    end

    it "remove cached values" do # rubocop:disable RSpec/ExampleLength
      aggregate_failures "demonstrate cache" do
        expect(unit.values).to include timestamp: 1
        expect(unit.values).to include timestamp: 1
      end
      expect(unit.refresh!).to include timestamp: 2
      expect(unit.values).to include timestamp: 2
    end
  end

  describe "validated snapshot lifecycle" do
    let(:xml) { Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/unit.xml"))) }

    def now
      Time.local(2026, 1, 15, 12, 0, 0)
    end

    def readers
      %i[values parsed current_power current_mode power mode outdoor_temperature preheat_temperature required_temperature configuration
         input_temperature preheating preheating? timestamp as_json to_json]
    end

    before do
      allow(unit).to receive(:valid?).and_call_original
      allow(Time).to receive(:now).and_return(now)
      xml.root["t"] = now.strftime("%Y-%m-%d %H:%M:%S")
      allow(request).to receive(:call).with(_t: "config/xml.xml").and_return(double(body: xml.to_xml))
    end

    def respond_with(document)
      allow(request).to receive(:call).with(_t: "config/xml.xml").and_return(double(body: document.to_xml))
    end

    def timestamp_offset(offset)
      xml.root["t"] = (now + offset).strftime("%Y-%m-%d %H:%M:%S")
      respond_with(xml)
    end

    it "reports an unloaded snapshot invalid without fetching or recursing" do
      expect(request).not_to receive(:call)
      expect(unit.valid?).to be false
    end

    it "shares one read between alias readers and immutable configuration" do
      expect(request).to receive(:call).with(_t: "config/xml.xml").once.and_return(double(body: xml.to_xml))
      expect([unit.required_temperature, unit.values[:required_temperature]]).to eq([unit.preheat_temperature, 15.0])
      expect(unit.configuration.fetch("H11300")).to eq(0)
    end

    it "validates getters with the live unpadded timestamp through its real parser" do
      current = Time.local(2026, 10, 25, 17, 7, 32)
      allow(Time).to receive(:now).and_return(current)
      xml.root["t"] = "2026-10-25 17:7:32 "
      respond_with(xml)
      expect([unit.timestamp, unit.power, unit.mode, unit.valid?]).to eq([current, 88.0, "CO2", true])
    end

    it "refreshes configuration with readings without mutating earlier configuration" do
      previous = unit.configuration
      respond_with(xml.tap { |document| document.at_xpath("//O[@I='H11300']")["V"] = "1" })
      unit.refresh!
      expect(unit.configuration.fetch("H11300")).to eq(1)
      expect(previous.fetch("H11300")).to eq(0)
    end

    %i[values parsed current_power current_mode power mode outdoor_temperature preheat_temperature required_temperature configuration
       input_temperature preheating preheating? timestamp as_json to_json].each do |reader|
      it "loads a valid snapshot through #{reader}" do
        expect(unit.public_send(reader)).not_to be_nil
        expect(unit.valid?).to be true
      end

      it "rejects initially old XML through #{reader}" do
        timestamp_offset(-901)
        expect { unit.public_send(reader) }.to raise_error(AtreaControl::SessionExpired)
      end

      it "checks aged snapshots through #{reader} without refetching" do
        unit.values
        allow(Time).to receive(:now).and_return(now + 900)
        expect(request).not_to receive(:call)
        expect { unit.public_send(reader) }.to raise_error(AtreaControl::SessionExpired)
        expect(unit.valid?).to be false
      end
    end

    { -900 => false, -899 => true, 60 => true, 61 => false }.each do |offset, accepted|
      if accepted
        it "accepts timestamp offset #{offset}" do
          timestamp_offset(offset)
          expect(unit.values[:timestamp]).to eq(now + offset)
        end
      else
        it "rejects timestamp offset #{offset}" do
          timestamp_offset(offset)
          expect { unit.values }.to raise_error(AtreaControl::SessionExpired)
        end
      end
    end

    [AtreaControl::TransportError, AtreaControl::ProtocolError, AtreaControl::SessionExpired, RuntimeError].each do |error|
      context "when refresh fails with #{error}" do
        before do
          unit.values
          allow(request).to receive(:call).and_raise(error)
          expect { unit.refresh! }.to raise_error(error)
        end

        it "invalidates all readers without implicit refetch" do
          expect(request).not_to receive(:call)
          readers.each { |reader| expect { unit.public_send(reader) }.to raise_error(error) }
          expect(unit.valid?).to be false
        end
      end
    end

    context "with a rejected snapshot" do
      before do
        unit.values
        timestamp_offset(-901)
        expect { unit.refresh! }.to raise_error(AtreaControl::SessionExpired)
      end

      it "keeps all readers invalid without refetching" do
        expect(request).not_to receive(:call)
        readers.each { |reader| expect { unit.public_send(reader) }.to raise_error(AtreaControl::SessionExpired) }
      end

      it "recovers only by explicit refresh" do
        timestamp_offset(0)
        expect(unit.refresh![:timestamp]).to eq(now)
      end
    end

    it "keeps initially expired readings out of power and JSON" do
      timestamp_offset(-901)
      expect { unit.values }.to raise_error(AtreaControl::SessionExpired)
      expect { unit.power }.to raise_error(AtreaControl::SessionExpired)
      expect { unit.as_json }.to raise_error(AtreaControl::SessionExpired)
    end

    context "when refresh receives an incomplete sensor payload" do
      before do
        unit.values
        xml.at_xpath("//O[@I='I10208']").remove
        respond_with(xml)
        expect { unit.refresh! }.to raise_error(AtreaControl::ProtocolError, /I10208/)
      end

      it "publishes neither a partial snapshot nor the previous valid one" do
        expect(request).not_to receive(:call)
        readers.each { |reader| expect { unit.public_send(reader) }.to raise_error(AtreaControl::ProtocolError) }
        expect(unit.valid?).to be false
      end
    end

    context "with zero power and no preheating" do
      before do
        xml.at_xpath("//O[@I='H10704']")["V"] = "0"
        xml.xpath("//O").select { |node| %w[C10200 C10202 C10215 C10217].include?(node["I"]) }.each { |node| node["V"] = "0" }
        respond_with(xml)
      end

      it "preserves zero and false without refetching" do
        expect(unit.power).to eq(0.0)
        expect(request).not_to receive(:call)
        expect([unit.preheating, unit.preheating?]).to eq([false, false])
      end
    end

    it "does not share the mutable symbol-keyed projection" do
      projection = unit.values
      projection[:timestamp] = now - 1000
      expect(unit.values[:timestamp]).to eq(now)
    end

    it "protects the string-keyed parsed projection" do
      expect { unit.parsed["timestamp"] = now - 1000 }.to raise_error(FrozenError)
      expect(unit.values[:timestamp]).to eq(now)
    end

    it "protects mutable snapshot values" do
      expect { unit.timestamp.localtime(3600) }.to raise_error(FrozenError)
      expect { unit.mode.replace("changed") }.to raise_error(FrozenError)
      expect(unit.mode).to eq("CO2")
    end

    it "copies timestamp assignments on a loaded snapshot" do
      assigned = now - 1
      unit.timestamp = assigned
      assigned.localtime(3600)
      expect(unit.timestamp).to eq(now - 1)
      expect(unit.timestamp.utc_offset).to eq(now.utc_offset)
    end

    it "does not let timestamp assignment resurrect a rejected snapshot" do
      timestamp_offset(-901)
      expect { unit.values }.to raise_error(AtreaControl::SessionExpired)
      expect { unit.timestamp = now }.to raise_error(AtreaControl::SessionExpired)
      expect { unit.power }.to raise_error(AtreaControl::SessionExpired)
    end

    it "passes explicit time zone to its real parser" do
      zoned = described_class.new(user_id: user_id, unit_id: unit_id, sid: sid, user_ctrl: user_ctrl, time_zone: "Europe/Prague")
      allow(zoned).to receive(:request).and_return(request)
      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 15, 11))
      expect(zoned.timestamp).to eq(Time.utc(2026, 1, 15, 11))
    end
  end
end
