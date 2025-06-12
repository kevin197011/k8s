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
      @logger.info 'Setting up Nginx load balancer for API Server...'
      setup_nginx_server
    end

    private

    def validate_config
      raise 'Missing nginx_server configuration' unless @nginx_server
      raise 'Missing nginx_server ip_address' unless @nginx_server['ip_address']
      raise 'Missing nginx_server hostname' unless @nginx_server['hostname']
      raise 'Missing nginx_server username' unless @nginx_server['username']
      raise 'No master nodes configured' if @master_nodes.nil? || @master_nodes.empty?
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
          # Update hosts file
          update_hosts_file(ssh)

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

    def update_hosts_file(ssh)
      @logger.info 'Updating hosts file...'

      # Check if entry already exists
      check_cmd = "grep -q '#{@nginx_server['ip_address']}.*#{@nginx_server['hostname']}' /etc/hosts"
      exists = execute_ssh_command(ssh, check_cmd, allow_non_zero_exit: true)

      if exists.empty?
        # Create hosts entry
        hosts_entry = "#{@nginx_server['ip_address']} #{@nginx_server['hostname']}"

        # First backup the hosts file
        execute_ssh_command(ssh, 'cp /etc/hosts /etc/hosts.bak')

        # Add the new entry
        execute_ssh_command(ssh, "echo '#{hosts_entry}' >> /etc/hosts")

        @logger.info 'Hosts file updated successfully'
      else
        @logger.info 'Hosts entry already exists, skipping update'
      end

      # Verify the entry
      execute_ssh_command(ssh, "cat /etc/hosts | grep '#{@nginx_server['hostname']}'")
    end

    def install_nginx(ssh)
      @logger.info 'Installing Nginx...'

      # Check if nginx is already installed
      nginx_check = execute_ssh_command(ssh, 'which nginx || true', allow_non_zero_exit: true)
      if nginx_check.strip != ''
        @logger.info 'Nginx is already installed, skipping installation'
        return
      end

      # Update package lists
      begin
        execute_ssh_command(ssh, 'DEBIAN_FRONTEND=noninteractive apt-get update', allow_non_zero_exit: true)
      rescue StandardError => e
        @logger.warn "apt-get update showed warnings but continuing: #{e.message}"
      end

      # Check package availability
      begin
        pkg_check = execute_ssh_command(ssh, 'apt-cache search nginx-extras', allow_non_zero_exit: true)
        @logger.info "Available nginx packages: #{pkg_check}"
      rescue StandardError => e
        @logger.warn "Package search warning: #{e.message}"
      end

      # Install nginx with detailed error capture
      begin
        # First try with just nginx
        @logger.info 'Attempting to install nginx...'
        execute_ssh_command(ssh, 'DEBIAN_FRONTEND=noninteractive apt-get install -y nginx')

        # Then try extras if available
        @logger.info 'Attempting to install nginx-extras...'
        execute_ssh_command(ssh, 'DEBIAN_FRONTEND=noninteractive apt-get install -y nginx-extras',
                            allow_non_zero_exit: true)
      rescue StandardError => e
        error_details = execute_ssh_command(ssh, 'cat /var/log/apt/term.log 2>/dev/null || true',
                                            allow_non_zero_exit: true)
        @logger.error "Failed to install nginx. APT logs: #{error_details}"
        raise "Failed to install nginx: #{e.message}"
      end
    end

    def create_directories(ssh)
      @logger.info 'Creating required directories...'

      # Check if directories already exist
      dir_check = execute_ssh_command(ssh,
                                      "[ -d #{NGINX_SITES_DIR} ] && [ -d #{NGINX_SSL_DIR} ] && echo 'exists' || echo 'not exists'", allow_non_zero_exit: true)

      if dir_check.strip == 'exists'
        @logger.info 'Required directories already exist'
        return
      end

      # Check if /etc/nginx exists
      nginx_dir_check = execute_ssh_command(ssh, '[ -d /etc/nginx ] && echo "exists" || echo "not exists"',
                                            allow_non_zero_exit: true)

      if nginx_dir_check.strip != 'exists'
        # If /etc/nginx doesn't exist, we need to create it first
        execute_ssh_command(ssh, 'mkdir -p /etc/nginx')
      end

      # Create required directories
      [NGINX_SITES_DIR, NGINX_SSL_DIR].each do |dir|
        # Create directory if it doesn't exist
        dir_exists = execute_ssh_command(ssh, "[ -d #{dir} ] && echo 'exists' || echo 'not exists'",
                                         allow_non_zero_exit: true)

        next unless dir_exists.strip != 'exists'

        execute_ssh_command(ssh, "mkdir -p #{dir}")
        # Set proper permissions
        execute_ssh_command(ssh, "chown -R nginx:nginx #{dir}")
        execute_ssh_command(ssh, "chmod 755 #{dir}")
      end
    end

    def setup_ssl_certificates(ssh)
      @logger.info 'Setting up SSL certificates...'

      # Check if certificates already exist
      cert_check = execute_ssh_command(ssh,
                                       "[ -f #{NGINX_SSL_DIR}/kube-api.crt ] && [ -f #{NGINX_SSL_DIR}/kube-api.key ] && echo 'exists' || echo 'not exists'",
                                       allow_non_zero_exit: true)

      if cert_check.strip == 'exists'
        @logger.info 'SSL certificates already exist'
        return
      end

      # Create temporary directory for certificate generation
      execute_ssh_command(ssh, 'mkdir -p /tmp/nginx-ssl')

      begin
        # Generate certificates in temporary directory
        cert_cmd = <<~SHELL
          cd /tmp/nginx-ssl && \
          openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout kube-api.key \
            -out kube-api.crt \
            -subj "/CN=kube-apiserver/O=Kubernetes"
        SHELL

        execute_ssh_command(ssh, cert_cmd)

        # Move certificates to final location
        execute_ssh_command(ssh, "mv /tmp/nginx-ssl/kube-api.key #{NGINX_SSL_DIR}/")
        execute_ssh_command(ssh, "mv /tmp/nginx-ssl/kube-api.crt #{NGINX_SSL_DIR}/")

        # Set proper permissions
        execute_ssh_command(ssh, "chown nginx:nginx #{NGINX_SSL_DIR}/kube-api.key #{NGINX_SSL_DIR}/kube-api.crt")
        execute_ssh_command(ssh, "chmod 600 #{NGINX_SSL_DIR}/kube-api.key")
        execute_ssh_command(ssh, "chmod 644 #{NGINX_SSL_DIR}/kube-api.crt")
      ensure
        # Clean up temporary directory
        execute_ssh_command(ssh, 'rm -rf /tmp/nginx-ssl', allow_non_zero_exit: true)
      end

      @logger.info 'SSL certificates setup completed'
    end

    def setup_nginx_config(ssh)
      @logger.info 'Configuring Nginx...'

      # 生成配置文件
      config_content = ERB.new(nginx_config_template).result(binding)

      # 上传配置
      execute_ssh_command(ssh, "cat > /tmp/k8s-apiserver.conf << 'EOL'\n#{config_content}\nEOL")
      execute_ssh_command(ssh, "mv /tmp/k8s-apiserver.conf #{NGINX_CONFIG_FILE}")

      # 验证配置
      result = execute_ssh_command(ssh, 'nginx -t')
      return if result.include?('successful')

      @logger.error "Nginx configuration test failed: #{result}"
      raise 'Nginx configuration test failed'
    end

    def start_nginx_service(ssh)
      @logger.info 'Starting Nginx service...'

      # 重启 Nginx
      execute_ssh_command(ssh, 'systemctl restart nginx')
      execute_ssh_command(ssh, 'systemctl enable nginx')

      # 检查服务状态
      nginx_status = execute_ssh_command(ssh, 'systemctl is-active nginx')
      @logger.info "Nginx status: #{nginx_status.strip}"

      return if nginx_status.strip == 'active'

      @logger.error 'Nginx service failed to start'
      raise 'Nginx service failed to start'
    end

    def execute_ssh_command(ssh, command, allow_non_zero_exit: false)
      @logger.debug "Executing: #{command}"
      result = ssh.exec!(command)
      @logger.debug "Result: #{result}"

      if $?.exitstatus && $?.exitstatus != 0 && !allow_non_zero_exit
        error_msg = "Command failed: #{command}\nExit status: #{$?.exitstatus}\nOutput: #{result}"
        @logger.error error_msg
        raise error_msg
      end

      result
    end
  end
end
