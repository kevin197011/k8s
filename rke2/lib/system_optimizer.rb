#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/ssh'
require 'json'

module RKE2
  class SystemOptimizer
    def initialize(config)
      @config = config
      @ssh_manager = SSHManager.new(config)
    end

    def optimize_all
      nodes = get_all_nodes
      nodes.each do |node|
        optimize_system(node)
        optimize_kubernetes(node)
      end

      optimize_calico
      optimize_rancher
      optimize_resources
    end

    private

    def get_all_nodes
      master_nodes = @config['master_nodes']
      worker_nodes = @config['worker_nodes']
      master_nodes + worker_nodes
    end

    def optimize_system(node)
      puts "Optimizing system settings on #{node['name']}..."

      # 系统参数优化
      create_sysctl_config(node)

      # 系统限制优化
      create_limits_config(node)

      # Docker 优化（如果使用）
      optimize_docker(node)

      # 应用系统参数
      @ssh_manager.execute_command(node, 'sysctl -p /etc/sysctl.d/99-kubernetes.conf')
    end

    def create_sysctl_config(node)
      sysctl_config = <<~CONFIG
        # 网络相关优化
        net.ipv4.ip_forward = 1
        net.bridge.bridge-nf-call-iptables = 1
        net.bridge.bridge-nf-call-ip6tables = 1
        net.ipv4.tcp_tw_recycle = 0
        net.ipv4.tcp_tw_reuse = 1
        net.ipv4.tcp_timestamps = 1
        net.ipv4.tcp_max_syn_backlog = 40960
        net.ipv4.tcp_max_tw_buckets = 6000000
        net.ipv4.tcp_keepalive_time = 1200
        net.ipv4.tcp_keepalive_probes = 3
        net.ipv4.tcp_keepalive_intvl = 15
        net.ipv4.tcp_fin_timeout = 15
        net.core.somaxconn = 65535
        net.core.netdev_max_backlog = 250000
        net.ipv4.tcp_max_orphans = 3276800
        net.ipv4.tcp_synack_retries = 2
        net.ipv4.tcp_syn_retries = 2

        # 文件系统和内存优化
        fs.file-max = 2097152
        fs.inotify.max_user_instances = 8192
        fs.inotify.max_user_watches = 524288
        vm.swappiness = 10
        vm.dirty_ratio = 60
        vm.dirty_background_ratio = 30
        vm.max_map_count = 262144

        # 内核优化
        kernel.pid_max = 65535
        kernel.threads-max = 65535
      CONFIG

      @ssh_manager.execute_command(node, "cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'\n#{sysctl_config}EOF")
    end

    def create_limits_config(node)
      limits_config = <<~CONFIG
        * soft nofile 1048576
        * hard nofile 1048576
        * soft nproc 65535
        * hard nproc 65535
        * soft memlock unlimited
        * hard memlock unlimited
      CONFIG

      @ssh_manager.execute_command(node, "cat > /etc/security/limits.d/kubernetes.conf << 'EOF'\n#{limits_config}EOF")
    end

    def optimize_docker(node)
      docker_config = {
        'exec-opts' => ['native.cgroupdriver=systemd'],
        'log-driver' => 'json-file',
        'log-opts' => {
          'max-size' => '100m',
          'max-file' => '3'
        },
        'storage-driver' => 'overlay2',
        'storage-opts' => [
          'overlay2.override_kernel_check=true'
        ],
        'max-concurrent-downloads' => 10,
        'max-concurrent-uploads' => 10,
        'registry-mirrors' => @config['registry_mirrors']['docker.io']
      }

      @ssh_manager.execute_command(node, 'mkdir -p /etc/docker')
      @ssh_manager.execute_command(node, "cat > /etc/docker/daemon.json << 'EOF'\n#{docker_config.to_json}EOF")
    end

    def optimize_kubernetes(node)
      # RKE2 优化配置
      create_rke2_optimization_config(node)

      # 如果是 master 节点，优化 etcd
      optimize_etcd(node) if @config['master_nodes'].include?(node)

      # 重启服务以应用更改
      restart_services(node)
    end

    def create_rke2_optimization_config(node)
      rke2_config = {
        'kubelet-arg' => [
          'max-pods=150',
          'kube-reserved=cpu=200m,memory=512Mi',
          'system-reserved=cpu=200m,memory=512Mi',
          'eviction-hard=memory.available<5%,nodefs.available<10%',
          'image-gc-high-threshold=85',
          'image-gc-low-threshold=80'
        ],
        'kube-apiserver-arg' => [
          'max-requests-inflight=1000',
          'max-mutating-requests-inflight=500',
          'default-watch-cache-size=1000'
        ],
        'kube-controller-manager-arg' => [
          'node-monitor-period=2s',
          'node-monitor-grace-period=16s',
          'pod-eviction-timeout=30s'
        ],
        'kube-scheduler-arg' => [
          'scheduler-name=default-scheduler'
        ]
      }.to_yaml

      @ssh_manager.execute_command(node, 'mkdir -p /etc/rancher/rke2/config.yaml.d')
      @ssh_manager.execute_command(node,
                                   "cat > /etc/rancher/rke2/config.yaml.d/optimization.yaml << 'EOF'\n#{rke2_config}EOF")
    end

    def optimize_etcd(node)
      etcd_config = {
        'etcd-arg' => [
          'quota-backend-bytes=8589934592',
          'auto-compaction-retention=8',
          'snapshot-count=10000'
        ]
      }.to_yaml

      @ssh_manager.execute_command(node, "cat > /etc/rancher/rke2/config.yaml.d/etcd.yaml << 'EOF'\n#{etcd_config}EOF")
    end

    def restart_services(node)
      if @config['master_nodes'].include?(node)
        @ssh_manager.execute_command(node, 'systemctl restart rke2-server')
      else
        @ssh_manager.execute_command(node, 'systemctl restart rke2-agent')
      end
    end

    def optimize_calico
      puts 'Optimizing Calico network settings...'
      # 在这里添加 Calico 网络优化的具体实现
    end

    def optimize_rancher
      puts 'Optimizing Rancher UI performance...'
      # 在这里添加 Rancher UI 优化的具体实现
    end

    def optimize_resources
      puts 'Optimizing node resource allocation...'
      # 在这里添加资源配额优化的具体实现
    end
  end
end
