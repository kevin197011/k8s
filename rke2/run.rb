#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/rke2_deploy'

if __FILE__ == $PROGRAM_NAME
  config_path = ARGV[0] || 'config.yml'
  unless File.exist?(config_path)
    puts "❌ 找不到配置文件: #{config_path}"
    exit 1
  end

  RKE2Deployer.new(config_path).run
end
