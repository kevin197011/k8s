#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'socket'

module RKE2
  class LoggerManager
    class << self
      def create(component_name)
        logger = Logger.new(STDOUT)
        logger.level = ENV['LOG_LEVEL'] ? Logger.const_get(ENV['LOG_LEVEL'].upcase) : Logger::INFO
        logger.formatter = proc do |severity, datetime, _progname, msg|
          hostname = Socket.gethostname
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] [#{hostname}] [#{component_name}] [#{severity}] #{msg}\n"
        end
        logger
      end
    end
  end
end
