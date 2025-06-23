# frozen_string_literal: true

module RKE2
  # Cluster diagnostics and monitoring
  class Diagnostics < Base
    def diagnose_cluster_status
      log('🔍 诊断集群状态...')

      server_nodes.each do |node|
        diagnose_node(node)
      end
    end

    def diagnose_node(node)
      log("\n📊 检查节点: #{node['name']} (#{node['ip']})")

      begin
        Net::SSH.start(node['ip'], node['ssh_user'], timeout: 15) do |ssh|
          # RKE2 service status
          log('🔧 RKE2 服务状态:')
          check_rke2_service_status(ssh)

          # Check critical processes
          log("\n🔄 关键进程状态:")
          check_critical_processes(ssh)

          # Process details
          log("\n🔍 进程详情:")
          check_process_details(ssh)

          # Recent logs
          log("\n📋 最近的 RKE2 日志 (最后5行):")
          check_recent_logs(ssh)

          # Network status
          log("\n🌐 网络状态:")
          check_network_status(ssh)

          # Cluster readiness
          log("\n🎯 集群就绪性检查:")
          check_cluster_readiness_status(ssh, node)

          # kubectl functionality test
          log("\n🧪 kubectl 功能测试:")
          test_kubectl_functionality(ssh)
        end
      rescue StandardError => e
        log("❌ 无法连接到 #{node['name']}: #{e.message}")
      end
    end

    private

    def check_rke2_service_status(ssh)
      rke2_status = ssh.exec!("systemctl is-active rke2-server 2>/dev/null || echo 'not-found'").strip
      rke2_state = ssh.exec!("systemctl is-enabled rke2-server 2>/dev/null || echo 'not-found'").strip
      log("  rke2-server: #{rke2_status} (#{rke2_state})")
    end

    def check_critical_processes(ssh)
      containerd_running = ssh.exec!('pgrep -f "containerd.*rke2" >/dev/null && echo "running" || echo "not_running"').strip
      kubelet_running = ssh.exec!('pgrep -f "kubelet.*rke2" >/dev/null && echo "running" || echo "not_running"').strip
      etcd_running = ssh.exec!('pgrep -f "etcd.*rke2" >/dev/null && echo "running" || echo "not_running"').strip

      log("  containerd: #{containerd_running}")
      log("  kubelet: #{kubelet_running}")
      log("  etcd: #{etcd_running}")
    end

    def check_process_details(ssh)
      process_count = ssh.exec!('ps aux | grep -E "(rke2|containerd|kubelet|etcd)" | grep -v grep | wc -l').strip
      log("  RKE2 相关进程总数: #{process_count}")
    end

    def check_recent_logs(ssh)
      recent_logs = ssh.exec!('journalctl -u rke2-server --no-pager -n 5 --since "2 minutes ago" 2>/dev/null || echo "无法获取日志"')
      log(recent_logs)
    end

    def check_network_status(ssh)
      api_port = ssh.exec!('ss -tlnp | grep ":6443" | wc -l').strip
      reg_port = ssh.exec!('ss -tlnp | grep ":9345" | wc -l').strip
      kubelet_port = ssh.exec!('ss -tlnp | grep ":10250" | wc -l').strip

      log("  API 服务器端口 (6443): #{api_port > '0' ? '✅ 监听中' : '❌ 未监听'}")
      log("  注册服务端口 (9345): #{reg_port > '0' ? '✅ 监听中' : '❌ 未监听'}")
      log("  Kubelet 端口 (10250): #{kubelet_port > '0' ? '✅ 监听中' : '❌ 未监听'}")
    end

    def check_cluster_readiness_status(ssh, _node)
      # Check if containerd process is running
      containerd_running = ssh.exec!('pgrep -f "containerd.*rke2" >/dev/null 2>&1 && echo "running" || echo "not_running"').strip

      # Check if kubelet process is running
      kubelet_running = ssh.exec!('pgrep -f "kubelet.*rke2" >/dev/null 2>&1 && echo "running" || echo "not_running"').strip

      # Check if kubectl is available and can access API
      kubectl_check = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl get nodes 2>/dev/null | wc -l').strip.to_i

      # Check if etcd is healthy
      etcd_check = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl get nodes --selector node-role.kubernetes.io/etcd 2>/dev/null | grep -c Ready || echo 0').strip.to_i

      # Check if API server is responding
      api_server_check = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && timeout 5 /var/lib/rancher/rke2/bin/kubectl cluster-info >/dev/null 2>&1 && echo "responding" || echo "not_responding"').strip

      ready = containerd_running == 'running' && kubelet_running == 'running' && kubectl_check > 1 && etcd_check.positive? && api_server_check == 'responding'
      status_msg = "containerd:#{containerd_running}, kubelet:#{kubelet_running}, kubectl_nodes:#{kubectl_check}, etcd_ready:#{etcd_check}, api_server:#{api_server_check}"

      log("  集群状态: #{ready ? '✅ 就绪' : '⏳ 未就绪'}")
      log("  详细信息: #{status_msg}")
    end

    def test_kubectl_functionality(ssh)
      kubectl_test = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && timeout 10 /var/lib/rancher/rke2/bin/kubectl get nodes --no-headers 2>/dev/null | wc -l').strip

      if kubectl_test.to_i > 0
        log("  ✅ kubectl 正常工作，发现 #{kubectl_test} 个节点")
      else
        log('  ❌ kubectl 无法正常工作')
      end
    end

    def quick_diagnosis
      log('🔍 快速诊断模式...')

      server_nodes.first(1).each do |node|
        log("📊 检查主节点: #{node['name']}")

        begin
          Net::SSH.start(node['ip'], node['ssh_user'], timeout: 10) do |ssh|
            # Basic service check
            status = ssh.exec!('systemctl is-active rke2-server').strip
            log("  RKE2 服务: #{status}")

            # Quick API test
            api_test = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && timeout 5 /var/lib/rancher/rke2/bin/kubectl cluster-info >/dev/null 2>&1 && echo "ok" || echo "fail"').strip
            log("  API 服务器: #{api_test == 'ok' ? '✅ 正常' : '❌ 异常'}")
          end
        rescue StandardError => e
          log("❌ 连接失败: #{e.message}")
        end
      end
    end

    def comprehensive_diagnosis
      log('🔍 全面诊断模式...')

      diagnose_cluster_status

      # Additional comprehensive checks
      log("\n🔧 额外检查:")
      check_system_resources
      check_disk_space
      check_network_connectivity
    end

    def check_system_resources
      log('📊 系统资源检查...')

      server_nodes.each do |node|
        Net::SSH.start(node['ip'], node['ssh_user'], timeout: 10) do |ssh|
          cpu_usage = ssh.exec!("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1").strip
          memory_usage = ssh.exec!("free | grep Mem | awk '{printf(\"%.1f%%\\n\", $3/$2 * 100.0)}'").strip
          load_avg = ssh.exec!("uptime | awk -F'load average:' '{print $2}'").strip

          log("  #{node['name']}: CPU #{cpu_usage}%, 内存 #{memory_usage}, 负载#{load_avg}")
        end
      rescue StandardError => e
        log("  #{node['name']}: 检查失败 - #{e.message}")
      end
    end

    def check_disk_space
      log('💾 磁盘空间检查...')

      server_nodes.each do |node|
        Net::SSH.start(node['ip'], node['ssh_user'], timeout: 10) do |ssh|
          disk_usage = ssh.exec!("df -h / | tail -1 | awk '{print $5}'").strip
          available = ssh.exec!("df -h / | tail -1 | awk '{print $4}'").strip

          log("  #{node['name']}: 使用率 #{disk_usage}, 可用 #{available}")
        end
      rescue StandardError => e
        log("  #{node['name']}: 检查失败 - #{e.message}")
      end
    end

    def check_network_connectivity
      log('🌐 网络连接检查...')

      server_nodes.each do |node|
        Net::SSH.start(node['ip'], node['ssh_user'], timeout: 10) do |ssh|
          # Test external connectivity
          internet_test = ssh.exec!("ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && echo 'ok' || echo 'fail'").strip
          dns_test = ssh.exec!("nslookup google.com >/dev/null 2>&1 && echo 'ok' || echo 'fail'").strip

          log("  #{node['name']}: 互联网 #{internet_test == 'ok' ? '✅' : '❌'}, DNS #{dns_test == 'ok' ? '✅' : '❌'}")
        end
      rescue StandardError => e
        log("  #{node['name']}: 检查失败 - #{e.message}")
      end
    end
  end
end
