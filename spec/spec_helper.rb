# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "atrea_control"
require "socket"
require "webmock/rspec"
WebMock.disable_net_connect!

RSpec.configure do |config|
  # Fail closed even if an HTTP adapter is missing its WebMock integration.
  config.before do
    [Socket, TCPSocket, UDPSocket].each do |type|
      allow(type).to receive(:new).and_raise("Unstubbed network socket")
      allow(type).to receive(:open).and_raise("Unstubbed network socket")
    end
    allow(Socket).to receive(:tcp).and_raise("Unstubbed network socket")
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
