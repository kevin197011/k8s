#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require 'net/scp'
require_relative 'logger_manager'

module RKE2
  class SSHManager
    def initialize(config)
      @config = config
      @ssh_config = config['ssh']
      @logger = LoggerManager.create('ssh')
    end

    def connect(node)
      options = {
        port: @ssh_config['port'] || 22,
        timeout: @ssh_config['connection_timeout'] || 30,
        number_of_password_prompts: @ssh_config['connection_retries'] || 3,
        non_interactive: true
      }

      if @ssh_config['private_key_path']
        options[:keys] = [@ssh_config['private_key_path']]
      elsif @ssh_config['password']
        options[:password] = @ssh_config['password']
      end

      Net::SSH.start(node['ip_address'], node['username'], options)
    end

    def execute_command(node, command)
      connect(node) do |ssh|
        @logger.info "Executing on #{node['name']}: #{command}"
        output = ssh.exec!(command)
        @logger.debug output if output
        output
      end
    end

    def upload_file(node, local_path, remote_path)
      connect(node) do |ssh|
        @logger.info "Uploading #{local_path} to #{node['name']}:#{remote_path}"
        ssh.scp.upload!(local_path, remote_path)
      end
    end

    def download_file(node, remote_path, local_path)
      connect(node) do |ssh|
        @logger.info "Downloading #{node['name']}:#{remote_path} to #{local_path}"
        ssh.scp.download!(remote_path, local_path)
      end
    end

    def test_connection(node)
      execute_command(node, 'echo "SSH connection test successful"')
      true
    rescue StandardError => e
      @logger.error "Failed to connect to #{node['name']}: #{e.message}"
      false
    end

    def setup_passwordless_ssh(node)
      return if @ssh_config['private_key_path'].nil?

      pub_key = File.read(@ssh_config['public_key_path'].gsub('~', ENV['HOME']))
      setup_commands = [
        'mkdir -p ~/.ssh',
        'chmod 700 ~/.ssh',
        "echo '#{pub_key}' >> ~/.ssh/authorized_keys",
        'chmod 600 ~/.ssh/authorized_keys'
      ]

      setup_commands.each do |cmd|
        execute_command(node, cmd)
      end
    end
  end
end
