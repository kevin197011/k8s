#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/rke2'

if __FILE__ == $PROGRAM_NAME
  config_path = ARGV[0] || 'config.yml'
  unless File.exist?(config_path)
    puts "❌ 找不到配置文件: #{config_path}"
    exit 1
  end

  puts "🚀 RKE2 集群自动化部署工具 v#{RKE2::VERSION}"
  puts '📋 使用模块化架构进行集群部署'
  puts ''

  RKE2.new(config_path).run
end
