# frozen_string_literal: true

RSpec.describe AtreaControl::Duplex::UserCtrl do
  subject(:user_ctrl) { described_class.new user_id: user_id, unit_id: unit_id, sid: "4012" }

  let(:user_id) { "1234" }
  let(:unit_id) { "123456789" }
  let(:user_ctrl_fixture) { File.join(__dir__, "../../fixtures/files/userCtrl.xml") }
  let(:user_texts_fixture) { File.join(__dir__, "../../fixtures/files/texts.xml") }
  let(:request) { instance_double(AtreaControl::Duplex::Request) }

  before do
    allow(user_ctrl).to receive(:request).and_return(request)
    allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return spy(body: File.read(user_ctrl_fixture))
    allow(request).to receive(:call).with(include(_t: "config/texts.xml")).and_return spy(body: File.read(user_texts_fixture))
  end

  it "fetches configuration once across discovery calls" do
    expect(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).once.and_return(spy(body: File.read(user_ctrl_fixture)))
    user_ctrl.sensors
    user_ctrl.modes
    user_ctrl.user_modes
    user_ctrl.input_temperature_source
  end

  describe "configuration validation" do
    ["<root>", "<html><body>Login</body></html>", "<root/>",
     '<!DOCTYPE root SYSTEM "https://example.test/config"><root><layout><body/></layout></root>'].each do |payload|
      it "rejects invalid configuration #{payload.inspect} without caching it" do
        expect(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).twice.and_return(spy(body: payload), spy(body: File.read(user_ctrl_fixture)))
        expect { user_ctrl.user_ctrl }.to raise_error(AtreaControl::ProtocolError)
        expect(user_ctrl.sensors).to include("outdoor_temperature" => "I10208")
      end
    end

    %w[$currentPower $currentMode $outdoorTemp $requiredTemp].each do |title|
      it "reports missing required sensor #{title}" do
        xml = Nokogiri::XML(File.read(user_ctrl_fixture))
        xml.xpath("//body/content/i[@title='#{title}']").remove
        allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
        expect { user_ctrl.sensors }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end

    %w[displayval onchange].each do |element|
      it "reports missing mode #{element} mapping" do
        xml = Nokogiri::XML(File.read(user_ctrl_fixture))
        xml.xpath("//i[@title='$currentMode']/#{element}").remove
        allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
        expect { user_ctrl.sensors }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end

    %w[Mode ModeText].each do |id|
      it "reports missing #{id} definitions" do
        xml = Nokogiri::XML(File.read(user_ctrl_fixture))
        xml.xpath("//op[@id='#{id}']").remove
        allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
        expect { id == "Mode" ? user_ctrl.modes : user_ctrl.user_modes }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end

    %w[id title].each do |attribute|
      it "reports missing mode #{attribute}" do
        xml = Nokogiri::XML(File.read(user_ctrl_fixture))
        xml.at_xpath("//op[@id='Mode']/i").remove_attribute(attribute)
        allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
        expect { user_ctrl.modes }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end

    ["<root>", "<html/>", '<root><texts><i id="UnitName"/></texts></root>'].each do |payload|
      it "reports invalid user texts #{payload.inspect}" do
        allow(request).to receive(:call).with(include(_t: "config/texts.xml")).and_return(spy(body: payload))
        expect { user_ctrl.name }.to raise_error(AtreaControl::ProtocolError)
      end
    end
  end

  it "#name" do
    expect(user_ctrl.name).to eq "Unit 007"
  end

  it "discovers both command inputs and their conditional control switches" do
    expect(user_ctrl.sensors).to include("power_input" => "H10708", "power_switch" => "H10700",
                                         "mode_input" => "H10709", "mode_switch" => "H10701")
  end

  ["$currentPower", "$currentMode"].each do |title|
    it "discovers alternate registers in the supported #{title} command profile" do # rubocop:disable RSpec/ExampleLength
      xml = Nokogiri::XML(File.read(user_ctrl_fixture))
      node = xml.at_xpath("//i[@title='#{title}']/onchange")
      node.content = node.text.gsub(/H1070([0189])/, "H1200\\1")
      allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
      field = title == "$currentPower" ? "power" : "mode"
      input, switch = field == "power" ? %w[H12008 H12000] : %w[H12009 H12001]
      expect(user_ctrl.sensors).to include("#{field}_input" => input, "#{field}_switch" => switch)
    end

    ["==1", "',2)", "saved=true;"].each do |fragment|
      it "rejects unknown #{title} command profile changed at #{fragment}" do
        xml = Nokogiri::XML(File.read(user_ctrl_fixture))
        node = xml.at_xpath("//i[@title='#{title}']/onchange")
        node.content = node.text.sub(fragment, fragment == "saved=true;" ? "evil();" : "UNKNOWN")
        allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
        expect { user_ctrl.sensors }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end
  end

  describe "#sensors" do
    subject { user_ctrl.sensors }

    it { is_expected.to be_a Hash }
  end

  it "recognizes the complete supported inlet source rule without choosing its first assignment" do
    expect(user_ctrl.input_temperature_source).to eq("rd5_standard")
    expect(user_ctrl.sensors["input_temperature"]).to eq("I10204")
    expect(user_ctrl).not_to respond_to(:input_temperature_profile)
  end

  it "does not assume custom inlet logic is the standard profile" do
    xml = Nokogiri::XML(File.read(user_ctrl_fixture))
    xml.at_xpath("//i[@title='$inletTemp']/displayval").content = "function() { return values.I10200; }"
    allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
    expect(user_ctrl.input_temperature_source).to eq("unsupported")
  end

  it "keeps missing optional inlet metadata unavailable" do
    xml = Nokogiri::XML(File.read(user_ctrl_fixture))
    xml.xpath("//i[@title='$inletTemp']").remove
    allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
    expect(user_ctrl.sensors["input_temperature"]).to be_nil
    expect(user_ctrl.input_temperature_source).to eq("unsupported")
  end

  it "rejects a subtly changed profile even if all register names remain" do
    xml = Nokogiri::XML(File.read(user_ctrl_fixture))
    node = xml.at_xpath("//i[@title='$inletTemp']/displayval")
    node.content = node.text.sub("H10200>0", "H10200>=0")
    allow(request).to receive(:call).with(include(_t: "lang/userCtrl.xml")).and_return(spy(body: xml.to_xml))
    expect(user_ctrl.input_temperature_source).to eq("unsupported")
  end

  describe "#modes" do
    subject { user_ctrl.modes }

    it { is_expected.to be_a Hash }
  end

  describe "#user_modes" do
    subject { user_ctrl.user_modes }

    it { is_expected.to be_a Hash }
  end
end
