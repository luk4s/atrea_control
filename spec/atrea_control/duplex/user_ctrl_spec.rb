# frozen_string_literal: true

RSpec.describe AtreaControl::Duplex::UserCtrl do
  subject(:user_ctrl) { described_class.new user_id: user_id, unit_id: unit_id, sid: sid }

  let(:user_id) { "1234" }
  let(:unit_id) { "123456789" }
  let(:sid) { "4012" }
  let(:user_ctrl_fixture) { File.join(__dir__, "../../fixtures/files/userCtrl.xml") }
  let(:user_texts_fixture) { File.join(__dir__, "../../fixtures/files/texts.xml") }

  before do
    request = instance_double(AtreaControl::Duplex::Request)
    allow(user_ctrl).to receive(:request).and_return(request)
    allow(request).to receive(:call).with(_t: "lang/userCtrl.xml").and_return spy(body: File.read(user_ctrl_fixture))
    allow(request).to receive(:call).with(_t: "config/texts.xml").and_return spy(body: File.read(user_texts_fixture))
  end

  it "#name" do
    expect(user_ctrl.name).to eq "Unit 007"
  end

  describe "#sensors" do
    subject { user_ctrl.sensors }

    it { is_expected.to be_a Hash }
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
