# frozen_string_literal: true

require "stringio"

RSpec.describe AtreaControl::Logger do
  subject(:client) { Class.new { include AtreaControl::Logger }.new }

  it "defaults to INFO rather than DEBUG" do
    expect(client.logger.level).to eq(Logger::INFO)
  end

  it "allows capturing diagnostics with an injected DEBUG logger" do
    output = StringIO.new
    client.logger = Logger.new(output, level: Logger::DEBUG)
    client.logger.debug("stage=login status=200")

    expect(output.string).to include("stage=login status=200")
  end

  it "keeps reliability errors under the common error contract" do
    names = %i[AuthenticationError UnitConnectionTimeout ProtocolError TransportError UnsupportedConfiguration WriteNotConfirmed]

    expect(names.map { |name| AtreaControl.const_get(name) }).to all(be < AtreaControl::Error)
  end
end
