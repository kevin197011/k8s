#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require 'net/scp'

module RKE2
  class NodeManager
    def initialize(config)
      @config = config
      @ssh_key_path = File.expand_path('~/.ssh/id_rsa')
      ensure_ssh_key
    end

    def deploy_first_master(node)
      puts "Deploying first master node: #{node['host']}"

      copy_ssh_key(node)
      install_rke2_server(node, true)

      # 获取节点令牌
      @token = get_node_token(node)
    end

    def deploy_additional_master(node)
      puts "Deploying additional master node: #{node['host']}"

      copy_ssh_key(node)
      install_rke2_server(node, false)
    end

    def deploy_worker(node)
      puts "Deploying worker node: #{node['host']}"

      copy_ssh_key(node)
      install_rke2_agent(node)
    end

    def add_worker(node_info)
      puts "Adding worker node: #{node_info['host']}"

      node = {
        'host' => node_info['host'],
        'user' => node_info['user'] || @config['default_user'],
        'name' => node_info['name']
      }

      deploy_worker(node)
    end

    def remove_worker(node_info)
      puts "Removing worker node: #{node_info['name']}"

      # 排空节点
      system("kubectl drain #{node_info['name']} --ignore-daemonsets --delete-emptydir-data")

      # 停止服务
      Net::SSH.start(node_info['host'], node_info['user']) do |ssh|
        ssh.exec!('systemctl stop rke2-agent')
        ssh.exec!('systemctl disable rke2-agent')
        ssh.exec!('rm -rf /var/lib/rancher/rke2')
      end

      # 从集群中删除节点
      system("kubectl delete node #{node_info['name']}")
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
  end
end
