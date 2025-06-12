#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require 'net/scp'
require_relative 'logger_manager'

module RKE2
  class NodeManager
    def initialize(config)
      @config = config
      @ssh_manager = SSHManager.new(config)
      @logger = LoggerManager.create('node')
    end

    def deploy_first_master(node)
      @logger.info "Deploying first master node: #{node['host']}"

      copy_ssh_key(node)
      install_rke2_server(node, true)

      # 获取节点令牌
      @token = get_node_token(node)
    end

    def deploy_additional_master(node)
      @logger.info "Deploying additional master node: #{node['host']}"

      copy_ssh_key(node)
      install_rke2_server(node, false)
    end

    def deploy_worker(node)
      @logger.info "Deploying worker node: #{node['host']}"

      copy_ssh_key(node)
      install_rke2_agent(node)
    end

    def add_worker(node_config)
      @logger.info "Adding worker node: #{node_config['name']}"

      # 测试 SSH 连接
      unless @ssh_manager.test_connection(node_config)
        @logger.error "Failed to connect to #{node_config['name']}, skipping..."
        return false
      end

      # 设置免密登录
      @ssh_manager.setup_passwordless_ssh(node_config)

      # 部署工作节点
      deploy_worker(node_config)
    end

    def remove_worker(node_name)
      @logger.info "Removing worker node: #{node_name}"

      node_config = find_worker_node(node_name)
      return false unless node_config

      # 排空节点
      drain_node(node_name)

      # 停止服务并清理
      cleanup_worker(node_config)

      # 从集群中删除节点
      delete_node(node_name)
    end

    private

    def ensure_ssh_key
      return if File.exist?(@ssh_key_path)

      system("ssh-keygen -t rsa -b 4096 -f #{@ssh_key_path} -N ''")
    end

    def copy_ssh_key(node)
      system("ssh-copy-id -i #{@ssh_key_path} #{node['user']}@#{node['host']}")
    end

    def get_node_token(node)
      Net::SSH.start(node['host'], node['user']) do |ssh|
        ssh.exec!('cat /var/lib/rancher/rke2/server/node-token')
      end
    end

    def install_rke2_server(node, is_first)
      Net::SSH.start(node['host'], node['user']) do |ssh|
        # 创建配置目录
        ssh.exec!('mkdir -p /etc/rancher/rke2')

        # 复制配置文件
        Net::SCP.upload!(
          node['host'],
          node['user'],
          'config.yaml',
          '/etc/rancher/rke2/config.yaml'
        )

        if is_first
          # 安装第一个主节点
          ssh.exec!("curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=#{@config['versions']['rke2']} sh -")
          ssh.exec!('systemctl enable rke2-server')
          ssh.exec!('systemctl start rke2-server')
        else
          # 安装其他主节点
          ssh.exec!("curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=#{@config['versions']['rke2']} sh -")
          ssh.exec!("echo 'server: https://#{@config['master_nodes'].first['host']}:9345' >> /etc/rancher/rke2/config.yaml")
          ssh.exec!("echo 'token: #{@token}' >> /etc/rancher/rke2/config.yaml")
          ssh.exec!('systemctl enable rke2-server')
          ssh.exec!('systemctl start rke2-server')
        end
      end
    end

    def install_rke2_agent(node)
      Net::SSH.start(node['host'], node['user']) do |ssh|
        # 安装 agent
        ssh.exec!("curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE='agent' INSTALL_RKE2_VERSION=#{@config['versions']['rke2']} sh -")

        # 配置 agent
        ssh.exec!('mkdir -p /etc/rancher/rke2')
        ssh.exec!("echo 'server: https://#{@config['master_nodes'].first['host']}:9345' > /etc/rancher/rke2/config.yaml")
        ssh.exec!("echo 'token: #{@token}' >> /etc/rancher/rke2/config.yaml")

        # 启动服务
        ssh.exec!('systemctl enable rke2-agent')
        ssh.exec!('systemctl start rke2-agent')
      end
    end

    def find_worker_node(node_name)
      @config['worker_nodes'].find { |node| node['name'] == node_name }
    end

    def drain_node(node_name)
      puts "Draining node #{node_name}..."
      system("kubectl drain #{node_name} --ignore-daemonsets --delete-emptydir-data --force")
    end

    def cleanup_worker(node_config)
      cleanup_commands = [
        'systemctl stop rke2-agent',
        'systemctl disable rke2-agent',
        'rm -rf /var/lib/rancher/rke2',
        'rm -rf /etc/rancher/rke2'
      ]

      cleanup_commands.each do |cmd|
        @ssh_manager.execute_command(node_config, cmd)
      end
    end

    def delete_node(node_name)
      puts "Deleting node #{node_name} from cluster..."
      system("kubectl delete node #{node_name}")
    end
  end
end
