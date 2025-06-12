#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'json'
require 'semantic'
require_relative 'logger_manager'

module RKE2
  class VersionManager
    attr_reader :config

    def initialize(config_path)
      @config_path = config_path
      @config = YAML.load_file(config_path)
      @logger = LoggerManager.create('version')
    end

    def check_versions
      @logger.info 'Checking component versions...'

      check_component_version('rke2', 'rancher/rke2')
      check_component_version('calico', 'projectcalico/calico')
      check_component_version('rancher', 'rancher/rancher')
      check_component_version('cert_manager', 'cert-manager/cert-manager')
      check_component_version('helm', 'helm/helm')
      check_component_version('kubectx', 'ahmetb/kubectx')
      check_kubectl_version

      update_config(@config['versions']) if @updated
    end

    def check_compatibility
      @logger.info 'Checking version compatibility...'

      rke2_version = get_rke2_version
      k8s_version = get_k8s_version

      compatibility_info = load_compatibility_info

      unless compatibility_info[k8s_version]
        @logger.warn "Warning: No compatibility information found for Kubernetes #{k8s_version}"
        return
      end

      check_component_compatibility('rke2', rke2_version, compatibility_info[k8s_version]['rke2'])
    end

    def update_config(new_versions)
      @config['versions'] = new_versions
      File.write(@config_path, @config.to_yaml)
      @logger.info 'Configuration updated successfully'
    rescue StandardError => e
      @logger.error "Error loading config: #{e.message}"
      raise
    end

    private

    def get_rke2_version
      @config['versions']['rke2']['version'].gsub(/^[vV]/, '').split('+').first
    end

    def get_k8s_version
      @config['versions']['kubernetes']['version'].gsub(/^[vV]/, '')
    end

    def get_kubectl_version
      @config['versions']['kubectl']['version']
    end

    def get_latest_rke2_version
      get_latest_github_release('rancher/rke2')
    end

    def get_latest_k8s_version
      get_latest_github_release('kubernetes/kubernetes')
    end

    def get_latest_kubectl_version
      get_latest_github_release('ahmetb/kubectx')
    end

    def load_compatibility_info
      # 实现加载兼容性信息的逻辑
      {
        '1.21.5' => {
          'rke2' => '~> 1.21.5'
        }
      }
    end

    def get_latest_github_release(repo)
      uri = URI("https://api.github.com/repos/#{repo}/releases/latest")
      response = Net::HTTP.get_response(uri)

      return unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)['tag_name']
    end

    def check_component_version(component, repo)
      latest_version = get_latest_github_release(repo)
      return unless latest_version

      current_version = @config['versions'][component]['version']
      return unless version_newer?(latest_version, current_version)

      @logger.info "New #{component} version available: #{latest_version}"
      @config['versions'][component]['version'] = latest_version
      @updated = true
    end

    def check_kubectl_version
      uri = URI('https://dl.k8s.io/release/stable.txt')
      response = Net::HTTP.get_response(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      latest_version = response.body.strip
      current_version = @config['versions']['kubectl']['version']

      return unless version_newer?(latest_version, current_version)

      @logger.info "New kubectl version available: #{latest_version}"
      @config['versions']['kubectl']['version'] = latest_version
      @updated = true
    end

    def version_newer?(version1, version2)
      # 移除版本号前缀
      v1 = version1.gsub(/^[vV]/, '')
      v2 = version2.gsub(/^[vV]/, '')

      # 处理 RKE2 特殊版本号格式
      if v1.include?('+') || v2.include?('+')
        v1 = v1.split('+').first
        v2 = v2.split('+').first
      end

      begin
        Semantic::Version.new(v1) > Semantic::Version.new(v2)
      rescue ArgumentError
        false
      end
    end

    def check_component_compatibility(component, actual_version, version_pattern)
      return if version_matches_pattern?(actual_version, version_pattern)

      @logger.warn "Warning: #{component} version #{actual_version} may not be compatible with current configuration"
      @logger.warn "Expected version pattern: #{version_pattern}"
    end

    def version_matches_pattern?(_version, _pattern)
      # 实现版本匹配逻辑
      true # 临时返回值
    end
  end
end
