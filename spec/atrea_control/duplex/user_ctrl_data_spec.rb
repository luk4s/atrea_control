# frozen_string_literal: true

require "json"

RSpec.describe AtreaControl::Duplex::UserCtrl, ".data" do
  let(:credentials) { { user_id: "1234", unit_id: "123456789", sid: "4012" } }
  let(:layout) { Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/userCtrl.xml"))) }
  let(:readings) { Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/unit.xml"))) }
  let(:persisted) { JSON.parse(JSON.generate(data)) }
  let(:unit) { AtreaControl::Duplex::Unit.new(**credentials, user_ctrl: home) }

  before do
    stub_request(:get, endpoint).with(query: hash_including("_t" => "lang/userCtrl.xml")).to_return { { body: layout.to_xml } }
    texts = File.read(File.join(__dir__, "../../fixtures/files/texts.xml"))
    stub_request(:get, endpoint).with(query: hash_including("_t" => "config/texts.xml")).to_return(body: texts)
    stub_request(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).to_return { { body: readings.to_xml } }
    allow(Time).to receive(:now).and_return(Time.local(2026, 1, 15, 12))
    readings.root["t"] = "2026-01-15 12:00:00"
    { "I10200" => 111, "I10201" => 222, "I10204" => 333, "H10200" => 50, "H10201" => 60 }.each do |id, value|
      register(id, value)
    end
  end

  def endpoint
    "#{AtreaControl::Duplex::CONTROL_URI}/comm/sw/unit.php"
  end

  def data
    described_class.data(**credentials)
  end

  def home
    Struct.new(:name, :sensors, :modes, :user_modes, :input_temperature_source, keyword_init: true).new(**persisted.transform_keys(&:to_sym))
  end

  def register(id, value)
    node = readings.at_xpath("//O[@I='#{id}']")
    value.nil? ? node.remove : node["V"] = value.to_s
  end

  it "exports a string source rule alongside the persisted mappings" do
    expect(data).to include(input_temperature_source: "rd5_standard")
    expect(persisted.keys).to contain_exactly("name", "sensors", "modes", "user_modes", "input_temperature_source")
    expect(home.sensors).to include("input_temperature" => "I10204")
  end

  [[0, 1, 11.1], [0, 2, 22.2], [1, 1, 33.3]].each do |inlet, fan, temperature|
    it "resolves H11300=#{inlet}, H10501=#{fan} after JSON roundtrip" do
      register("H11300", inlet)
      register("H10501", fan)
      expect(unit.input_temperature).to eq(temperature)
      expect(unit.values[:input_temperature]).to eq(temperature)
    end
  end

  it "discovers metadata once and reuses the unit snapshot" do
    2.times { unit.values }
    expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_t" => "lang/userCtrl.xml")).once
    expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_t" => "config/texts.xml")).once
    expect(WebMock).to have_requested(:get, endpoint).with(query: hash_including("_t" => "config/xml.xml")).once
  end

  [{ "H10200" => 0 }, { "I10200" => 1260 }, { "I10200" => nil }, { "H10200" => nil }].each do |missing|
    it "preserves unavailable inlet readings for #{missing.inspect}" do
      register("H11300", 0)
      register("H10501", 1)
      missing.each { |id, value| register(id, value) }
      expect(unit.input_temperature).to be_nil
    end
  end

  it "preserves unsupported source rules after JSON roundtrip" do
    layout.at_xpath("//i[@title='$inletTemp']/displayval").content = "function() { return values.I10204; }"
    expect(persisted["input_temperature_source"]).to eq("unsupported")
    expect(unit.input_temperature).to be_nil
  end

  it "preserves a missing optional inlet after JSON roundtrip" do
    layout.xpath("//i[@title='$inletTemp']").remove
    expect(home.sensors["input_temperature"]).to be_nil
    expect(unit.input_temperature).to be_nil
  end
end
