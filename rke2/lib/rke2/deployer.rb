# frozen_string_literal: true

require_relative 'base'
require_relative 'node_initializer'
require_relative 'load_balancer'
require_relative 'config_generator'
require_relative 'node_deployer'
require_relative 'cluster_manager'
require_relative 'ingress_controller'
require_relative 'tools_installer'
require_relative 'diagnostics'

module RKE2
  # Main deployment orchestrator
  class Deployer < Base
    def initialize(config_file)
      super
      @config_file = config_file
      @node_initializer = NodeInitializer.new(config_file)
      @load_balancer = LoadBalancer.new(config_file)
      @config_generator = ConfigGenerator.new(config_file)
      @node_deployer = NodeDeployer.new(config_file)
      @cluster_manager = ClusterManager.new(config_file)
      @ingress_controller = IngressController.new(config_file)
      @tools_installer = ToolsInstaller.new(config_file)
      @diagnostics = Diagnostics.new(config_file)
    end

    def run
      log('🚀 开始 RKE2 集群部署')
      log("服务器节点: #{server_nodes.size} 个")
      log("工作节点: #{agent_nodes.size} 个")
      log("负载均衡节点: #{lb_nodes.size} 个")

      # Deployment steps
      @node_initializer.initialize_all_nodes
      @load_balancer.deploy_lb_nodes
      deploy_first_server
      deploy_additional_servers
      deploy_agent_nodes
      configure_ingress_daemonset

      log('🎉 RKE2 集群部署完成!')
    end

    # Public interface methods for accessing sub-modules
    attr_reader :diagnostics, :tools_installer, :ingress_controller, :cluster_manager

    def configure_ingress_daemonset
      @ingress_controller.configure_ingress_daemonset
    end

    def fix_ingress_rbac
      @ingress_controller.fix_ingress_rbac
    end

    def diagnose_cluster_status
      @diagnostics.diagnose_cluster_status
    end

    def configure_kubectl_on_servers
      @tools_installer.configure_kubectl_on_servers
    end

    def configure_kubectl_on_node(node)
      @tools_installer.configure_kubectl_on_node(node)
    end

    def install_k9s_helm_on_servers
      @tools_installer.install_k9s_helm_on_servers
    end

    def install_k9s_helm_on_node(node)
      @tools_installer.install_k9s_helm_on_node(node)
    end

    def monitor_startup_progress(node, max_wait_minutes = 15)
      @cluster_manager.monitor_startup_progress(node, max_wait_minutes)
    end

    def check_cluster_readiness(ssh, node)
      @cluster_manager.check_cluster_readiness(ssh, node)
    end

    private

    def deploy_first_server
      return if server_nodes.empty?

      first_server = server_nodes.first
      log("🔧 部署第一个服务器节点 #{first_server['name']}")

      @config_generator.write_config_file(first_server, true)
      @node_deployer.write_install_script(first_server)
      @node_deployer.deploy_to_node(first_server)

      @cluster_manager.wait_for_server_ready(first_server)
    end

    def deploy_additional_servers
      additional_servers = server_nodes[1..] || []
      return if additional_servers.empty?

      log('🔧 部署其他服务器节点...')
      additional_servers.each do |node|
        log("🔧 配置服务器节点 #{node['name']}")
        @config_generator.write_config_file(node, false)
        @node_deployer.write_install_script(node)
        @node_deployer.deploy_to_node(node)
      end
    end

    def deploy_agent_nodes
      return if agent_nodes.empty?

      log('🔧 部署工作节点...')
      agent_nodes.each do |node|
        log("🔧 配置工作节点 #{node['name']}")
        @config_generator.write_config_file(node, false)
        @node_deployer.write_install_script(node)
        @node_deployer.deploy_to_node(node)
      end
    end
  end
end
