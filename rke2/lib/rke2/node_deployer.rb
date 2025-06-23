# frozen_string_literal: true

module RKE2
  # Node deployment and installation script management
  class NodeDeployer < Base
    def deploy_to_node(node)
      ip = node['ip']
      user = node['ssh_user'] || 'root'
      name = node['name']
      role = node['role']

      log("🔗 连接 #{name} (#{ip}) - #{role}")

      begin
        Net::SSH.start(ip, user, timeout: 30) do |ssh|
          log("📤 上传文件到 #{name}...")
          ssh.exec!('mkdir -p /tmp')

          # Upload configuration file
          if role == 'lb'
            ssh.scp.upload!("output/#{name}/haproxy.cfg", '/tmp/haproxy.cfg')
          else
            ssh.scp.upload!("output/#{name}/config.yaml", '/tmp/config.yaml')
          end

          # Upload install script
          ssh.scp.upload!("output/#{name}/install.sh", '/tmp/install.sh')

          log("⚙️  在 #{name} 上执行安装...")
          output = ssh.exec!('sudo bash /tmp/install.sh 2>&1')
          log("📋 #{name} 安装输出:")
          log(output)

          log("✅ #{name} 部署完成")
        end
      rescue StandardError => e
        log("❌ #{name} 部署失败: #{e.message}")
        logger.error("#{name} deployment failed: #{e.message}")
        logger.error(e.backtrace.join("\n"))
      end
    end

    def write_install_script(node)
      role = node['role']
      service = role == 'server' ? 'rke2-server' : 'rke2-agent'

      script = generate_base_install_script(node, role, service)

      # Add kubectl configuration for server nodes
      script += generate_kubectl_install_section if role == 'server'

      File.write("output/#{node['name']}/install.sh", script)
      FileUtils.chmod('+x', "output/#{node['name']}/install.sh")
    end

    private

    def generate_base_install_script(node, role, service)
      <<~SH
        #!/bin/bash
        set -e
        echo "🚀 Installing RKE2 (#{role}) on #{node['name']}"

        # Download and install RKE2
        curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=#{role} sh -

        # Create configuration directory
        mkdir -p /etc/rancher/rke2

        # Copy configuration file
        cp /tmp/config.yaml /etc/rancher/rke2/config.yaml

        # Set correct permissions
        chmod 600 /etc/rancher/rke2/config.yaml

        # Enable service
        systemctl enable #{service}

        # Start service
        systemctl restart #{service}

        echo "✅ RKE2 #{role} 安装完成"

        # Show service status
        systemctl status #{service} --no-pager
      SH
    end

    def generate_kubectl_install_section
      <<~SH

        echo "🔧 配置 kubectl for root 用户..."

        # Wait for kubeconfig file generation (max 60 seconds)
        echo "⏳ 等待 kubeconfig 文件生成..."
        for i in {1..12}; do
          if [ -f /etc/rancher/rke2/rke2.yaml ]; then
            break
          fi
          echo "  等待中... ($i/12)"
          sleep 5
        done

        if [ ! -f /etc/rancher/rke2/rke2.yaml ]; then
          echo "❌ kubeconfig 文件未找到，请稍后手动配置"
          exit 1
        fi

        # Create kubectl symlink to system PATH
        echo "🔗 创建 kubectl 软链接..."
        ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
        chmod +x /usr/local/bin/kubectl

        # Configure kubeconfig for root user
        echo "📝 为 root 用户配置 kubeconfig..."
        mkdir -p /root/.kube
        cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
        chmod 600 /root/.kube/config
        chown root:root /root/.kube/config

        # Set environment variables to root's bashrc
        echo "🔧 配置环境变量..."
        if ! grep -q "KUBECONFIG" /root/.bashrc; then
          echo "# RKE2 kubectl configuration" >> /root/.bashrc
          echo "export KUBECONFIG=/root/.kube/config" >> /root/.bashrc
          echo "export PATH=/var/lib/rancher/rke2/bin:\\$PATH" >> /root/.bashrc
          echo "alias k=kubectl" >> /root/.bashrc
        fi

        # Set environment variables to root's profile
        if ! grep -q "KUBECONFIG" /root/.profile; then
          echo "# RKE2 kubectl configuration" >> /root/.profile
          echo "export KUBECONFIG=/root/.kube/config" >> /root/.profile
          echo "export PATH=/var/lib/rancher/rke2/bin:\\$PATH" >> /root/.profile
        fi

        # Test kubectl configuration
        echo "🧪 测试 kubectl 配置..."
        export KUBECONFIG=/root/.kube/config
        export PATH=/var/lib/rancher/rke2/bin:\\$PATH

        # Wait for API server readiness
        echo "⏳ 等待 Kubernetes API 服务器就绪..."
        for i in {1..24}; do
          if kubectl cluster-info >/dev/null 2>&1; then
            echo "✅ API 服务器已就绪"
            break
          fi
          echo "  等待 API 服务器... ($i/24)"
          sleep 5
        done

        # Verify kubectl functionality
        echo "🔍 验证 kubectl 功能..."
        if kubectl get nodes >/dev/null 2>&1; then
          echo "✅ kubectl 配置成功！"
          echo "📊 当前集群节点:"
          kubectl get nodes
        else
          echo "⚠️  kubectl 配置可能需要更多时间生效"
        fi

        echo ""
        echo "🎉 kubectl 配置完成！"
        echo "💡 提示: 重新登录 root 用户后，可以直接使用以下命令:"
        echo "   kubectl get nodes"
        echo "   k get pods --all-namespaces"
        echo ""

        #{generate_tools_installation_section}
      SH
    end

    def generate_tools_installation_section
      <<~SH
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

        # Create k9s configuration directory
        echo "🔧 配置 k9s..."
        mkdir -p /root/.config/k9s

        # Create k9s basic configuration
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
  end
end
