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
        action: nil
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
      else
        puts @parser
        exit 1
      end
    end

    private

    def create_option_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options] ACTION"

        opts.separator "\nActions:"
        opts.separator "  deploy              - 部署新的 RKE2 集群"
        opts.separator "  optimize            - 优化现有集群"
        opts.separator "  add-worker          - 添加工作节点"
        opts.separator "  remove-worker       - 移除工作节点"
        opts.separator "  check-versions      - 检查组件版本"
        opts.separator "  check-compatibility - 检查版本兼容性"

        opts.separator "\nOptions:"

        opts.on('-c', '--config FILE', 'Config file path (default: config.yaml)') do |file|
          @options[:config] = file
        end

        opts.on('-h', '--host HOST', 'Worker node host (for add-worker)') do |host|
          @options[:host] = host
        end

        opts.on('-u', '--user USER', 'Worker node user (for add-worker)') do |user|
          @options[:user] = user
        end

        opts.on('-n', '--name NAME', 'Worker node name') do |name|
          @options[:name] = name
        end

        opts.on('--help', 'Show this help message') do
          puts opts
          exit
        end

        opts.separator "\nExamples:"
        opts.separator "  #{File.basename($PROGRAM_NAME)} deploy"
        opts.separator "  #{File.basename($PROGRAM_NAME)} optimize"
        opts.separator "  #{File.basename($PROGRAM_NAME)} add-worker -h worker3.example.com -u root -n worker3"
        opts.separator "  #{File.basename($PROGRAM_NAME)} remove-worker -n worker3"
        opts.separator "  #{File.basename($PROGRAM_NAME)} check-versions"
      end
    end

    def deploy_cluster
      puts '开始部署 RKE2 集群...'
      manager = ClusterManager.new(@options[:config])
      manager.deploy
    end

    def optimize_cluster
      puts '开始优化集群...'
      manager = ClusterManager.new(@options[:config])
      manager.optimize
    end

    def add_worker
      unless @options[:host] && @options[:name]
        puts "错误: 添加工作节点需要指定 --host 和 --name"
        puts @parser
        exit 1
      end

      puts "添加工作节点: #{@options[:name]} (#{@options[:host]})"
      manager = ClusterManager.new(@options[:config])
      node_info = {
        'host' => @options[:host],
        'user' => @options[:user] || 'root',
        'name' => @options[:name]
      }
      manager.scale('add', node_info)
    end

    def remove_worker
      unless @options[:name]
        puts "错误: 移除工作节点需要指定 --name"
        puts @parser
        exit 1
      end

      puts "移除工作节点: #{@options[:name]}"
      manager = ClusterManager.new(@options[:config])
      node_info = { 'name' => @options[:name] }
      manager.scale('remove', node_info)
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
