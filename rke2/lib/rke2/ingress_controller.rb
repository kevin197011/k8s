# frozen_string_literal: true

module RKE2
  # Ingress Controller management and configuration
  class IngressController < Base
    def initialize(config_file)
      super
      @config_file = config_file
    end

    def configure_ingress_daemonset
      log('🔧 配置 Ingress Controller 为 DaemonSet 模式...')

      return if server_nodes.empty?

      first_server = server_nodes.first
      log("📝 在 #{first_server['name']} 上配置 Ingress DaemonSet...")

      begin
        Net::SSH.start(first_server['ip'], first_server['ssh_user'], timeout: 30) do |ssh|
          # Wait for cluster readiness
          log('⏳ 等待集群 API 完全就绪...')
          wait_for_api_ready(ssh)

          # Generate and apply Ingress DaemonSet configuration
          ingress_config = generate_ingress_daemonset_manifest
          ssh.scp.upload!(StringIO.new(ingress_config), '/tmp/nginx-ingress-daemonset.yaml')

          log('🚀 部署 Nginx Ingress Controller (DaemonSet 模式)...')

          # Apply configuration
          output = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl apply -f /tmp/nginx-ingress-daemonset.yaml 2>&1')
          log('📋 Ingress DaemonSet 部署输出:')
          log(output)

          # Wait for DaemonSet readiness
          log('⏳ 等待 Ingress DaemonSet 就绪...')
          ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl -n ingress-nginx rollout status daemonset/nginx-ingress-controller --timeout=300s')

          # Verify deployment status
          log('🔍 验证 Ingress Controller 状态...')
          status_output = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl -n ingress-nginx get daemonset,pods -o wide')
          log('📊 Ingress Controller 状态:')
          log(status_output)

          # Clean up
          ssh.exec!('rm -f /tmp/nginx-ingress-daemonset.yaml')

          log('✅ Ingress Controller DaemonSet 配置完成!')
        end
      rescue StandardError => e
        log("❌ Ingress DaemonSet 配置失败: #{e.message}")
        logger.error("Ingress DaemonSet configuration failed: #{e.message}")
      end
    end

    def fix_ingress_rbac
      log('🔧 修复 Ingress Controller RBAC 权限...')

      return if server_nodes.empty?

      first_server = server_nodes.first
      log("📝 在 #{first_server['name']} 上修复 Ingress RBAC 权限...")

      begin
        Net::SSH.start(first_server['ip'], first_server['ssh_user'], timeout: 30) do |ssh|
          # Wait for cluster readiness
          log('⏳ 等待集群 API 完全就绪...')
          wait_for_api_ready(ssh)

          # Generate and apply RBAC fix configuration
          rbac_fix_config = generate_rbac_fix_manifest
          ssh.scp.upload!(StringIO.new(rbac_fix_config), '/tmp/nginx-ingress-rbac-fix.yaml')

          log('🚀 应用修复的 RBAC 权限...')

          # Apply configuration
          output = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl apply -f /tmp/nginx-ingress-rbac-fix.yaml 2>&1')
          log('📋 RBAC 修复输出:')
          log(output)

          # Restart Ingress Pods to apply new permissions
          log('🔄 重启 Ingress Controller Pods...')
          restart_output = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl -n ingress-nginx rollout restart daemonset/nginx-ingress-controller 2>&1')
          log(restart_output)

          # Wait for restart completion
          log('⏳ 等待 Ingress Pods 重启完成...')
          ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl -n ingress-nginx rollout status daemonset/nginx-ingress-controller --timeout=300s')

          # Verify fix status
          log('🔍 验证 Ingress Controller 状态...')
          status_output = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl -n ingress-nginx get pods')
          log('📊 Ingress Controller 状态:')
          log(status_output)

          # Test permission fix
          log('🧪 测试权限修复...')
          test_output = ssh.exec!('export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /var/lib/rancher/rke2/bin/kubectl -n ingress-nginx logs daemonset/nginx-ingress-controller --tail=10 2>&1 | grep -E "(error|Error|forbidden|Forbidden)" || echo "No permission errors found"')
          log("权限测试结果: #{test_output}")

          # Clean up
          ssh.exec!('rm -f /tmp/nginx-ingress-rbac-fix.yaml')

          log('✅ Ingress Controller RBAC 权限修复完成!')
        end
      rescue StandardError => e
        log("❌ Ingress RBAC 权限修复失败: #{e.message}")
        logger.error("Ingress RBAC fix failed: #{e.message}")
      end
    end

    private

    def wait_for_api_ready(ssh)
      cluster_manager = ClusterManager.new(@config_file)
      cluster_manager.wait_for_api_ready(ssh)
    end

    def generate_ingress_daemonset_manifest
      <<~YAML
        apiVersion: v1
        kind: Namespace
        metadata:
          name: ingress-nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/instance: ingress-nginx
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: nginx-configuration
          namespace: ingress-nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        data:
          worker-processes: "auto"
          worker-connections: "16384"
          enable-real-ip: "true"
          use-gzip: "true"
          gzip-level: "6"
        ---
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: nginx-ingress-serviceaccount
          namespace: ingress-nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        ---
        #{generate_rbac_manifest}
        ---
        #{generate_daemonset_manifest}
        ---
        apiVersion: networking.k8s.io/v1
        kind: IngressClass
        metadata:
          name: nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        spec:
          controller: k8s.io/ingress-nginx
      YAML
    end

    def generate_rbac_manifest
      <<~YAML
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRole
        metadata:
          name: nginx-ingress-clusterrole
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        rules:
          - apiGroups: [""]
            resources: ["configmaps", "endpoints", "nodes", "pods", "secrets", "namespaces"]
            verbs: ["list", "watch", "get"]
          - apiGroups: [""]
            resources: ["services"]
            verbs: ["get", "list", "watch"]
          - apiGroups: ["networking.k8s.io"]
            resources: ["ingresses"]
            verbs: ["get", "list", "watch"]
          - apiGroups: [""]
            resources: ["events"]
            verbs: ["create", "patch"]
          - apiGroups: ["networking.k8s.io"]
            resources: ["ingresses/status"]
            verbs: ["update"]
          - apiGroups: ["networking.k8s.io"]
            resources: ["ingressclasses"]
            verbs: ["get", "list", "watch"]
          - apiGroups: ["coordination.k8s.io"]
            resources: ["leases"]
            verbs: ["list", "watch", "get", "update", "create"]
          - apiGroups: ["discovery.k8s.io"]
            resources: ["endpointslices"]
            verbs: ["list", "watch", "get"]
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: Role
        metadata:
          name: nginx-ingress-role
          namespace: ingress-nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        rules:
          - apiGroups: [""]
            resources: ["configmaps", "pods", "secrets", "namespaces"]
            verbs: ["get"]
          - apiGroups: [""]
            resources: ["configmaps"]
            resourceNames: ["ingress-controller-leader"]
            verbs: ["get", "update"]
          - apiGroups: [""]
            resources: ["configmaps"]
            verbs: ["create"]
          - apiGroups: ["coordination.k8s.io"]
            resources: ["leases"]
            verbs: ["get", "create", "update"]
          - apiGroups: [""]
            resources: ["endpoints"]
            verbs: ["get"]
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          name: nginx-ingress-role-nisa-binding
          namespace: ingress-nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: Role
          name: nginx-ingress-role
        subjects:
          - kind: ServiceAccount
            name: nginx-ingress-serviceaccount
            namespace: ingress-nginx
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: nginx-ingress-clusterrole-nisa-binding
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: nginx-ingress-clusterrole
        subjects:
          - kind: ServiceAccount
            name: nginx-ingress-serviceaccount
            namespace: ingress-nginx
      YAML
    end

    def generate_daemonset_manifest
      <<~YAML
        apiVersion: apps/v1
        kind: DaemonSet
        metadata:
          name: nginx-ingress-controller
          namespace: ingress-nginx
          labels:
            app.kubernetes.io/name: ingress-nginx
            app.kubernetes.io/part-of: ingress-nginx
            app.kubernetes.io/component: controller
        spec:
          selector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
              app.kubernetes.io/part-of: ingress-nginx
              app.kubernetes.io/component: controller
          template:
            metadata:
              labels:
                app.kubernetes.io/name: ingress-nginx
                app.kubernetes.io/part-of: ingress-nginx
                app.kubernetes.io/component: controller
              annotations:
                prometheus.io/port: "10254"
                prometheus.io/scrape: "true"
            spec:
              serviceAccountName: nginx-ingress-serviceaccount
              hostNetwork: true
              dnsPolicy: ClusterFirstWithHostNet
              nodeSelector:
                kubernetes.io/os: linux
              tolerations:
              - key: node-role.kubernetes.io/control-plane
                operator: Exists
                effect: NoSchedule
              - key: node-role.kubernetes.io/master
                operator: Exists
                effect: NoSchedule
              containers:
              - name: nginx-ingress-controller
                image: registry.k8s.io/ingress-nginx/controller:v1.8.2
                args:
                  - /nginx-ingress-controller
                  - --configmap=$(POD_NAMESPACE)/nginx-configuration
                  - --ingress-class=nginx
                  - --watch-ingress-without-class=true
                  - --http-port=80
                  - --https-port=443
                  - --healthz-port=10254
                  - --enable-ssl-passthrough
                securityContext:
                  allowPrivilegeEscalation: true
                  capabilities:
                    drop: [ALL]
                    add: [NET_BIND_SERVICE]
                  runAsUser: 101
                  runAsGroup: 82
                env:
                  - name: POD_NAME
                    valueFrom:
                      fieldRef:
                        fieldPath: metadata.name
                  - name: POD_NAMESPACE
                    valueFrom:
                      fieldRef:
                        fieldPath: metadata.namespace
                ports:
                - name: http
                  containerPort: 80
                  hostPort: 80
                  protocol: TCP
                - name: https
                  containerPort: 443
                  hostPort: 443
                  protocol: TCP
                - name: webhook
                  containerPort: 8443
                  protocol: TCP
                - name: metrics
                  containerPort: 10254
                  protocol: TCP
                livenessProbe:
                  httpGet:
                    path: /healthz
                    port: 10254
                    scheme: HTTP
                  initialDelaySeconds: 30
                  periodSeconds: 10
                  timeoutSeconds: 5
                  failureThreshold: 3
                readinessProbe:
                  httpGet:
                    path: /healthz
                    port: 10254
                    scheme: HTTP
                  periodSeconds: 10
                  timeoutSeconds: 5
                  failureThreshold: 3
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
                  limits:
                    cpu: 1000m
                    memory: 512Mi
      YAML
    end

    def generate_rbac_fix_manifest
      generate_rbac_manifest
    end
  end
end
