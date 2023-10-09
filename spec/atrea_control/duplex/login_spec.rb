# frozen_string_literal: true

FIXTURE_LOGIN_PATH = File.join(__dir__, "../../fixtures/files/login.html")
AtreaControl::Duplex::CONTROL_URI = "file://#{FIXTURE_LOGIN_PATH}".freeze

RSpec.describe AtreaControl::Duplex::Login do
  subject(:duplex) { described_class.new login: "myhome", password: "secret" }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    duplex.close
  end

  describe "#login" do
    it "fill form, wait until unit response" do
      expect(duplex).to receive(:open_dashboard).and_raise Selenium::WebDriver::Error::NoSuchElementError
      expect(duplex).to receive(:sleep)
      expect(duplex).to receive(:open_dashboard).and_return true
      duplex.login
    end
  end

  describe "#open_dashboard" do
    it "grab object data" do
      fixture = File.join(__dir__, "../../fixtures/files/texts.xml")
      stub_request(:get,
                   %r{https://control.atrea.eu/comm/sw/unit.php}).to_return(body: File.read(fixture))
      duplex.driver.get "file://#{File.join(__dir__, "../../fixtures/files/logged.html")}"
      expect { duplex.open_dashboard }.not_to raise_exception
    end
  end

  describe "#user" do
    subject(:user) { duplex.user }

    let(:driver) { nil }

    before do
      duplex.driver.get "file://#{File.join(__dir__, "../../fixtures/files/dashboard.html")}"
      allow(duplex).to receive(:login).and_return driver
    end

    context "without login" do
      it { expect { user }.to raise_error AtreaControl::Error }
    end

    context "with login return credentials" do
      let(:driver) { double }

      it { expect(user).to include(user_id: match(/\d+/), unit_id: match(/\d+/), sid: be_a(Integer)) }
    end
  end

  it ".user_tokens" do
    dbl = spy("Login")
    allow(described_class).to receive(:new).and_return dbl
    described_class.user_tokens(login: "myhome", password: "secret")
    expect(dbl).to have_received(:user).exactly 1
    expect(dbl).to have_received(:close).at_least 1
  end
end
