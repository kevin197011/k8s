require 'net/ssh'
require 'fileutils'
require 'erb'
require 'logger'

module RKE2
  class NginxHAManager
    NGINX_CONFIG_DIR = '/etc/nginx'
    NGINX_SITES_DIR = "#{NGINX_CONFIG_DIR}/conf.d"
    NGINX_CONFIG_FILE = "#{NGINX_SITES_DIR}/k8s-apiserver.conf"
    NGINX_SSL_DIR = "#{NGINX_CONFIG_DIR}/ssl"

    def initialize(config)
      @config = config
      @master_nodes = config['master_nodes']
      @nginx_server = config.dig('api_server', 'nginx_server')
      @api_port = config.dig('api_server', 'port') || 6443
      @nginx_port = config.dig('api_server', 'nginx_port') || 8443
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO

      validate_config
    end

    def setup_nginx_lb
      @logger.info "Setting up Nginx load balancer for API Server..."
      setup_nginx_server
    end

    private

    def validate_config
      raise "Missing nginx_server configuration" unless @nginx_server
      raise "Missing nginx_server ip_address" unless @nginx_server['ip_address']
      raise "Missing nginx_server hostname" unless @nginx_server['hostname']
      raise "Missing nginx_server username" unless @nginx_server['username']
      raise "No master nodes configured" if @master_nodes.nil? || @master_nodes.empty?
    end

    def nginx_config_template
      <<~EOF
      # Nginx configuration for Kubernetes API Server Load Balancing
      user nginx;
      worker_processes auto;
      error_log /var/log/nginx/error.log notice;
      pid /var/run/nginx.pid;

      events {
          worker_connections 1024;
      }

      stream {
          log_format proxy '$remote_addr [$time_local] '
                         '$protocol $status $bytes_sent $bytes_received '
                         '$session_time "$upstream_addr"';

          access_log /var/log/nginx/k8s-access.log proxy;
          error_log  /var/log/nginx/k8s-error.log;

          upstream kubernetes {
              least_conn;  # 使用最少连接数算法
              <% @master_nodes.each do |node| %>
              server <%= node['ip_address'] %>:<%= @api_port %> max_fails=3 fail_timeout=30s;
              <% end %>
          }

          server {
              listen <%= @nginx_port %> ssl;
              proxy_connect_timeout 1s;
              proxy_timeout 3s;
              proxy_next_upstream on;

              ssl_certificate <%= NGINX_SSL_DIR %>/kube-api.crt;
              ssl_certificate_key <%= NGINX_SSL_DIR %>/kube-api.key;
              ssl_session_timeout 5m;
              ssl_protocols TLSv1.2 TLSv1.3;
              ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
              ssl_prefer_server_ciphers off;

              proxy_pass kubernetes;
          }
      }
      EOF
    end

    def setup_nginx_server
      @logger.info "Setting up Nginx on server: #{@nginx_server['hostname']}"

      begin
        Net::SSH.start(@nginx_server['ip_address'], @nginx_server['username'], verify_host_key: :never) do |ssh|
          # 安装 Nginx
          install_nginx(ssh)

          # 创建必要的目录
          create_directories(ssh)

          # 生成并上传 SSL 证书
          setup_ssl_certificates(ssh)

          # 配置 Nginx
          setup_nginx_config(ssh)

          # 启动服务
          start_nginx_service(ssh)
        end
      rescue Net::SSH::AuthenticationFailed
        @logger.error "Authentication failed for #{@nginx_server['hostname']}"
        raise
      rescue StandardError => e
        @logger.error "Error setting up Nginx on #{@nginx_server['hostname']}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end
    end

    def install_nginx(ssh)
      @logger.info "Installing Nginx..."
      execute_ssh_command(ssh, 'sudo apt-get update')
      execute_ssh_command(ssh, 'sudo apt-get install -y nginx nginx-extras')
    end

    def create_directories(ssh)
      execute_ssh_command(ssh, "sudo mkdir -p #{NGINX_SITES_DIR} #{NGINX_SSL_DIR}")
    end

    def setup_ssl_certificates(ssh)
      @logger.info "Setting up SSL certificates..."

      # 生成自签名证书
      cert_cmd = <<~SHELL
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout #{NGINX_SSL_DIR}/kube-api.key \
          -out #{NGINX_SSL_DIR}/kube-api.crt \
          -subj "/CN=kube-apiserver/O=Kubernetes"
      SHELL

      execute_ssh_command(ssh, cert_cmd)

      # 设置权限
      execute_ssh_command(ssh, "sudo chmod 644 #{NGINX_SSL_DIR}/kube-api.crt")
      execute_ssh_command(ssh, "sudo chmod 600 #{NGINX_SSL_DIR}/kube-api.key")
    end

    def setup_nginx_config(ssh)
      @logger.info "Configuring Nginx..."

      # 生成配置文件
      config_content = ERB.new(nginx_config_template).result(binding)

      # 上传配置
      execute_ssh_command(ssh, "cat > /tmp/k8s-apiserver.conf << 'EOL'\n#{config_content}\nEOL")
      execute_ssh_command(ssh, "sudo mv /tmp/k8s-apiserver.conf #{NGINX_CONFIG_FILE}")

      # 验证配置
      result = execute_ssh_command(ssh, 'sudo nginx -t')
      unless result.include?('successful')
        @logger.error "Nginx configuration test failed: #{result}"
        raise "Nginx configuration test failed"
      end
    end

    def start_nginx_service(ssh)
      @logger.info "Starting Nginx service..."

      # 重启 Nginx
      execute_ssh_command(ssh, 'sudo systemctl restart nginx')
      execute_ssh_command(ssh, 'sudo systemctl enable nginx')

      # 检查服务状态
      nginx_status = execute_ssh_command(ssh, 'sudo systemctl is-active nginx')
      @logger.info "Nginx status: #{nginx_status.strip}"

      unless nginx_status.strip == 'active'
        @logger.error "Nginx service failed to start"
        raise "Nginx service failed to start"
      end
    end

    def execute_ssh_command(ssh, command)
      @logger.debug "Executing: #{command}"
      result = ssh.exec!(command)
      @logger.debug "Result: #{result}"

      if $?.exitstatus && $?.exitstatus != 0
        @logger.error "Command failed: #{command}"
        @logger.error "Exit status: #{$?.exitstatus}"
        @logger.error "Output: #{result}"
        raise "Command failed: #{command}"
      end

      result
    end
  end
end
