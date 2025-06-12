#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require_relative 'logger_manager'

module RKE2
  class SystemOptimizer
    def initialize(config)
      @config = config
      @logger = LoggerManager.create('optimizer')
    end

    def optimize_all
      optimize_nodes
      optimize_network
      optimize_ui
      optimize_resources
    end

    private

    def optimize_nodes
      nodes = @config['nodes'] || []
      master_nodes = @config['master_nodes'] || []
      worker_nodes = @config['worker_nodes'] || []

      all_nodes = nodes + master_nodes + worker_nodes
      all_nodes.uniq! { |node| node['ip_address'] }

      all_nodes.each do |node|
        optimize_node(node)
      end
    end

    def optimize_node(node)
      @logger.info "Optimizing system settings on #{node['name']}..."

      begin
        Net::SSH.start(node['ip_address'], node['username'], verify_host_key: :never) do |ssh|
          # 系统参数优化
          optimize_sysctl(ssh)

          # 磁盘优化
          optimize_disk(ssh)

          # 网络优化
          optimize_network_settings(ssh)

          # 内存优化
          optimize_memory(ssh)

          # CPU优化
          optimize_cpu(ssh)
        end
      rescue StandardError => e
        @logger.error "Failed to optimize #{node['name']}: #{e.message}"
        raise
      end
    end

    def optimize_sysctl(ssh)
      sysctl_settings = {
        'net.ipv4.ip_forward' => 1,
        'net.bridge.bridge-nf-call-iptables' => 1,
        'net.ipv4.conf.all.forwarding' => 1,
        'net.ipv6.conf.all.forwarding' => 1,
        'vm.swappiness' => 0,
        'vm.overcommit_memory' => 1,
        'kernel.panic' => 10,
        'kernel.panic_on_oops' => 1,
        'fs.inotify.max_user_watches' => 524_288,
        'fs.file-max' => 2_097_152
      }

      sysctl_settings.each do |key, value|
        ssh.exec!("echo '#{key} = #{value}' | sudo tee -a /etc/sysctl.conf")
      end

      ssh.exec!('sudo sysctl -p')
    end

    def optimize_disk(ssh)
      # 优化磁盘I/O调度器
      ssh.exec!("echo 'deadline' | sudo tee /sys/block/*/queue/scheduler")

      # 优化文件系统挂载选项
      ssh.exec!("sudo sed -i 's/defaults/defaults,noatime,nodiratime/' /etc/fstab")
      ssh.exec!('sudo mount -o remount,noatime,nodiratime /')
    end

    def optimize_network_settings(ssh)
      # 优化网络缓冲区
      ssh.exec!('echo "net.core.rmem_max = 16777216" | sudo tee -a /etc/sysctl.conf')
      ssh.exec!('echo "net.core.wmem_max = 16777216" | sudo tee -a /etc/sysctl.conf')
      ssh.exec!('echo "net.ipv4.tcp_rmem = 4096 87380 16777216" | sudo tee -a /etc/sysctl.conf')
      ssh.exec!('echo "net.ipv4.tcp_wmem = 4096 65536 16777216" | sudo tee -a /etc/sysctl.conf')

      # 优化TCP连接设置
      ssh.exec!('echo "net.ipv4.tcp_max_syn_backlog = 8096" | sudo tee -a /etc/sysctl.conf')
      ssh.exec!('echo "net.core.somaxconn = 8096" | sudo tee -a /etc/sysctl.conf')
    end

    def optimize_memory(ssh)
      # 禁用交换分区
      ssh.exec!('sudo swapoff -a')
      ssh.exec!("sudo sed -i '/ swap / s/^/#/' /etc/fstab")

      # 设置透明大页
      ssh.exec!('echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled')
      ssh.exec!('echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag')
    end

    def optimize_cpu(ssh)
      # 设置CPU性能模式
      ssh.exec!('sudo apt-get install -y cpufrequtils')
      ssh.exec!('echo "GOVERNOR=performance" | sudo tee /etc/default/cpufrequtils')
      ssh.exec!('sudo systemctl restart cpufrequtils')
    end

    def optimize_network
      @logger.info 'Optimizing Calico network settings...'
      # 实现 Calico 网络优化逻辑
    end

    def optimize_ui
      @logger.info 'Optimizing Rancher UI performance...'
      # 实现 Rancher UI 性能优化逻辑
    end

    def optimize_resources
      @logger.info 'Optimizing node resource allocation...'
      # 实现资源分配优化逻辑
    end
  end
end
