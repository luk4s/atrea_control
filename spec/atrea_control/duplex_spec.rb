AtreaControl::Duplex::CONTROL_URI = "file://#{File.join(__dir__, "../fixtures/files/login.html")}"

RSpec.describe AtreaControl::Duplex do
  subject(:duplex) { described_class.new login: "myhome", password: "secret" }

  after do
    duplex.close
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
      duplex.driver.get "file://#{File.join(__dir__, "../fixtures/files/logged.html")}"
      expect { duplex.open_dashboard }.to change(duplex, :logged?)
    end
  end

  context "with logged" do
    before do
      duplex.instance_variable_set :@logged, true
      duplex.driver.get "file://#{File.join(__dir__, "../fixtures/files/dashboard.html")}"
    end

    describe "#name" do
      it { expect(duplex.name).to eq "My Home" }
    end

    describe "#unit_id" do
      it { expect(duplex.unit_id).to eq "123456789" }
    end

    describe "#outdoor_temperature" do
      it { expect(duplex.outdoor_temperature).to eq 21.4 }
    end

    describe "#current_power" do
      it { expect(duplex.current_power).to eq 86.0 }
    end

    describe "#current_mode" do
      it { expect(duplex.current_mode).to eq "ovladač" }
    end

    describe "#to_json" do
      it "parsed json" do
        json = JSON.parse(duplex.to_json)
        expect(json).to include("current_power" => 86.0, "outdoor_temperature" => 21.4)
      end
    end
  end
end
