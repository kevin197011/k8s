#!/usr/bin/env ruby
# frozen_string_literal: true

# RKE2 集群诊断工具 - 模块化架构演示
# Usage: ruby diagnose.rb [mode] [config_file]
#   mode: quick, standard, comprehensive (default: standard)
#   config_file: path to config file (default: config.yml)

require_relative 'lib/rke2_deploy'

def show_usage
  puts <<~USAGE
    🔍 RKE2 集群诊断工具 v#{RKE2::VERSION} (模块化架构)

    用法: #{$PROGRAM_NAME} [模式] [配置文件]

    诊断模式:
      quick        快速诊断 (仅检查主节点状态)
      standard     标准诊断 (完整的集群状态检查)  [默认]
      comprehensive 全面诊断 (包含系统资源和网络检查)

    示例:
      #{$PROGRAM_NAME}                      # 标准诊断
      #{$PROGRAM_NAME} quick               # 快速诊断
      #{$PROGRAM_NAME} comprehensive       # 全面诊断
      #{$PROGRAM_NAME} standard config.yml # 使用指定配置文件

    模块化特性:
      ✅ 分离的诊断模块 (RKE2::Diagnostics)
      ✅ 独立的集群管理 (RKE2::ClusterManager)
      ✅ 模块间清晰的职责分工
      ✅ 可复用的组件设计
  USAGE
end

def main
  # Parse command line arguments
  mode = ARGV[0] || 'standard'
  config_file = ARGV[1] || 'config.yml'

  # Validate mode
  valid_modes = %w[quick standard comprehensive]
  unless valid_modes.include?(mode)
    puts "❌ 无效的诊断模式: #{mode}"
    puts "有效模式: #{valid_modes.join(', ')}"
    show_usage
    exit 1
  end

  # Check config file
  unless File.exist?(config_file)
    puts "❌ 配置文件 #{config_file} 不存在"
    exit 1
  end

  puts "🔍 RKE2 集群诊断工具 v#{RKE2::VERSION}"
  puts '📋 使用模块化架构进行诊断'
  puts "🎯 诊断模式: #{mode}"
  puts "📄 配置文件: #{config_file}"
  puts ''

  begin
    # Create diagnostics instance using factory method
    diagnostics = RKE2.diagnostics(config_file)

    case mode
    when 'quick'
      puts '⚡ 执行快速诊断...'
      diagnostics.quick_diagnosis
    when 'standard'
      puts '🔍 执行标准诊断...'
      diagnostics.diagnose_cluster_status
    when 'comprehensive'
      puts '🔬 执行全面诊断...'
      diagnostics.comprehensive_diagnosis
    end

    puts ''
    puts '✅ 诊断完成!'
    puts ''
    puts '💡 提示: 您可以使用以下模块化方法进行其他操作:'
    puts '   - RKE2.tools_installer(config_file)     # 工具安装'
    puts '   - RKE2.ingress_controller(config_file)  # Ingress 管理'
    puts '   - RKE2.cluster_manager(config_file)     # 集群管理'
    puts '   - deployer = RKE2.new(config_file)      # 完整部署器'
  rescue StandardError => e
    puts "❌ 诊断过程中发生错误: #{e.message}"
    puts '📋 错误详情:'
    puts e.backtrace.first(5).map { |line| "   #{line}" }.join("\n")
    exit 1
  end
end

# Show usage if --help or -h
if ARGV.include?('--help') || ARGV.include?('-h')
  show_usage
  exit 0
end

# Run main function if this file is executed directly
main if __FILE__ == $PROGRAM_NAME
