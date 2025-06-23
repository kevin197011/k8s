# frozen_string_literal: true

require 'yaml'
require 'logger'

module RKE2
  # Base configuration and utilities
  class Base
    attr_reader :config, :logger, :nodes, :server_nodes, :agent_nodes, :lb_nodes

    def initialize(config_file)
      @config = YAML.load_file(config_file)
      @logger = Logger.new('deploy.log')
      @nodes = @config['nodes']

      # Group nodes by role
      @server_nodes = @nodes.select { |node| node['role'] == 'server' }
      @agent_nodes = @nodes.select { |node| node['role'] == 'agent' }
      @lb_nodes = @nodes.select { |node| node['role'] == 'lb' }
    end

    def log(msg)
      puts msg
      @logger.info(msg)
    end

    def token
      @config['token']
    end

    def lb_ip
      @config['loadbalancer_ip']
    end
  end
end
