# frozen_string_literal: true

require 'fileutils'
require_relative 'base'

module RKE2
  # Configuration file generation
  class ConfigGenerator < Base
    def write_config_file(node, is_first_server = false)
      content = case node['role']
                when 'server'
                  if is_first_server
                    generate_first_server_config(node)
                  else
                    generate_additional_server_config(node)
                  end
                when 'agent'
                  generate_agent_config(node)
                end

      return unless content

      dir = "output/#{node['name']}"
      FileUtils.mkdir_p(dir)
      File.write("#{dir}/config.yaml", content)
    end

    private

    def generate_first_server_config(node)
      <<~YAML
        token: #{token}
        node-name: #{node['name']}
        bind-address: 0.0.0.0
        advertise-address: #{node['ip']}
        tls-san:
          - "0.0.0.0"
          - "#{lb_ip}"
          - "#{node['ip']}"
        cni: canal
        write-kubeconfig-mode: "0644"
        cluster-init: true
      YAML
    end

    def generate_additional_server_config(node)
      <<~YAML
        server: https://#{lb_ip}:9345
        token: #{token}
        node-name: #{node['name']}
        bind-address: 0.0.0.0
        advertise-address: #{node['ip']}
        tls-san:
          - "0.0.0.0"
          - "#{lb_ip}"
          - "#{node['ip']}"
        cni: canal
        write-kubeconfig-mode: "0644"
      YAML
    end

    def generate_agent_config(node)
      <<~YAML
        server: https://#{lb_ip}:9345
        token: #{token}
        node-name: #{node['name']}
      YAML
    end
  end
end
