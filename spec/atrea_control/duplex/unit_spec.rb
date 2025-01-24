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

  describe "#power=" do
    it "with number" do
      expect(request).to receive(:call).with(hash_including(_t: "config/xml.cgi"))
      unit.power = 63
    end

    it "with nil" do
      expect(request).to receive(:call).with(hash_including(_t: "config/xml.cgi"))
      unit.power = nil
    end
  end

  describe "#mode=" do
    it "with number" do
      expect(request).to receive(:call).with(hash_including(_t: "config/xml.cgi"))
      unit.mode = 1
    end
  end

  describe "#refresh!" do
    let(:parser) { instance_double(AtreaControl::SensorParser) }

    before do
      allow(unit).to receive(:read).and_return spy(body: "<xml></xml>")
      allow(unit).to receive(:parser).and_return parser
      allow(parser).to receive(:values).and_return({ timestamp: 1 }, { timestamp: 2 })
    end

    # rubocop:disable RSpec/ExampleLength
    it "remove cached values" do
      aggregate_failures "demonstrate cache" do
        expect(unit.values).to include timestamp: 1
        expect(unit.values).to include timestamp: 1
      end
      expect(unit.refresh!).to include timestamp: 2
      expect(unit.values).to include timestamp: 2
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe "#valid?" do
    subject(:valid?) { unit.valid? }

    before do
      allow(unit).to receive(:valid?).and_call_original
    end

    context "when timestamp is nil" do
      before { allow(unit).to receive(:timestamp).and_return nil }

      it { is_expected.to be false }
    end

    context "when timestamp is older than 15 minutes" do
      before { allow(unit).to receive(:timestamp).and_return Time.now - (20 * 60.0) }

      it { is_expected.to be false }
    end

    context "when timestamp is newer than 15 minutes" do
      before { allow(unit).to receive(:timestamp).and_return Time.now - (10 * 60.0) }

      it { is_expected.to be true }
    end
  end
end
