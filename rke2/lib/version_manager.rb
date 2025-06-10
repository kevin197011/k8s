#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'json'
require 'semantic'

module RKE2
  class VersionManager
    attr_reader :config

    def initialize(config_file = 'config.yaml')
      @config_file = config_file
      @config = load_config
    end

    def check_versions
      puts 'Checking component versions...'

      check_component_version('rke2', 'rancher/rke2')
      check_component_version('calico', 'projectcalico/calico')
      check_component_version('rancher', 'rancher/rancher')
      check_component_version('cert_manager', 'cert-manager/cert-manager')
      check_component_version('helm', 'helm/helm')
      check_component_version('kubectx', 'ahmetb/kubectx')
      check_kubectl_version

      save_config if @updated
    end

    def check_compatibility
      puts 'Checking version compatibility...'

      rke2_version = @config['versions']['rke2']['version'].gsub(/^[vV]/, '').split('+').first
      k8s_version = @config['versions']['kubernetes']['version'].gsub(/^[vV]/, '')

      # 检查 RKE2 和 Kubernetes 版本兼容性
      major_minor = k8s_version.split('.')[0..1].join('.')
      compat_key = "rke2_v#{major_minor}.x"

      if @config['compatibility_matrix'][compat_key]
        check_component_compatibility(compat_key)
      else
        puts "Warning: No compatibility information found for Kubernetes #{k8s_version}"
      end
    end

    private

    def load_config
      YAML.load_file(@config_file)
    rescue StandardError => e
      puts "Error loading config: #{e.message}"
      exit 1
    end

    def save_config
      File.write(@config_file, @config.to_yaml)
      puts 'Configuration updated successfully'
    end

    def get_latest_github_release(repo)
      uri = URI("https://api.github.com/repos/#{repo}/releases/latest")
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)['tag_name']
      else
        nil
      end
    end

    def check_component_version(component, repo)
      latest_version = get_latest_github_release(repo)
      return unless latest_version

      current_version = @config['versions'][component]['version']
      if version_newer?(latest_version, current_version)
        puts "New #{component} version available: #{latest_version}"
        @config['versions'][component]['version'] = latest_version
        @updated = true
      end
    end

    def check_kubectl_version
      uri = URI('https://dl.k8s.io/release/stable.txt')
      response = Net::HTTP.get_response(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      latest_version = response.body.strip
      current_version = @config['versions']['kubectl']['version']

      if version_newer?(latest_version, current_version)
        puts "New kubectl version available: #{latest_version}"
        @config['versions']['kubectl']['version'] = latest_version
        @updated = true
      end
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

    def check_component_compatibility(compat_key)
      matrix = @config['compatibility_matrix'][compat_key]

      matrix.each do |component, version_pattern|
        actual_version = @config['versions'][component]['version']
        pattern = version_pattern.gsub('x', '\\d+')

        unless actual_version.match?(/^v?#{pattern}/)
          puts "Warning: #{component} version #{actual_version} may not be compatible with current configuration"
          puts "Expected version pattern: #{version_pattern}"
        end
      end
    end
  end
end
