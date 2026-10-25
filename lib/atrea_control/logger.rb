# frozen_string_literal: true

require "logger"

module AtreaControl
  module Logger
    attr_writer :logger

    def logger
      @logger ||= ::Logger.new($stdout, level: ::Logger::INFO)
    end
  end
end
