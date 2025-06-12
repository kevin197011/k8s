#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'net/ssh'
require 'net/scp'
require 'fileutils'
require_relative 'version_manager'
require_relative 'node_manager'
require_relative 'system_optimizer'
require_relative 'state_manager'
require_relative 'hosts_manager'
require_relative 'nginx_ha_manager'
require_relative 'ssh_manager'
require_relative 'logger_manager'

module RKE2
  class ClusterManager
    attr_reader :config, :version_manager, :node_manager, :system_optimizer, :state_manager, :hosts_manager,
                :nginx_ha_manager, :ssh_manager

    def initialize(config_path)
      @config = YAML.load_file(config_path)
      @config_path = config_path
      @cluster_name = @config['cluster_name']
      @logger = LoggerManager.create('cluster')
      @state_manager = StateManager.new(@cluster_name)
      @version_manager = VersionManager.new(@config_path)
      @system_optimizer = SystemOptimizer.new(@config)
      @node_manager = NodeManager.new(@config)
      @hosts_manager = HostsManager.new(@config)
      @nginx_ha_manager = NginxHAManager.new(@config)
      @ssh_manager = SSHManager.new(@config)
    end

    def deploy
      @logger.info "Deploying RKE2 cluster: #{@cluster_name}"

      # 更新所有节点的 hosts 文件
      update_hosts_files

      # 记录初始状态
      initial_state = @state_manager.record_state

      # 设置 Nginx 负载均衡
      setup_nginx_lb

      # 执行部署
      deploy_master_nodes
      deploy_worker_nodes

      # 检查部署后状态
      compare_and_handle_changes(initial_state)
    end

    def optimize
      @logger.info "Optimizing RKE2 cluster: #{@cluster_name}"

      # 记录优化前状态
      pre_optimize_state = @state_manager.record_state

      # 执行优化
      @system_optimizer.optimize_all

      # 检查优化后状态
      compare_and_handle_changes(pre_optimize_state)
    end

    def add_worker(node_config)
      puts "Adding worker node to cluster: #{@cluster_name}"

      # 更新所有节点的 hosts 文件
      update_hosts_files

      # 记录添加节点前状态
      pre_add_state = @state_manager.record_state

      # 添加节点
      @node_manager.add_worker_node(node_config)

      # 检查添加后状态
      compare_and_handle_changes(pre_add_state)
    end

    def remove_worker(node_name)
      puts "Removing worker node from cluster: #{@cluster_name}"

      # 记录删除节点前状态
      pre_remove_state = @state_manager.record_state

      # 删除节点
      @node_manager.remove_worker_node(node_name)

      # 更新所有节点的 hosts 文件
      update_hosts_files

      # 检查删除后状态
      compare_and_handle_changes(pre_remove_state)
    end

    def update_hosts_files
      puts 'Updating hosts files on all nodes...'
      @hosts_manager.update_all_hosts
    end

    def setup_nginx_lb
      puts 'Setting up Nginx load balancer...'
      @nginx_ha_manager.setup_nginx_lb
    end

    private

    def deploy_master_nodes
      first_master = true
      @config['master_nodes'].each do |node|
        puts "Deploying master node: #{node['name']}"

        # 测试 SSH 连接
        unless @ssh_manager.test_connection(node)
          puts "Failed to connect to #{node['name']}, skipping..."
          next
        end

        # 设置免密登录
        @ssh_manager.setup_passwordless_ssh(node)

        if first_master
          deploy_first_master(node)
          first_master = false
        else
          deploy_additional_master(node)
        end
      end
    end

    def deploy_worker_nodes
      @config['worker_nodes'].each do |node|
        puts "Deploying worker node: #{node['name']}"

        # 测试 SSH 连接
        unless @ssh_manager.test_connection(node)
          puts "Failed to connect to #{node['name']}, skipping..."
          next
        end

        # 设置免密登录
        @ssh_manager.setup_passwordless_ssh(node)

        # 部署工作节点
        deploy_worker(node)
      end
    end

    def deploy_first_master(node)
      commands = [
        # 系统准备
        'swapoff -a',
        'setenforce 0',

        # 下载并安装 RKE2
        "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=#{@config['versions']['rke2']['version']} sh -",

        # 创建配置目录
        'mkdir -p /etc/rancher/rke2',

        # 写入配置文件
        "echo 'token: #{@config['token']}' > /etc/rancher/rke2/config.yaml",
        "echo 'tls-san:' >> /etc/rancher/rke2/config.yaml"
      ]

      # 添加 tls-san 配置
      @config['tls-san'].each do |san|
        commands << "echo '  - #{san}' >> /etc/rancher/rke2/config.yaml"
      end

      # 添加其他命令
      commands += [
        # 启动 RKE2 服务
        'systemctl enable rke2-server',
        'systemctl start rke2-server',

        # 设置环境变量
        'echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> ~/.bashrc',
        'echo "export PATH=\$PATH:/var/lib/rancher/rke2/bin" >> ~/.bashrc',
        '. ~/.bashrc'
      ]

      commands.each do |cmd|
        @ssh_manager.execute_command(node, cmd)
      end
    end

    def deploy_additional_master(node)
      first_master = @config['master_nodes'].first
      server_url = "https://#{first_master['ip_address']}:9345"

      commands = [
        # 系统准备
        'swapoff -a',
        'setenforce 0',

        # 下载并安装 RKE2
        "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=#{@config['versions']['rke2']['version']} sh -",

        # 创建配置目录
        'mkdir -p /etc/rancher/rke2',

        # 写入配置文件
        "echo 'server: #{server_url}' > /etc/rancher/rke2/config.yaml",
        "echo 'token: #{@config['token']}' >> /etc/rancher/rke2/config.yaml",

        # 启动 RKE2 服务
        'systemctl enable rke2-server',
        'systemctl start rke2-server'
      ]

      commands.each do |cmd|
        @ssh_manager.execute_command(node, cmd)
      end
    end

    def deploy_worker(node)
      first_master = @config['master_nodes'].first
      server_url = "https://#{first_master['ip_address']}:9345"

      commands = [
        # 系统准备
        'swapoff -a',
        'setenforce 0',

        # 下载并安装 RKE2
        "curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent INSTALL_RKE2_VERSION=#{@config['versions']['rke2']['version']} sh -",

        # 创建配置目录
        'mkdir -p /etc/rancher/rke2',

        # 写入配置文件
        "echo 'server: #{server_url}' > /etc/rancher/rke2/config.yaml",
        "echo 'token: #{@config['token']}' >> /etc/rancher/rke2/config.yaml",

        # 启动 RKE2 服务
        'systemctl enable rke2-agent',
        'systemctl start rke2-agent'
      ]

      commands.each do |cmd|
        @ssh_manager.execute_command(node, cmd)
      end
    end

    def compare_and_handle_changes(previous_state)
      comparison = @state_manager.compare_states(previous_state)

      case comparison[:status]
      when :changed
        handle_changes(comparison[:changes])
      when :unchanged
        puts 'No changes detected in cluster state.'
      when :initial_state
        puts 'Initial cluster state recorded.'
      end
    end

    def handle_changes(changes)
      puts "\nDetected changes in cluster state:"

      changes.each do |component, details|
        puts "\n#{component.to_s.capitalize} changes:"
        case component
        when :nodes
          handle_node_changes(details)
        when :components
          handle_component_changes(details)
        when :network
          handle_network_changes(details)
        when :resources
          handle_resource_changes(details)
        end
      end
    end

    def handle_node_changes(details)
      if details[:details][:added].any?
        puts 'New nodes added:'
        details[:details][:added].each { |node| puts "  - #{node[:name]}" }
        update_hosts_files
      end

      if details[:details][:removed].any?
        puts 'Nodes removed:'
        details[:details][:removed].each { |node| puts "  - #{node[:name]}" }
        update_hosts_files
      end

      return unless details[:details][:changed].any?

      puts 'Nodes changed:'
      details[:details][:changed].each { |node| puts "  - #{node[:name]}" }
    end

    def handle_component_changes(details)
      puts 'Core components changed' if details[:details][:core]

      return unless details[:details][:rke2]

      puts 'RKE2 component status changed'
    end

    def handle_network_changes(details)
      puts 'Network pod configuration changed' if details[:details][:pods]

      return unless details[:details][:services]

      puts 'Service configuration changed'
    end

    def handle_resource_changes(details)
      details[:details].each do |resource, changed|
        @logger.info "#{resource.to_s.capitalize} configuration changed" if changed
      end
    end
  end
end
