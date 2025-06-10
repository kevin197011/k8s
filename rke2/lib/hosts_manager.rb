require 'net/ssh'
require 'tempfile'
require 'fileutils'

module RKE2
  class HostsManager
    HOSTS_FILE = '/etc/hosts'
    HOSTS_BACKUP = '/etc/hosts.bak'
    MARKER_START = '# BEGIN RKE2 CLUSTER HOSTS'
    MARKER_END = '# END RKE2 CLUSTER HOSTS'

    def initialize(config)
      @config = config
      @all_nodes = (@config['master_nodes'] + @config['worker_nodes']).map do |node|
        {
          ip: node['ip_address'],
          hostname: node['hostname'],
          username: node['username']
        }
      end
    end

    def update_all_hosts
      # 更新本地 hosts 文件
      update_local_hosts

      # 更新所有节点的 hosts 文件
      @all_nodes.each do |node|
        update_remote_hosts(node)
      end
    end

    private

    def generate_hosts_entries
      entries = ["#{MARKER_START}"]
      @all_nodes.each do |node|
        entries << "#{node[:ip]} #{node[:hostname]}"
      end
      entries << MARKER_END
      entries.join("\n")
    end

    def update_local_hosts
      puts "Updating local hosts file..."

      # 备份原始 hosts 文件
      FileUtils.cp(HOSTS_FILE, HOSTS_BACKUP, preserve: true) unless File.exist?(HOSTS_BACKUP)

      # 读取当前 hosts 文件
      current_content = File.read(HOSTS_FILE)

      # 移除旧的 RKE2 条目
      new_content = remove_existing_entries(current_content)

      # 添加新的条目
      new_content = "#{new_content}\n#{generate_hosts_entries}\n"

      # 使用临时文件写入新内容
      temp_file = Tempfile.new('hosts')
      begin
        temp_file.write(new_content)
        temp_file.close

        # 使用 sudo 更新 hosts 文件
        system("sudo cp #{temp_file.path} #{HOSTS_FILE}")
        system("sudo chmod 644 #{HOSTS_FILE}")
      ensure
        temp_file.unlink
      end
    end

    def update_remote_hosts(node)
      puts "Updating hosts file on #{node[:hostname]}..."

      Net::SSH.start(node[:ip], node[:username]) do |ssh|
        # 检查是否有 sudo 权限
        has_sudo = ssh.exec!('sudo -n true 2>/dev/null') ? true : false
        sudo_cmd = has_sudo ? 'sudo' : ''

        # 备份远程 hosts 文件
        ssh.exec!("#{sudo_cmd} cp #{HOSTS_FILE} #{HOSTS_BACKUP}") unless
          ssh.exec!("test -f #{HOSTS_BACKUP} && echo 'exists'") == 'exists'

        # 读取当前 hosts 文件
        current_content = ssh.exec!("cat #{HOSTS_FILE}")

        # 移除旧的 RKE2 条目
        new_content = remove_existing_entries(current_content)

        # 添加新的条目
        new_content = "#{new_content}\n#{generate_hosts_entries}\n"

        # 使用临时文件写入新内容
        remote_temp = "/tmp/hosts.#{Time.now.to_i}"
        ssh.exec!("cat > #{remote_temp} << 'EOL'\n#{new_content}\nEOL")

        # 更新 hosts 文件
        ssh.exec!("#{sudo_cmd} cp #{remote_temp} #{HOSTS_FILE}")
        ssh.exec!("#{sudo_cmd} chmod 644 #{HOSTS_FILE}")
        ssh.exec!("rm #{remote_temp}")
      end
    rescue Net::SSH::AuthenticationFailed
      puts "Authentication failed for #{node[:hostname]}"
    rescue StandardError => e
      puts "Error updating hosts on #{node[:hostname]}: #{e.message}"
    end

    def remove_existing_entries(content)
      lines = content.lines
      start_index = lines.find_index { |line| line.strip == MARKER_START }
      end_index = lines.find_index { |line| line.strip == MARKER_END }

      if start_index && end_index
        lines = lines[0...start_index] + lines[(end_index + 1)..-1]
      end

      lines.join.strip
    end
  end
end
