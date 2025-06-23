# frozen_string_literal: true

module RKE2
  # Cluster management and monitoring
  class ClusterManager < Base
    def wait_for_server_ready(node)
      log("⏳ 等待服务器节点 #{node['name']} 就绪...")

      max_attempts = 30
      attempt = 0

      while attempt < max_attempts
        begin
          Net::SSH.start(node['ip'], node['ssh_user'], timeout: 10) do |ssh|
            # Check service status
            status = ssh.exec!('systemctl is-active rke2-server').strip
            if status == 'active'
              # Further check if service is truly ready
              ready_status = check_cluster_readiness(ssh, node)
              if ready_status[:ready]
                log("✅ 服务器节点 #{node['name']} 已完全就绪")
                return true
              else
                log("⏳ 服务运行中但组件仍在初始化... #{ready_status[:status]}")
              end
            else
              log("⏳ 服务状态: #{status}")
            end
          end
        rescue StandardError => e
          log("⏳ 尝试 #{attempt + 1}/#{max_attempts}: #{e.message}")
        end

        attempt += 1
        sleep(30)
      end

      log("⚠️  服务器节点 #{node['name']} 可能需要更多时间启动")
      false
    end

    def check_cluster_readiness(ssh, _node)
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

      if containerd_running == 'running' && kubelet_running == 'running' && kubectl_check > 1 && etcd_check.positive? && api_server_check == 'responding'
        return { ready: true, status: 'All components operational' }
      end

      status_msg = "containerd:#{containerd_running}, kubelet:#{kubelet_running}, kubectl_nodes:#{kubectl_check}, etcd_ready:#{etcd_check}, api_server:#{api_server_check}"
      { ready: false, status: status_msg }
    rescue StandardError => e
      { ready: false, status: "Check failed: #{e.message}" }
    end

    def wait_for_api_ready(ssh)
      max_attempts = 20
      attempt = 0

      while attempt < max_attempts
        begin
          result = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && timeout 10 /var/lib/rancher/rke2/bin/kubectl get nodes >/dev/null 2>&1 && echo "ready"').strip
          if result == 'ready'
            log('✅ API 服务器已就绪')
            return true
          end
        rescue StandardError => e
          log("⏳ 等待 API 就绪... (#{attempt + 1}/#{max_attempts}): #{e.message}")
        end

        attempt += 1
        sleep(15)
      end

      log('⚠️ API 服务器等待超时，但继续配置...')
      false
    end

    def monitor_startup_progress(node, max_wait_minutes = 15)
      log("🔄 监控 #{node['name']} 启动进度 (最大等待 #{max_wait_minutes} 分钟)...")

      start_time = Time.now
      last_status = ''

      while (Time.now - start_time) < (max_wait_minutes * 60)
        begin
          Net::SSH.start(node['ip'], node['ssh_user'], timeout: 10) do |ssh|
            # Get latest status message
            recent_log = ssh.exec!('journalctl -u rke2-server --no-pager -n 1 --since "30 seconds ago" -o cat 2>/dev/null | tail -1').strip

            if recent_log != last_status && !recent_log.empty?
              log("📝 #{Time.now.strftime('%H:%M:%S')}: #{recent_log}")
              last_status = recent_log
            end

            # Check for service failure
            service_failed = ssh.exec!('systemctl is-failed rke2-server 2>/dev/null').strip
            if service_failed == 'failed'
              log('❌ RKE2 服务失败,检查详细日志:')
              error_logs = ssh.exec!('journalctl -u rke2-server --no-pager -n 20 | tail -10')
              log(error_logs)
              return false
            end

            # Check if ready
            ready_check = check_cluster_readiness(ssh, node)
            if ready_check[:ready]
              log("✅ #{node['name']} 启动完成!")
              return true
            end
          end
        rescue StandardError => e
          log("⚠️  监控连接问题: #{e.message}")
        end

        sleep(30)
      end

      log('⏰ 监控超时,但这不一定意味着失败')
      false
    end
  end
end
