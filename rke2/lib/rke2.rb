# frozen_string_literal: true

# RKE2 Deployment System - Modular Architecture v2.1.0
# This file serves as the unified entry point with all factory methods and backward compatibility

# Load all modular components
require_relative 'rke2/base'
require_relative 'rke2/node_initializer'
require_relative 'rke2/load_balancer'
require_relative 'rke2/config_generator'
require_relative 'rke2/node_deployer'
require_relative 'rke2/cluster_manager'
require_relative 'rke2/ingress_controller'
require_relative 'rke2/tools_installer'
require_relative 'rke2/diagnostics'
require_relative 'rke2/deployer'

module RKE2
  # Version information
  VERSION = '2.1.0'

  # Factory method to create a new deployer instance
  def self.new(config_file)
    Deployer.new(config_file)
  end

  # Factory method to create diagnostic instance
  def self.diagnostics(config_file)
    Diagnostics.new(config_file)
  end

  # Factory method to create tools installer instance
  def self.tools_installer(config_file)
    ToolsInstaller.new(config_file)
  end

  # Factory method to create ingress controller instance
  def self.ingress_controller(config_file)
    IngressController.new(config_file)
  end

  # Factory method to create cluster manager instance
  def self.cluster_manager(config_file)
    ClusterManager.new(config_file)
  end

  # Factory method to create node deployer instance
  def self.node_deployer(config_file)
    NodeDeployer.new(config_file)
  end

  # Factory method to create load balancer instance
  def self.load_balancer(config_file)
    LoadBalancer.new(config_file)
  end

  # Factory method to create config generator instance
  def self.config_generator(config_file)
    ConfigGenerator.new(config_file)
  end

  # Factory method to create node initializer instance
  def self.node_initializer(config_file)
    NodeInitializer.new(config_file)
  end

  # Convenience method for quick diagnosis
  def self.quick_diagnosis(config_file)
    diagnostics(config_file).quick_diagnosis
  end

  # Convenience method for comprehensive diagnosis
  def self.comprehensive_diagnosis(config_file)
    diagnostics(config_file).comprehensive_diagnosis
  end

  # Convenience method for standard diagnosis
  def self.standard_diagnosis(config_file)
    diagnostics(config_file).standard_diagnosis
  end
end

# Backward compatibility - maintain the original class interface
class RKE2Deployer < RKE2::Deployer
end
