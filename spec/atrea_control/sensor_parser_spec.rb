# frozen_string_literal: true

require_relative "../support/user_ctrl"

RSpec.describe AtreaControl::SensorParser do
  subject(:parser) { described_class.new(user_ctrl) }

  include_context "userCtrl"

  let(:xml) { Nokogiri::XML(File.read(File.join(__dir__, "../fixtures/files/unit.xml"))) }

  describe "command encoder" do
    { 0 => "00000", 88 => "00088", 65_535 => "65535" }.each do |value, encoded|
      it "encodes unsigned #{value} with exactly five digits" do
        expect(parser.input("H10708", value)).to eq("H10708#{encoded}")
      end
    end

    [nil, true, false, -1, 65_536, 88.0, "88", 1.5, Float::NAN, Float::INFINITY].each do |value|
      it "rejects non-uint16 encoder value #{value.inspect}" do
        expect { parser.input("H10708", value) }.to raise_error(ArgumentError)
      end
    end

    [nil, "I10708", "H1070", "H107080", "H10708\n", "H１０７０８", "H10708&evil"].each do |sensor|
      it "rejects invalid holding-register mapping #{sensor.inspect}" do
        expect { parser.input(sensor, 88) }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end
  end

  describe "explicit time zone" do
    subject(:parser) { described_class.new(user_ctrl, time_zone: "Europe/Prague") }

    {
      "2026-01-15 12:00:00" => Time.utc(2026, 1, 15, 11),
      "2026-07-15 12:00:00" => Time.utc(2026, 7, 15, 10),
      "2026-1-5 2:3:4 " => Time.utc(2026, 1, 5, 1, 3, 4),
    }.each do |local, instant|
      it "resolves #{local} independent of process time zone" do
        xml.root["t"] = local
        expect(parser.values(xml.to_xml)["timestamp"]).to eq(instant)
      end
    end

    ["2026-03-29 02:30:00", "2026-10-25 02:30:00", "2026-3-29 2:30:0", "2026-10-25 2:30:0"].each do |local|
      it "rejects nonexistent or ambiguous local time #{local}" do
        xml.root["t"] = local
        expect { parser.values(xml.to_xml) }.to raise_error(AtreaControl::ProtocolError)
      end
    end

    it "reports an invalid IANA zone as a library error" do
      expect { described_class.new(user_ctrl, time_zone: "Invalid/Zone") }.to raise_error(AtreaControl::Error)
    end
  end

  describe "#raw_values" do
    it "returns unsigned registers, independent of field mappings" do
      xml.at_xpath("//O[@I='H10704']")["V"] = "65535"
      expect(parser.raw_values(xml.to_xml)).to include("H10704" => 65_535, "I10208" => 93)
    end

    it "uses the last duplicate register" do
      node = xml.at_xpath("//O[@I='I10208']")
      node.add_next_sibling(node.dup.tap { |copy| copy["V"] = "1300" })
      expect(parser.raw_values(xml.to_xml)["I10208"]).to eq(1300)
    end

    [nil, "", "abc", "12oops", "1.5", "-1", "65536"].each do |value|
      it "rejects invalid register V=#{value.inspect}" do
        node = xml.at_xpath("//O[@I='I10208']")
        value.nil? ? node.remove_attribute("V") : node["V"] = value
        expect { parser.raw_values(xml.to_xml) }.to raise_error(AtreaControl::ProtocolError)
      end
    end

    it "rejects a missing register ID" do
      xml.at_xpath("//O").remove_attribute("I")
      expect { parser.raw_values(xml.to_xml) }.to raise_error(AtreaControl::ProtocolError)
    end
  end

  describe "payload validation" do
    ["<other/>", "<html><body>Login</body></html>", "<RD5WEB>",
     '<wrapper><RD5WEB t="2021-10-26 21:45:51"><RD5/></RD5WEB></wrapper>',
     '<RD5WEB t="2021-10-26 21:45:51"/>'].each do |payload|
      it "rejects non-unit or malformed XML #{payload.inspect}" do
        expect { parser.parse(payload) }.to raise_error(AtreaControl::ProtocolError)
      end
    end

    [nil, "", "   "].each do |timestamp|
      it "reports missing timestamp #{timestamp.inspect} before sensor discovery" do
        timestamp.nil? ? xml.root.remove_attribute("t") : xml.root["t"] = timestamp
        expect(user_ctrl).not_to receive(:sensors)
        expect { parser.parse(xml.to_xml) }.to raise_error(AtreaControl::SessionExpired)
      end
    end

    ["invalid", "2021-02-30 12:00:00", "2021-10-26 25:00:00", "2021-10-26 21:45:51junk",
     "2026-2-30 1:2:3", "2026-13-1 1:2:3", "2026-1-0 1:2:3", "2026-1-1 24:0:0", "2026-1-1 25:0:0",
     "2026-1-1 1:60:0", "2026-1-1 1:2:60", "2026-1-1 1:2:3junk", "026-1-1 1:2:3", "2026-001-1 1:2:3"].each do |timestamp|
      it "rejects invalid timestamp #{timestamp.inspect} before sensor discovery" do
        xml.root["t"] = timestamp
        expect(user_ctrl).not_to receive(:sensors)
        expect { parser.parse(xml.to_xml) }.to raise_error(AtreaControl::ProtocolError)
      end
    end

    it "rejects DTDs without resolving external entities" do
      payload = '<!DOCTYPE RD5WEB [<!ENTITY secret SYSTEM "https://example.test/secret">]>' \
                '<RD5WEB t="2021-10-26 21:45:51"><RD5>&secret;</RD5></RD5WEB>'
      expect { parser.raw_values(payload) }.to raise_error(AtreaControl::ProtocolError)
    end
  end

  describe "field projections" do
    {
      "2026-10-25 17:7:32 " => Time.local(2026, 10, 25, 17, 7, 32),
      "2026-1-15 12:34:56" => Time.local(2026, 1, 15, 12, 34, 56),
      "2026-01-5 12:34:56" => Time.local(2026, 1, 5, 12, 34, 56),
      "2026-01-15 2:34:56" => Time.local(2026, 1, 15, 2, 34, 56),
      "2026-01-15 12:3:56" => Time.local(2026, 1, 15, 12, 3, 56),
      "2026-01-15 12:34:6" => Time.local(2026, 1, 15, 12, 34, 6),
      "2026-1-5 2:3:4 " => Time.local(2026, 1, 5, 2, 3, 4),
    }.each do |timestamp, instant|
      it "accepts unpadded timestamp #{timestamp.inspect}" do
        xml.root["t"] = timestamp
        expect(parser.values(xml.to_xml)["timestamp"]).to eq(instant)
      end
    end

    it "aliases requested temperature while retaining the historical name" do
      sensors["preheat_temperature"] = "H10706"
      expect(parser.values(xml.to_xml)).to include("required_temperature" => 15.0, "preheat_temperature" => 15.0)
      expect(parser.parse(xml.to_xml)["required_temperature"]).to eq(150)
    end

    it "keeps an undiscovered optional inlet unavailable" do
      sensors.delete("input_temperature")
      expect(parser.values(xml.to_xml)["input_temperature"]).to be_nil
    end

    it "reads values without command configuration or command registers" do
      optional = %w[H10510 H10501 H11300 H11700 C10508 C10509 I11401 H10700 H10701 H10708 H10709]
      xml.xpath("//O").select { |node| optional.include?(node["I"]) }.each(&:remove)
      expect(parser.values(xml.to_xml)).to include("current_power" => 88.0, "required_temperature" => 15.0)
    end

    it "uses discovered alternate outdoor register" do
      sensors["outdoor_temperature"] = "I10211"
      xml.at_xpath("//O[@I='I10211']")["V"] = "123"
      expect(parser.values(xml.to_xml)["outdoor_temperature"]).to eq(12.3)
    end

    it "publishes configuration and readings from one parse" do
      payload = xml.to_xml
      expect(Nokogiri).to receive(:XML).once.and_call_original
      bundle = parser.snapshot(payload)
      expect(bundle.fetch(:configuration).fetch("H11300")).to eq(0)
      expect(bundle.fetch(:values)["current_power"]).to eq(88.0)
    end

    context "with inlet source metadata" do
      before do
        allow(user_ctrl).to receive(:input_temperature_source).and_return("rd5_standard")
        xml.at_xpath("//O[@I='H11300']")["V"] = "1"
      end

      it "uses I10204 for H11300=1 instead of the first assignment" do
        xml.at_xpath("//O[@I='I10204']")["V"] = "65036"
        expect(parser.values(xml.to_xml)["input_temperature"]).to eq(-50.0)
      end

      %w[unsupported future_rule].each do |source|
        it "keeps source #{source} unavailable" do
          allow(user_ctrl).to receive(:input_temperature_source).and_return(source)
          expect(parser.values(xml.to_xml)["input_temperature"]).to be_nil
        end
      end

      it "accepts a custom object's symbol source" do
        allow(user_ctrl).to receive(:input_temperature_source).and_return(:rd5_standard)
        xml.at_xpath("//O[@I='I10204']")["V"] = "65036"
        expect(parser.values(xml.to_xml)["input_temperature"]).to eq(-50.0)
      end

      it "retains direct mapping for a legacy nil source" do
        allow(user_ctrl).to receive(:input_temperature_source).and_return(nil)
        sensors["input_temperature"] = "I10200"
        xml.at_xpath("//O[@I='I10200']")["V"] = "123"
        expect(parser.values(xml.to_xml)["input_temperature"]).to eq(12.3)
      end

      it "allows missing optional inlet registers" do
        xml.xpath("//O[@I='I10204']").remove
        expect(parser.values(xml.to_xml)["input_temperature"]).to be_nil
      end
    end

    { 65_535 => -0.1, 65_036 => -50.0, 0 => 0.0, 1300 => 130.0, 32_767 => 3276.7, 32_768 => -3276.8 }.each do |raw, temperature|
      it "decodes temperature #{raw} as #{temperature}" do
        xml.at_xpath("//O[@I='I10208']")["V"] = raw.to_s
        expect(parser.values(xml.to_xml)["outdoor_temperature"]).to eq(temperature)
      end
    end

    it "retains legacy direct temperature mappings without a source method, preserving raw registers" do
      sensors.merge!("preheat_temperature" => "H10706", "input_temperature" => "I10200")
      %w[H10706 I10200].each { |id| xml.at_xpath("//O[@I='#{id}']")["V"] = "65036" }
      expect(user_ctrl).not_to respond_to(:input_temperature_source)
      expect(parser.raw_values(xml.to_xml)).to include("H10706" => 65_036, "I10200" => 65_036)
      expect(parser.values(xml.to_xml)).to include("preheat_temperature" => -50.0, "input_temperature" => -50.0)
    end

    it "keeps non-temperature and configuration values unsigned" do
      %w[H10704 H10708].each { |id| xml.at_xpath("//O[@I='#{id}']")["V"] = "65535" }
      expect(parser.parse(xml.to_xml)).to include("current_power" => 65_535, "power_input" => 65_535)
    end

    it "preserves timestamp and preheating projections" do
      expect(parser.values(xml.to_xml)).to include("timestamp" => Time.local(2021, 10, 26, 21, 45, 51), "preheating" => true)
    end

    it "rejects a missing required mapped register" do
      xml.xpath("//O[@I='I10208']").remove
      expect { parser.parse(xml.to_xml) }.to raise_error(AtreaControl::ProtocolError, /I10208/)
    end

    it "rejects an invalid sensor mapping" do
      sensors["outdoor_temperature"] = nil
      expect { parser.parse(xml.to_xml) }.to raise_error(AtreaControl::UnsupportedConfiguration)
    end
  end
end
