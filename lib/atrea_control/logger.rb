require "logger"

module AtreaControl
  module Logger

    def logger
      @logger ||= ::Logger.new($stdout)
    end

  end
end
