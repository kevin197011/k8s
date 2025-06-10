#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'lib/cluster_manager'
require_relative 'lib/version_manager'

module RKE2
  class CLI
    def initialize
      @options = {
        config: 'config.yaml',
        action: nil,
        node: nil,
        force: false
      }
      @parser = create_option_parser
    end

    def run(args = ARGV)
      @parser.parse!(args)

      case @options[:action]
      when 'deploy'
        deploy_cluster
      when 'optimize'
        optimize_cluster
      when 'add-worker'
        add_worker
      when 'remove-worker'
        remove_worker
      when 'check-versions'
        check_versions
      when 'check-compatibility'
        check_compatibility
      when 'show-state'
        show_state
      when 'watch-state'
        watch_state
      when 'update-hosts'
        update_hosts
      when 'setup-lb'
        setup_lb
      else
        puts @parser
        exit 1
      end
    end

    private

    def create_option_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] COMMAND"

        opts.on('-c', '--config FILE', 'Config file path (default: config.yaml)') do |file|
          @options[:config] = file
        end

        opts.on('-n', '--node NAME', 'Node name for add/remove operations') do |name|
          @options[:node] = name
        end

        opts.on('-f', '--force', 'Force operation without confirmation') do
          @options[:force] = true
        end

        opts.on('-h', '--help', 'Show this help message') do
          puts opts
          puts "\nCommands:"
          puts "  deploy         Deploy a new RKE2 cluster"
          puts "  optimize       Optimize cluster settings"
          puts "  add-worker     Add a worker node"
          puts "  remove-worker  Remove a worker node"
          puts "  show-state     Show current cluster state"
          puts "  watch-state    Watch cluster state changes"
          puts "  update-hosts   Update hosts files on all nodes"
          puts "  setup-lb       Setup Nginx load balancer"
          exit
        end
      end
    end

    def deploy_cluster
      puts '开始部署 RKE2 集群...'
      manager = ClusterManager.new(@options[:config])
      if @options[:force] || confirm_action('deploy a new cluster')
        manager.deploy
      end
    end

    def optimize_cluster
      puts '开始优化集群...'
      manager = ClusterManager.new(@options[:config])
      if @options[:force] || confirm_action('optimize the cluster')
        manager.optimize
      end
    end

    def add_worker
      unless @options[:node]
        puts "Error: Node name is required for add-worker command"
        exit 1
      end

      puts "添加工作节点: #{@options[:node]} (#{@options[:node]}.example.com)"
      manager = ClusterManager.new(@options[:config])
      if @options[:force] || confirm_action("add worker node #{@options[:node]}")
        node_config = {
          'name' => @options[:node],
          'ip_address' => "192.168.1.#{@options[:node].split('worker')[1].to_i + 20}",
          'hostname' => "#{@options[:node]}.example.com",
          'username' => 'root'
        }
        manager.add_worker(node_config)
      end
    end

    def remove_worker
      unless @options[:node]
        puts "Error: Node name is required for remove-worker command"
        exit 1
      end

      puts "移除工作节点: #{@options[:node]}"
      manager = ClusterManager.new(@options[:config])
      if @options[:force] || confirm_action("remove worker node #{@options[:node]}")
        manager.remove_worker(@options[:node])
      end
    end

    def check_versions
      puts '检查组件版本...'
      version_manager = VersionManager.new(@options[:config])
      version_manager.check_versions
    end

    def check_compatibility
      puts '检查版本兼容性...'
      version_manager = VersionManager.new(@options[:config])
      version_manager.check_compatibility
    end

    def show_state
      state = manager.state_manager.record_state
      puts "\nCurrent Cluster State:"
      puts JSON.pretty_generate(state)
    end

    def watch_state
      puts "Watching cluster state (Press Ctrl+C to stop)..."
      previous_hash = nil

      begin
        loop do
          state = manager.state_manager.record_state
          changes = manager.state_manager.compare_states(previous_hash)

          if changes[:status] == :changed
            puts "\nState change detected at #{Time.now}:"
            puts JSON.pretty_generate(changes)
          end

          previous_hash = state[:hash]
          sleep 10
        end
      rescue Interrupt
        puts "\nStopped watching cluster state."
      end
    end

    def update_hosts
      if @options[:force] || confirm_action('update hosts files on all nodes')
        manager.update_hosts_files
      end
    end

    def setup_lb
      if @options[:force] || confirm_action('setup Nginx load balancer')
        manager.setup_nginx_lb
      end
    end

    def confirm_action(action)
      print "Are you sure you want to #{action}? [y/N] "
      response = gets.chomp.downcase
      response == 'y'
    end
  end
end

# 如果直接运行此文件
if __FILE__ == $PROGRAM_NAME
  begin
    RKE2::CLI.new.run
  rescue Interrupt
    puts "\n操作已取消"
    exit 1
  rescue StandardError => e
    puts "错误: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end
