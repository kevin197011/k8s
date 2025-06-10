#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'net/ssh'
require 'net/scp'
require 'fileutils'
require_relative 'version_manager'
require_relative 'node_manager'
require_relative 'system_optimizer'

module RKE2
  class ClusterManager
    attr_reader :config, :version_manager, :node_manager, :system_optimizer

    def initialize(config_file = 'config.yaml')
      @config = load_config(config_file)
      @version_manager = VersionManager.new
      @node_manager = NodeManager.new(@config)
      @system_optimizer = SystemOptimizer.new(@config)
    end

    def deploy
      puts 'Starting RKE2 cluster deployment...'

      # 检查版本更新
      check_versions

      # 部署主节点
      deploy_master_nodes

      # 部署工作节点
      deploy_worker_nodes

      # 设置本地 kubectl
      setup_local_kubectl

      # 安装 Rancher
      install_rancher

      puts 'RKE2 cluster deployment completed!'
      print_access_info
    end

    def optimize
      puts 'Starting cluster optimization...'
      system_optimizer.optimize_all
      puts 'Cluster optimization completed!'
    end

    def scale(action, node_info)
      case action
      when 'add'
        node_manager.add_worker(node_info)
      when 'remove'
        node_manager.remove_worker(node_info)
      else
        puts "Unknown action: #{action}"
      end
    end

    private

    def load_config(config_file)
      YAML.load_file(config_file)
    rescue StandardError => e
      puts "Error loading config: #{e.message}"
      exit 1
    end

    def check_versions
      version_manager.check_versions
      version_manager.check_compatibility
    end

    def deploy_master_nodes
      puts 'Deploying master nodes...'

      # 部署第一个主节点
      first_master = @config['master_nodes'].first
      node_manager.deploy_first_master(first_master)

      # 等待第一个主节点就绪
      sleep 30

      # 部署其他主节点
      @config['master_nodes'][1..-1].each do |node|
        node_manager.deploy_additional_master(node)
      end
    end

    def deploy_worker_nodes
      puts 'Deploying worker nodes...'
      @config['worker_nodes'].each do |node|
        node_manager.deploy_worker(node)
      end
    end

    def setup_local_kubectl
      puts 'Setting up local kubectl...'

      first_master = @config['master_nodes'].first
      kubeconfig_dir = File.expand_path('~/.kube')
      FileUtils.mkdir_p(kubeconfig_dir)

      Net::SCP.download!(
        first_master['host'],
        first_master['user'],
        '/etc/rancher/rke2/rke2.yaml',
        File.join(kubeconfig_dir, 'config')
      )

      # 更新 kubeconfig 中的服务器地址
      kubeconfig = File.read(File.join(kubeconfig_dir, 'config'))
      kubeconfig.gsub!('127.0.0.1', first_master['host'])
      File.write(File.join(kubeconfig_dir, 'config'), kubeconfig)
    end

    def install_rancher
      puts 'Installing Rancher...'

      # 创建命名空间
      system('kubectl create namespace cattle-system')

      # 安装 cert-manager
      cert_manager_url = "https://github.com/cert-manager/cert-manager/releases/download/#{version_manager.versions['cert_manager']['version']}/cert-manager.yaml"
      system("kubectl apply -f #{cert_manager_url}")

      sleep 30

      # 安装 Rancher
      system('helm repo add rancher-latest https://releases.rancher.com/server-charts/latest')
      system('helm repo update')

      rancher_version = version_manager.versions['rancher']['version']
      system(
        "helm install rancher rancher-latest/rancher \
        --namespace cattle-system \
        --version #{rancher_version} \
        --set hostname=#{@config['rancher']['hostname']} \
        --set bootstrapPassword=#{@config['rancher']['password']} \
        --set ingress.tls.source=rancher"
      )
    end

    def print_access_info
      puts "\nAccess Information:"
      puts "Rancher UI: https://#{@config['rancher']['hostname']}"
      puts "Username: admin"
      puts "Password: #{@config['rancher']['password']}"
      puts "\nTo use kubectl:"
      puts "export KUBECONFIG=~/.kube/config"
    end
  end
end
