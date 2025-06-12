#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'digest'
require 'fileutils'
require_relative 'logger_manager'

module RKE2
  class StateManager
    STATE_DIR = File.join(Dir.home, '.rke2', 'states')
    CURRENT_STATE_FILE = File.join(STATE_DIR, 'current_state.yaml')

    def initialize(cluster_name)
      @cluster_name = cluster_name
      @logger = LoggerManager.create('state')
      FileUtils.mkdir_p(STATE_DIR)
      load_current_state
    end

    def load_current_state
      @current_state = if File.exist?(CURRENT_STATE_FILE)
                         @logger.debug "Loading current state from #{CURRENT_STATE_FILE}"
                         YAML.load_file(CURRENT_STATE_FILE) || {}
                       else
                         @logger.info "No current state file found at #{CURRENT_STATE_FILE}, starting fresh"
                         {}
                       end
    end

    def save_current_state
      @logger.debug "Saving current state to #{CURRENT_STATE_FILE}"
      File.write(CURRENT_STATE_FILE, @current_state.to_yaml)
    end

    def record_state
      @logger.info "Recording state for cluster: #{@cluster_name}"
      new_state = {
        timestamp: Time.now.utc,
        cluster_name: @cluster_name,
        nodes: collect_node_states,
        components: collect_component_states,
        network: collect_network_state,
        resources: collect_resource_states
      }

      state_hash = calculate_state_hash(new_state)
      new_state[:hash] = state_hash

      @current_state = new_state
      save_current_state
      state_hash
    end

    def compare_states(old_hash = nil)
      return { status: :initial_state } unless old_hash

      old_state = @current_state
      new_state = record_state

      differences = {
        nodes: compare_nodes(old_state[:nodes], new_state[:nodes]),
        components: compare_components(old_state[:components], new_state[:components]),
        network: compare_network(old_state[:network], new_state[:network]),
        resources: compare_resources(old_state[:resources], new_state[:resources])
      }

      {
        status: differences.values.any? { |v| v[:changed] } ? :changed : :unchanged,
        changes: differences.select { |_, v| v[:changed] }
      }
    end

    private

    def collect_node_states
      # 收集节点状态
      nodes_json = JSON.parse(`kubectl get nodes -o json`)
      nodes_json['items'].map do |node|
        {
          name: node['metadata']['name'],
          status: node['status']['conditions'].find { |c| c['type'] == 'Ready' }['status'],
          roles: node['metadata']['labels'].select { |k, _| k.start_with?('node-role.kubernetes.io/') },
          version: node['status']['nodeInfo']['kubeletVersion']
        }
      end
    rescue StandardError
      []
    end

    def collect_component_states
      # 收集组件状态
      components = {}

      # 核心组件状态
      core_pods = JSON.parse(`kubectl get pods -n kube-system -o json`)
      components[:core] = core_pods['items'].map do |pod|
        {
          name: pod['metadata']['name'],
          status: pod['status']['phase'],
          restarts: pod['status']['containerStatuses']&.first&.dig('restartCount') || 0
        }
      end

      # RKE2 特定组件
      version = begin
        File.read('/var/lib/rancher/rke2/agent/version').strip
      rescue StandardError
        nil
      end

      components[:rke2] = {
        version: version,
        status: check_rke2_status
      }

      components
    rescue StandardError
      {}
    end

    def collect_network_state
      # 收集网络状态
      {
        pods: JSON.parse(`kubectl get pods -n calico-system -o json`)['items'].map do |pod|
          {
            name: pod['metadata']['name'],
            status: pod['status']['phase']
          }
        end,
        services: JSON.parse(`kubectl get services --all-namespaces -o json`)['items'].count
      }
    rescue StandardError
      {}
    end

    def collect_resource_states
      # 收集资源使用状态
      {
        pods: `kubectl get pods --all-namespaces --field-selector=status.phase=Running -o json`,
        deployments: `kubectl get deployments --all-namespaces -o json`,
        services: `kubectl get services --all-namespaces -o json`
      }
    rescue StandardError
      {}
    end

    def calculate_state_hash(state)
      @logger.debug 'Calculating state hash'
      Digest::SHA256.hexdigest(state.to_json)
    end

    def compare_nodes(old_nodes, new_nodes)
      changes = {
        added: new_nodes - old_nodes,
        removed: old_nodes - new_nodes,
        changed: new_nodes.select do |n|
          old_node = old_nodes.find { |o| o[:name] == n[:name] }
          old_node && (old_node != n)
        end
      }

      {
        changed: changes.values.any?(&:any?),
        details: changes
      }
    end

    def compare_components(old_components, new_components)
      changes = {
        core: compare_core_components(old_components[:core], new_components[:core]),
        rke2: old_components[:rke2] != new_components[:rke2]
      }

      {
        changed: changes.values.any?,
        details: changes
      }
    end

    def compare_network(old_network, new_network)
      changes = {
        pods: compare_network_pods(old_network[:pods], new_network[:pods]),
        services: old_network[:services] != new_network[:services]
      }

      {
        changed: changes.values.any?,
        details: changes
      }
    end

    def compare_resources(old_resources, new_resources)
      changes = %i[pods deployments services].map do |resource|
        [resource, old_resources[resource] != new_resources[resource]]
      end.to_h

      {
        changed: changes.values.any?,
        details: changes
      }
    end

    def check_rke2_status
      service_status = begin
        `systemctl is-active rke2-server.service`.strip
      rescue StandardError
        'unknown'
      end

      process_running = begin
        `pgrep rke2`.strip.split("\n").any?
      rescue StandardError
        false
      end

      {
        service: service_status,
        process: process_running
      }
    end

    def compare_core_components(old_core, new_core)
      old_core.map(&:to_json).sort != new_core.map(&:to_json).sort
    end

    def compare_network_pods(old_pods, new_pods)
      old_pods.map(&:to_json).sort != new_pods.map(&:to_json).sort
    end
  end
end
