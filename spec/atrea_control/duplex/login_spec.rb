# frozen_string_literal: true

FIXTURE_CORE_INIT_PATH = File.join(__dir__, "../../fixtures/files/core.php-init.xml")
FIXTURE_UNITS_TABLE_PATH = File.join(__dir__, "../../fixtures/files/data.php-getdata.xml")
FIXTURE_UNIT_RECORD_PATH = File.join(__dir__, "../../fixtures/files/data.php-getrecord.xml")
FIXTURE_UNIT_QUERY_PATH_0 = File.join(__dir__, "../../fixtures/files/handle.php-unitQuery_0.xml")
FIXTURE_UNIT_QUERY_PATH = File.join(__dir__, "../../fixtures/files/handle.php-unitQuery_009.xml")

RSpec.describe AtreaControl::Duplex::Login do
  subject(:duplex) { described_class.new login: "myhome", password: "secret" }

  before do
    stub_request(:post, /\?action=login/)
      .to_return(headers: { "Set-Cookie" => "PHPSESSID=12345" })

    stub_request(:get, %r{.*core/core.php\?.*action=init})
      .with(headers: { "Cookie" => "PHPSESSID=12345", "App-name" => "rd5Control" })
      .to_return(body: File.read(FIXTURE_CORE_INIT_PATH))

    stub_request(:post, %r{/core/core.php\?Sync=1&action=run&object=app&lng=28&rVer=1})
      .to_return(status: 200)

    stub_request(:post, %r{/core/core.php\?Sync=1&action=load&object=setting})
      .to_return(status: 200)

    stub_request(:get, %r{/_data/data.php\?.*action=getdata.*&ds=rd5})
      .to_return(body: File.read(FIXTURE_UNITS_TABLE_PATH))

    stub_request(:get, %r{/_data/data.php\?.*action=getrecord})
      .to_return(body: File.read(FIXTURE_UNIT_RECORD_PATH))

    stub_request(:get, %r{/apps/rd5Control/handle.php\?.*action=unitQuery})
      .to_return(body: File.read(FIXTURE_UNIT_QUERY_PATH_0))
  end

  describe ".user_tokens" do
    it "returns user tokens" do
      stub_request(:get, %r{/apps/rd5Control/handle.php\?.*action=unitQuery})
        .to_return(body: File.read(FIXTURE_UNIT_QUERY_PATH))

      tokens = described_class.user_tokens(login: "myhome", password: "secret")
      expect(tokens).to include(:user_id, :unit_id, :sid)
    end
  end

  describe "#call" do
    it "raise error when login failed" do
      stub_request(:post, %r{/apps/rd5Control/handle.php.*action=unitLogin})
        .to_return(status: 200, body: "<root><sended time='1'></sended></root>")

      expect { duplex.call }.to raise_error(AtreaControl::Error)
    end
  end
end
