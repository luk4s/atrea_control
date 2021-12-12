AtreaControl::Duplex::CONTROL_URI = "file://#{File.join(__dir__, "../fixtures/files/login.html")}"

RSpec.describe AtreaControl::Duplex do
  subject(:duplex) { described_class.new login: "myhome", password: "secret" }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    duplex.close
  end

  def stub_unit!
    fixture = File.join(__dir__, "../fixtures/files/unit.xml")
    stub_request(:get,
                 %r{https://control.atrea.eu/comm/sw/unit.php}).to_return(body: File.read(fixture))
  end

  describe "#login" do
    it "fill form, wait until unit response" do
      expect(duplex).to receive(:open_dashboard).and_raise Selenium::WebDriver::Error::NoSuchElementError
      expect(duplex).to receive(:sleep)
      expect(duplex).to receive(:open_dashboard).and_return true
      expect(duplex).to receive(:inspect)
      duplex.login
    end
  end

  describe "#open_dashboard" do
    it "grab object data" do
      fixture = File.join(__dir__, "../fixtures/files/texts.xml")
      stub_request(:get,
                   %r{https://control.atrea.eu/comm/sw/unit.php}).to_return(body: File.read(fixture))
      duplex.driver.get "file://#{File.join(__dir__, "../fixtures/files/logged.html")}"
      expect { duplex.open_dashboard }.to change(duplex, :logged?)
    end
  end

  context "with logged" do
    before do
      duplex.instance_variable_set :@logged, true
      duplex.driver.get "file://#{File.join(__dir__, "../fixtures/files/dashboard.html")}"
      duplex.send(:refresh!)
    end

    describe "#unit_id" do
      it { expect(duplex.unit_id).to eq "123456789" }
    end

    # describe "#outdoor_temperature" do
    #   it { expect(duplex.outdoor_temperature).to eq 21.4 }
    # end
    #
    # describe "#current_power" do
    #   it { expect(duplex.current_power).to eq 86.0 }
    # end

    describe "#call_unit!" do
      it "stub xml" do
        allow(duplex).to receive(:user_auth).and_return "4012"
        stub_unit!
        expect(duplex.call_unit!).to include current_power: 88.0, outdoor_temperature: 9.3
      end
    end

    describe "#to_json" do
      before do
        allow(duplex).to receive(:user_auth).and_return "4012"
        stub_unit!
        duplex.call_unit!
      end

      it "parsed json" do
        json = JSON.parse(duplex.to_json)
        expect(json).to include("current_power" => 88.0, "outdoor_temperature" => 9.3)
      end
    end
  end
end
