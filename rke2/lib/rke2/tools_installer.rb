# frozen_string_literal: true

module RKE2
  # Tools installation and configuration (kubectl, k9s, helm)
  class ToolsInstaller < Base
    def configure_kubectl_on_servers
      log('🔧 配置所有服务器节点的 kubectl...')

      server_nodes.each do |node|
        configure_kubectl_on_node(node)
      end
    end

    def configure_kubectl_on_node(node)
      return unless node['role'] == 'server'

      log("🔧 配置 #{node['name']} 的 kubectl...")

      begin
        Net::SSH.start(node['ip'], node['ssh_user'], timeout: 30) do |ssh|
          kubectl_config_script = generate_kubectl_config_script

          # Upload and execute configuration script
          ssh.scp.upload!(StringIO.new(kubectl_config_script), '/tmp/configure_kubectl.sh')
          ssh.exec!('chmod +x /tmp/configure_kubectl.sh')

          log("⚙️  在 #{node['name']} 上配置 kubectl...")
          output = ssh.exec!('sudo bash /tmp/configure_kubectl.sh 2>&1')
          log("📋 #{node['name']} kubectl 配置输出:")
          log(output)

          # Clean up
          ssh.exec!('rm -f /tmp/configure_kubectl.sh')

          log("✅ #{node['name']} kubectl 配置完成")
        end
      rescue StandardError => e
        log("❌ #{node['name']} kubectl 配置失败: #{e.message}")
        logger.error("#{node['name']} kubectl configuration failed: #{e.message}")
      end
    end

    def install_k9s_helm_on_servers
      log('📦 为所有服务器节点安装 k9s 和 helm...')

      server_nodes.each do |node|
        install_k9s_helm_on_node(node)
      end
    end

    def install_k9s_helm_on_node(node)
      return unless node['role'] == 'server'

      log("📦 为 #{node['name']} 安装 k9s 和 helm...")

      begin
        Net::SSH.start(node['ip'], node['ssh_user'], timeout: 30) do |ssh|
          k9s_helm_script = generate_k9s_helm_script

          # Upload and execute installation script
          ssh.scp.upload!(StringIO.new(k9s_helm_script), '/tmp/install_k9s_helm.sh')
          ssh.exec!('chmod +x /tmp/install_k9s_helm.sh')

          log("⚙️  在 #{node['name']} 上安装 k9s 和 helm...")
          output = ssh.exec!('sudo bash /tmp/install_k9s_helm.sh 2>&1')
          log("📋 #{node['name']} k9s 和 helm 安装输出:")
          log(output)

          # Clean up
          ssh.exec!('rm -f /tmp/install_k9s_helm.sh')

          log("✅ #{node['name']} k9s 和 helm 安装完成")
        end
      rescue StandardError => e
        log("❌ #{node['name']} k9s 和 helm 安装失败: #{e.message}")
        logger.error("#{node['name']} k9s and helm installation failed: #{e.message}")
      end
    end

    private

    def generate_kubectl_config_script
      <<~SH
        #!/bin/bash
        set -e
        echo "🔧 配置 kubectl for root 用户..."

        # Check if kubeconfig file exists
        if [ ! -f /etc/rancher/rke2/rke2.yaml ]; then
          echo "❌ RKE2 kubeconfig 文件不存在，请确保 RKE2 已正确安装"
          exit 1
        fi

        # Create kubectl symlink
        echo "🔗 创建 kubectl 软链接..."
        ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
        chmod +x /usr/local/bin/kubectl

        # Configure kubeconfig for root user
        echo "📝 为 root 用户配置 kubeconfig..."
        mkdir -p /root/.kube
        cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
        chmod 600 /root/.kube/config
        chown root:root /root/.kube/config

        # Configure environment variables
        echo "🔧 配置环境变量..."
        if ! grep -q "KUBECONFIG" /root/.bashrc; then
          echo "# RKE2 kubectl configuration" >> /root/.bashrc
          echo "export KUBECONFIG=/root/.kube/config" >> /root/.bashrc
          echo "export PATH=/var/lib/rancher/rke2/bin:\\$PATH" >> /root/.bashrc
          echo "alias k=kubectl" >> /root/.bashrc
        fi

        if ! grep -q "KUBECONFIG" /root/.profile; then
          echo "# RKE2 kubectl configuration" >> /root/.profile
          echo "export KUBECONFIG=/root/.kube/config" >> /root/.profile
          echo "export PATH=/var/lib/rancher/rke2/bin:\\$PATH" >> /root/.profile
        fi

        # Test kubectl configuration
        echo "🧪 测试 kubectl 配置..."
        export KUBECONFIG=/root/.kube/config
        export PATH=/var/lib/rancher/rke2/bin:\\$PATH

        # Verify kubectl functionality
        echo "🔍 验证 kubectl 功能..."
        if kubectl get nodes >/dev/null 2>&1; then
          echo "✅ kubectl 配置成功！"
          echo "📊 当前集群节点:"
          kubectl get nodes
        else
          echo "⚠️  kubectl 可能需要 API 服务器完全就绪后才能正常工作"
        fi

        echo ""
        echo "🎉 kubectl 配置完成！"
        echo "💡 提示: 重新登录 root 用户后，可以直接使用以下命令:"
        echo "   kubectl get nodes"
        echo "   k get pods --all-namespaces"
        echo ""
      SH
    end

    def generate_k9s_helm_script
      <<~SH
        #!/bin/bash
        set -e
        echo "📦 安装 k9s 和 helm..."

        # Install k9s
        echo "📦 安装 k9s..."
        K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\\1/')
        echo "  下载 k9s $K9S_VERSION..."

        # Detect system architecture
        ARCH=$(uname -m)
        case $ARCH in
          x86_64) K9S_ARCH="amd64" ;;
          aarch64) K9S_ARCH="arm64" ;;
          *) K9S_ARCH="amd64" ;;
        esac

        curl -sL "https://github.com/derailed/k9s/releases/download/$K9S_VERSION/k9s_Linux_$K9S_ARCH.tar.gz" -o /tmp/k9s.tar.gz
        tar -xzf /tmp/k9s.tar.gz -C /tmp
        mv /tmp/k9s /usr/local/bin/k9s
        chmod +x /usr/local/bin/k9s
        rm -f /tmp/k9s.tar.gz /tmp/LICENSE /tmp/README.md

        # Verify k9s installation
        if k9s version >/dev/null 2>&1; then
          echo "  ✅ k9s 安装成功: $(k9s version --short)"
        else
          echo "  ⚠️  k9s 安装可能有问题"
        fi

        # Install helm
        echo "📦 安装 helm..."
        curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod 700 /tmp/get_helm.sh
        HELM_INSTALL_DIR="/usr/local/bin" /tmp/get_helm.sh --no-sudo >/dev/null 2>&1
        rm -f /tmp/get_helm.sh

        # Verify helm installation
        if helm version >/dev/null 2>&1; then
          echo "  ✅ helm 安装成功: $(helm version --short)"
        else
          echo "  ⚠️  helm 安装可能有问题"
        fi

        # Initialize helm
        echo "🔧 初始化 helm..."
        export KUBECONFIG=/root/.kube/config
        helm repo add stable https://charts.helm.sh/stable >/dev/null 2>&1 || true
        helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
        helm repo update >/dev/null 2>&1 || true
        echo "  ✅ helm 仓库初始化完成"

        # Configure k9s
        echo "🔧 配置 k9s..."
        mkdir -p /root/.config/k9s

        # Create k9s configuration
        #{generate_k9s_config}

        echo ""
        echo "🎉 k9s 和 helm 安装完成！"
        echo ""
        echo "💡 可用工具："
        echo "   kubectl get nodes          # Kubernetes 命令行工具"
        echo "   k get pods --all-namespaces # kubectl 别名"
        echo "   k9s                        # 终端 UI 集群管理工具"
        echo "   helm list                  # Kubernetes 包管理器"
        echo ""
        echo "🚀 k9s 使用提示："
        echo "   - 按 ':' 进入命令模式"
        echo "   - 输入资源名称快速跳转 (pods, svc, deploy 等)"
        echo "   - 按 '?' 查看帮助"
        echo "   - 按 'Ctrl+C' 退出"
        echo ""
      SH
    end

    def generate_k9s_config
      <<~CONFIG
        cat > /root/.config/k9s/config.yml << 'EOF'
        k9s:
          liveViewAutoRefresh: true
          refreshRate: 2
          maxConnRetry: 5
          readOnly: false
          noExitOnCtrlC: false
          ui:
            enableMouse: true
            headless: false
            logoless: false
            crumbsless: false
            reactive: false
            noIcons: false
          skipLatestRevCheck: false
          disablePodCounting: false
          shellPod:
            image: busybox:1.35.0
            namespace: default
            limits:
              cpu: 100m
              memory: 100Mi
          imageScanner:
            enable: false
          logger:
            tail: 100
            buffer: 5000
            sinceSeconds: -1
            textWrap: false
            showTime: false
        EOF
      CONFIG
    end
  end
end
