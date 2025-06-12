#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require 'net/scp'
require 'tempfile'
require_relative 'logger_manager'

module RKE2
  class HostsManager
    HOSTS_FILE = '/etc/hosts'
    HOSTS_BACKUP = '/etc/hosts.bak'
    MARKER_START = '# BEGIN RKE2 CLUSTER HOSTS'
    MARKER_END = '# END RKE2 CLUSTER HOSTS'

    def initialize(config)
      @config = config
      @logger = LoggerManager.create('hosts')
      @all_nodes = (@config['master_nodes'] + @config['worker_nodes']).map do |node|
        {
          ip: node['ip_address'],
          hostname: node['hostname'],
          username: node['username']
        }
      end
    end

    def update_hosts_files
      nodes = @config['nodes'] || []
      master_nodes = @config['master_nodes'] || []
      worker_nodes = @config['worker_nodes'] || []

      all_nodes = nodes + master_nodes + worker_nodes
      all_nodes.uniq! { |node| node['ip_address'] }

      # 生成 hosts 文件内容
      hosts_content = generate_hosts_content(all_nodes)

      # 更新每个节点的 hosts 文件
      all_nodes.each do |node|
        update_node_hosts(node['ip_address'], node['username'], hosts_content)
      end
    end

    def update_nginx_hosts(nginx_server)
      @logger.info "Updating hosts file on #{nginx_server['hostname']}..."

      begin
        Net::SSH.start(nginx_server['ip_address'], nginx_server['username'], verify_host_key: :never) do |ssh|
          update_hosts_with_cloud_init(ssh, nginx_server)
        end
      rescue Net::SSH::AuthenticationFailed
        @logger.error "Authentication failed for #{nginx_server['hostname']}"
        raise
      rescue StandardError => e
        @logger.error "Error updating hosts on #{nginx_server['hostname']}: #{e.message}"
        raise
      end
    end

    private

    def write_file_content(ssh, content, target_file)
      @logger.info "Writing content to #{target_file}..."

      # Create a temporary file locally
      temp_file = Tempfile.new('hosts')
      begin
        temp_file.write(content)
        temp_file.flush

        # Upload the file using SCP
        ssh.scp.upload!(temp_file.path, target_file)
      ensure
        temp_file.close
        temp_file.unlink
      end
    end

    def update_hosts_with_cloud_init(ssh, server)
      # Check if system is using cloud-init to manage hosts
      cloud_init_check = execute_ssh_command(ssh,
                                             '[ -f /etc/cloud/cloud.cfg ] && grep -q "^manage_etc_hosts:" /etc/cloud/cloud.cfg && echo "yes" || echo "no"',
                                             allow_non_zero_exit: true)

      if cloud_init_check.strip == 'yes'
        @logger.info 'System is using cloud-init to manage hosts file'
        update_cloud_init_hosts(ssh, server)
      else
        update_hosts_file_direct(ssh, server)
      end

      # Verify the entry
      result = execute_ssh_command(ssh, "cat /etc/hosts | grep '#{server['hostname']}'")
      @logger.info "Current hosts entry: #{result.strip}"
    end

    def update_cloud_init_hosts(ssh, server)
      # Check if template file exists
      template_exists = execute_ssh_command(ssh,
                                            '[ -f /etc/cloud/templates/hosts.debian.tmpl ] && echo "yes" || echo "no"',
                                            allow_non_zero_exit: true)

      if template_exists.strip == 'yes'
        update_hosts_template(ssh, server)
      else
        # If template doesn't exist, disable cloud-init hosts management
        @logger.info 'Disabling cloud-init hosts management...'
        execute_ssh_command(ssh, "sed -i 's/manage_etc_hosts: true/manage_etc_hosts: false/' /etc/cloud/cloud.cfg")
        update_hosts_file_direct(ssh, server)
      end
    end

    def update_hosts_template(ssh, server)
      @logger.info 'Updating hosts template file...'
      current_template = execute_ssh_command(ssh, 'cat /etc/cloud/templates/hosts.debian.tmpl',
                                             allow_non_zero_exit: true)

      # Remove old entry if exists and add new one
      hosts_entry = "#{server['ip_address']} #{server['hostname']}"
      new_lines = current_template.lines.reject do |line|
        line.include?(server['hostname']) || line.strip.empty?
      end

      # Add entry before the IPv6 section if it exists
      ipv6_index = new_lines.find_index { |line| line.include?('# The following lines are desirable for IPv6') }
      if ipv6_index
        new_lines.insert(ipv6_index, "#{hosts_entry}\n")
      else
        new_lines << "#{hosts_entry}\n"
      end

      new_content = new_lines.join

      # Write to temporary file first, then move it
      remote_temp = "/tmp/hosts.tmpl.#{Time.now.to_i}"
      write_file_content(ssh, new_content, remote_temp)
      execute_ssh_command(ssh, "mv #{remote_temp} /etc/cloud/templates/hosts.debian.tmpl")

      # Force cloud-init to update hosts file
      execute_ssh_command(ssh, 'cloud-init single --name cc_update_etc_hosts --frequency always',
                          allow_non_zero_exit: true)
    end

    def update_hosts_file_direct(ssh, server)
      @logger.info 'Updating hosts file directly...'

      # Read current hosts file content
      current_content = execute_ssh_command(ssh, 'cat /etc/hosts', allow_non_zero_exit: true)

      # Create new content by removing old entry if exists and adding new one
      hosts_entry = "#{server['ip_address']} #{server['hostname']}"
      new_lines = current_content.lines.reject do |line|
        line.include?(server['hostname']) || line.strip.empty?
      end

      # Add entry before the IPv6 section if it exists
      ipv6_index = new_lines.find_index { |line| line.include?('# The following lines are desirable for IPv6') }
      if ipv6_index
        new_lines.insert(ipv6_index, "#{hosts_entry}\n")
      else
        new_lines << "#{hosts_entry}\n"
      end

      new_content = new_lines.join

      # Write to temporary file first, then move it
      remote_temp = "/tmp/hosts.#{Time.now.to_i}"
      write_file_content(ssh, new_content, remote_temp)
      execute_ssh_command(ssh, "mv #{remote_temp} /etc/hosts")

      @logger.info 'Hosts file updated successfully'
    end

    def generate_hosts_content(nodes)
      content = "127.0.0.1 localhost\n"
      content += "::1 localhost ip6-localhost ip6-loopback\n"
      content += "fe00::0 ip6-localnet\n"
      content += "ff00::0 ip6-mcastprefix\n"
      content += "ff02::1 ip6-allnodes\n"
      content += "ff02::2 ip6-allrouters\n\n"

      nodes.each do |node|
        content += "#{node['ip_address']} #{node['hostname']}\n"
      end

      content
    end

    def update_node_hosts(ip, username, content)
      @logger.info "Updating hosts file on #{ip}..."

      begin
        Net::SSH.start(ip, username, verify_host_key: :never) do |ssh|
          ssh.exec!("echo '#{content}' | sudo tee /etc/hosts")
        end
      rescue Net::SSH::AuthenticationFailed
        @logger.error "Authentication failed for #{ip}"
        raise
      rescue StandardError => e
        @logger.error "Error updating hosts on #{ip}: #{e.message}"
        raise
      end
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
