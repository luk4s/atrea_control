# frozen_string_literal: true

RSpec.shared_context "with login clock" do
  let(:clock) { [0.0] }

  before do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
    allow(Kernel).to receive(:sleep) { |seconds| clock[0] += seconds }
  end
end
