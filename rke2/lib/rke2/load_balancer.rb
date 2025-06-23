# frozen_string_literal: true

require 'fileutils'
require 'net/ssh'
require 'net/scp'
require_relative 'base'

module RKE2
  # Load balancer configuration and management
  class LoadBalancer < Base
    def deploy_lb_nodes
      return if lb_nodes.empty?

      log('📋 部署负载均衡节点...')
      lb_nodes.each do |node|
        log("🔧 配置负载均衡器 #{node['name']} (#{node['ip']})")
        write_nginx_config(node)
        write_lb_install_script(node)
        deploy_to_node(node)
      end
    end

    private

    def write_nginx_config(node)
      server_ips = server_nodes.map { |n| n['ip'] }

      haproxy_config = generate_haproxy_config(server_ips)

      dir = "output/#{node['name']}"
      FileUtils.mkdir_p(dir)
      File.write("#{dir}/haproxy.cfg", haproxy_config)
    end

    def generate_haproxy_config(server_ips)
      <<~HAPROXY
        global
          daemon
          log stdout local0
          chroot /var/lib/haproxy
          stats socket /run/haproxy/admin.sock mode 660 level admin
          stats timeout 30s
          user haproxy
          group haproxy

        defaults
          mode tcp
          log global
          option tcplog
          option dontlognull
          option log-health-checks
          timeout connect 5000ms
          timeout client 50000ms
          timeout server 50000ms

        # Kubernetes API Server
        frontend kubernetes-api
          bind *:6443
          mode tcp
          default_backend kubernetes-api-backend

        backend kubernetes-api-backend
          mode tcp
          balance roundrobin
          option tcp-check
          #{server_ips.map { |ip| "server master-#{ip.gsub('.', '-')} #{ip}:6443 check" }.join("\n  ")}

        # RKE2 Registration Server
        frontend rke2-registration
          bind *:9345
          mode tcp
          default_backend rke2-registration-backend

        backend rke2-registration-backend
          mode tcp
          balance roundrobin
          option tcp-check
          #{server_ips.map { |ip| "server master-#{ip.gsub('.', '-')} #{ip}:9345 check" }.join("\n  ")}

        # Stats interface
        frontend stats
          bind *:8404
          mode http
          stats enable
          stats uri /stats
          stats refresh 30s
          stats admin if TRUE
      HAPROXY
    end

    def write_lb_install_script(node)
      script = <<~SH
        #!/bin/bash
        set -e
        echo "🚀 Installing HAProxy Load Balancer on #{node['name']}"

        # Install HAProxy
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update
          apt-get install -y haproxy
        elif command -v yum >/dev/null 2>&1; then
          yum install -y haproxy
        else
          echo "❌ 不支持的包管理器"
          exit 1
        fi

        # Backup original config
        cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup

        # Copy our configuration
        cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg

        # Test configuration
        haproxy -f /etc/haproxy/haproxy.cfg -c

        # Enable and start HAProxy
        systemctl enable haproxy
        systemctl restart haproxy

        # Check HAProxy status
        systemctl status haproxy --no-pager

        # Show listening ports
        echo "🔍 检查监听端口:"
        ss -tlnp | grep -E ':6443|:9345|:8404'

        echo "✅ HAProxy 负载均衡器配置完成"
        echo "📊 统计页面: http://#{node['ip']}:8404/stats"
      SH

      File.write("output/#{node['name']}/install.sh", script)
      FileUtils.chmod('+x', "output/#{node['name']}/install.sh")
    end

    def deploy_to_node(node)
      ip = node['ip']
      user = node['ssh_user'] || 'root'
      name = node['name']

      log("🔗 连接 #{name} (#{ip}) - #{node['role']}")

      begin
        Net::SSH.start(ip, user, timeout: 30) do |ssh|
          log("📤 上传文件到 #{name}...")
          ssh.exec!('mkdir -p /tmp')

          # Upload configuration file
          ssh.scp.upload!("output/#{name}/haproxy.cfg", '/tmp/haproxy.cfg')
          ssh.scp.upload!("output/#{name}/install.sh", '/tmp/install.sh')

          log("⚙️  在 #{name} 上执行安装...")
          output = ssh.exec!('sudo bash /tmp/install.sh 2>&1')
          log("📋 #{name} 安装输出:")
          log(output)

          log("✅ #{name} 部署完成")
        end
      rescue StandardError => e
        log("❌ #{name} 部署失败: #{e.message}")
        logger.error("#{name} deployment failed: #{e.message}")
      end
    end
  end
end
