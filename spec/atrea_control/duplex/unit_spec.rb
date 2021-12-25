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
end
