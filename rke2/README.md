# RKE2 集群自动化部署工具

一个简洁高效的 RKE2 Kubernetes 集群自动化部署工具，使用 Ruby 实现，专注于核心功能和稳定性。

## ✨ 功能特点

- 🚀 **自动化部署**: 一键部署完整的 RKE2 高可用集群
- 🔧 **多节点类型**: 支持主节点、工作节点和负载均衡节点
- ⚡ **性能优化**: 自动进行节点初始化和系统性能优化
- 🔒 **TLS 安全**: 自动配置和管理 TLS 证书
- 🌐 **Ingress DaemonSet**: 自动部署 Nginx Ingress Controller 为 DaemonSet 模式
- 🎯 **自动工具**: 自动配置 kubectl、k9s、helm 等管理工具
- 📊 **状态监控**: 实时监控集群部署状态和健康检查
- 🛠️ **故障诊断**: 内置集群状态诊断和问题排查工具
- ⚡ **轻量级**: 精简的依赖，快速安装和部署

## 📋 系统要求

- **操作系统**: Linux（推荐 Ubuntu 20.04+ 或 CentOS 8+）
- **硬件要求**: 每个节点至少 2 CPU，4GB 内存，20GB 磁盘空间
- **网络要求**: 节点之间网络互通，支持 SSH 访问
- **权限要求**: 具有 sudo 或 root 权限
- **Ruby 版本**: Ruby 3.0+

## 🚀 快速开始

### 1. 环境准备

```bash
# 克隆项目
git clone <repository_url>
cd rke2

# 运行环境安装脚本
./setup.sh
```

安装脚本会自动完成：
- 安装 Ruby 环境和依赖管理工具
- 安装项目依赖
- 设置正确的文件权限

### 2. 配置集群

编辑 `config.yml` 文件：

```yaml
# 集群认证令牌
token: rke2Secret123456

# 负载均衡器IP（用于高可用集群）
loadbalancer_ip: 10.0.1.100

# 节点配置
nodes:
  # 主节点（控制平面）
  - name: master-01
    ip: 10.0.1.10
    role: server
    ssh_user: root

  # 工作节点
  - name: worker-01
    ip: 10.0.1.20
    role: agent
    ssh_user: root

  # 负载均衡节点（可选）
  - name: lb-01
    ip: 10.0.1.100
    role: lb
    ssh_user: root
```

### 3. 部署集群

```bash
# 开始部署
ruby run.rb

# 或使用 Rake 任务
bundle exec rake rke2:deploy
```

## 🔧 使用方法

### 基本命令

```bash
# 部署完整集群
ruby run.rb

# 诊断集群状态
bundle exec rake rke2:diagnose

# 初始化和优化所有节点
bundle exec rake rke2:init_nodes

# 初始化和优化特定节点
bundle exec rake rke2:init_node[master-01]

# 配置所有主节点的 kubectl
bundle exec rake rke2:configure_kubectl

# 配置特定主节点的 kubectl
bundle exec rake rke2:configure_kubectl_node[master-01]

# 安装 k9s 和 helm 到所有主节点
bundle exec rake rke2:install_k9s_helm

# 安装 k9s 和 helm 到特定主节点
bundle exec rake rke2:install_k9s_helm_node[master-01]

# 配置 Ingress Controller 为 DaemonSet 模式
bundle exec rake rke2:configure_ingress_daemonset

# 修复 Ingress Controller RBAC 权限
bundle exec rake rke2:fix_ingress_rbac

# 代码质量检查
bundle exec rake test:lint

# 生成文档
bundle exec rake doc:yard
```

### 集群管理

#### 自动 kubectl 配置（推荐）

本工具会自动为主节点配置 kubectl，无需手动设置：

```bash
# 配置所有主节点的 kubectl（部署时自动执行）
bundle exec rake rke2:configure_kubectl

# 配置特定主节点
bundle exec rake rke2:configure_kubectl_node[master-01]
```

配置完成后，直接登录主节点即可使用所有工具：

```bash
# SSH 到主节点
ssh root@<master-node-ip>

# 直接使用 kubectl（无需额外配置）
kubectl get nodes
kubectl cluster-info
k get pods --all-namespaces  # k 是 kubectl 的别名

# 使用 k9s 终端 UI 管理集群
k9s

# 使用 helm 包管理器
helm list
helm repo list
```

#### 手动 kubectl 配置（如果需要）

如果您需要手动配置，可以使用完整路径：

```bash
# SSH 到主节点
ssh root@<master-node-ip>

# 使用完整路径
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes
```

### Ingress Controller DaemonSet 模式

本工具自动将 Nginx Ingress Controller 配置为 DaemonSet 模式，提供以下优势：

#### DaemonSet 模式的优势
- **高可用性**: 在每个工作节点上运行 Ingress 实例
- **负载分散**: 流量直接分散到各个节点，无需额外的负载均衡
- **最佳性能**: 使用宿主机网络，减少网络层次，提高性能
- **故障隔离**: 单个节点故障不影响其他节点的 Ingress 服务

#### 自动配置功能
- **宿主机网络**: 直接使用节点的网络，端口 80 和 443 直接暴露
- **节点选择器**: 只在 Linux 节点上部署
- **污点容忍**: 支持在主节点上运行（如果需要）
- **SSL 直通**: 支持 SSL passthrough 功能
- **实时 IP**: 自动检测和报告真实客户端 IP

#### 验证 Ingress 部署

```bash
# SSH 到主节点
ssh root@<master-node-ip>

# 检查 Ingress DaemonSet 状态
kubectl -n ingress-nginx get daemonset
kubectl -n ingress-nginx get pods -o wide

# 检查 Ingress 端口
ss -tlnp | grep -E ':80|:443'

# 测试 Ingress 健康检查
curl -I http://localhost/healthz
```

#### 手动配置 Ingress DaemonSet

如果需要单独配置 Ingress Controller：

```bash
# 配置 Ingress Controller 为 DaemonSet 模式
bundle exec rake rke2:configure_ingress_daemonset

# 如果遇到 RBAC 权限问题，运行修复命令
bundle exec rake rke2:fix_ingress_rbac
```

#### 故障排除 - RBAC 权限问题

如果您看到类似以下的错误：
```
pods "nginx-ingress-controller-xxxx" is forbidden: User "system:serviceaccount:ingress-nginx:nginx-ingress-serviceaccount" cannot get resource "pods"
```

运行 RBAC 权限修复命令：
```bash
bundle exec rake rke2:fix_ingress_rbac
```

该命令会：
- 更新 ClusterRole 和 Role 权限
- 重启 Ingress Controller Pods
- 验证权限修复状态

## 📁 项目结构

```
rke2/
├── lib/
│   └── rke2_deploy.rb         # 核心部署逻辑
├── output/                    # 生成的配置文件和脚本
│   ├── master-01/
│   │   ├── config.yaml       # RKE2 配置文件
│   │   └── install.sh        # 安装脚本
│   └── lb-01/
│       ├── haproxy.cfg       # HAProxy 配置
│       └── install.sh        # 负载均衡器安装脚本
├── config.yml                # 集群配置文件
├── run.rb                    # 主执行文件
├── setup.sh                 # 环境安装脚本
├── Gemfile                   # 依赖管理（已优化）
├── Rakefile                  # 任务定义
├── .rubocop.yml             # 代码风格配置
└── README.md                # 本文档
```

## 🔧 依赖说明

项目经过优化，只包含必要的依赖：

### 核心依赖
- `net-ssh`: SSH 连接管理
- `net-scp`: 文件传输
- `logger`: 日志记录
- `fileutils`: 文件操作
- `rake`: 任务管理

### 开发依赖
- `rspec`: 测试框架
- `rubocop`: 代码质量检查
- `yard`: 文档生成
- `pry`: 调试工具

## 🔍 故障排除

### 常见问题

#### 1. TLS 证书验证失败
```
Error: tls: failed to verify certificate
```

**解决方案**: 这个问题已在最新版本中修复。确保使用最新的配置文件，其中包含正确的 `tls-san` 设置。

#### 2. SSH 连接失败
```
Error: Net::SSH::AuthenticationFailed
```

**解决方案**:
- 检查 SSH 密钥配置
- 确认用户名和权限
- 验证网络连通性

#### 3. 节点未就绪
```
Node status: NotReady
```

**解决方案**:
```bash
# 运行诊断工具
bundle exec rake rke2:diagnose

# 检查特定节点的日志
ssh root@<node-ip>
journalctl -u rke2-server -f
```

### 诊断命令

```bash
# 检查集群状态
bundle exec rake rke2:diagnose

# 检查语法
ruby -c lib/rke2_deploy.rb
ruby -c run.rb

# 运行代码检查
bundle exec rubocop
```

### 日志位置

- **部署日志**: `deploy.log`
- **RKE2 服务器日志**: `/var/log/rke2/rke2.log`（在各节点上）
- **系统日志**: `journalctl -u rke2-server`

## 🏗️ 架构说明

### 部署流程

1. **负载均衡器部署**: 配置 HAProxy 为 API 服务器提供高可用
2. **第一个主节点**: 初始化集群控制平面
3. **其他主节点**: 加入集群形成高可用控制平面
4. **工作节点**: 加入集群提供计算资源

### 网络配置

- **API 服务器**: 端口 6443（通过负载均衡器）
- **RKE2 注册**: 端口 9345
- **CNI**: 使用 Canal（Calico + Flannel）
- **服务网络**: 10.43.0.0/16
- **Pod 网络**: 10.42.0.0/16

## 🧪 测试

```bash
# 运行代码检查
bundle exec rake test:lint

# 语法检查
bundle exec rake -T  # 列出所有可用任务
```

## 🤝 贡献指南

1. **Fork 项目**
2. **创建功能分支**: `git checkout -b feature/amazing-feature`
3. **提交更改**: `git commit -m 'Add amazing feature'`
4. **推送分支**: `git push origin feature/amazing-feature`
5. **创建 Pull Request**

### 代码风格

项目使用 RuboCop 进行代码风格检查：

```bash
# 检查代码风格
bundle exec rubocop

# 自动修复可修复的问题
bundle exec rubocop -A
```

### 节点初始化和性能优化

在部署 RKE2 之前，工具会自动对所有节点进行系统优化：

#### 系统优化项目
1. **时间同步**: 自动安装和配置 chrony/ntp 服务
2. **内存管理**: 禁用 swap，配置内存回收策略
3. **内核优化**: 加载必要模块 (overlay, br_netfilter, ip_vs 等)
4. **网络参数**: 优化 TCP/IP 栈和连接跟踪
5. **系统限制**: 调整文件句柄和进程数限制
6. **防火墙**: 禁用冲突的防火墙服务
7. **磁盘性能**: 优化磁盘调度器设置
8. **DNS 配置**: 配置高性能 DNS 服务器
9. **安全设置**: 应用安全相关的内核参数
10. **系统工具**: 安装必要的管理和监控工具

#### 性能优化参数
- 网络连接跟踪最大值: 1,000,000
- 文件句柄限制: 1,048,576
- TCP 缓冲区优化: 最大 16MB
- 禁用透明大页 (THP)
- 设置合理的内核 panic 参数

### 管理工具自动配置说明

本工具自动为主节点配置以下管理工具：

#### kubectl 配置
1. **kubectl 软链接**: `/usr/local/bin/kubectl` -> `/var/lib/rancher/rke2/bin/kubectl`
2. **Kubeconfig 文件**: 复制到 `/root/.kube/config`
3. **环境变量**: 自动添加到 `/root/.bashrc` 和 `/root/.profile`
   - `KUBECONFIG=/root/.kube/config`
   - `PATH=/var/lib/rancher/rke2/bin:$PATH`
4. **命令别名**: `k=kubectl` (方便快速使用)
5. **权限设置**: 确保文件具有正确的权限 (600)

#### k9s 配置
1. **自动下载**: 最新版本的 k9s 二进制文件
2. **安装位置**: `/usr/local/bin/k9s`
3. **配置文件**: 自动创建 `/root/.config/k9s/config.yml`
4. **优化设置**: 配置合理的刷新频率和 UI 选项

#### helm 配置
1. **官方安装**: 使用 helm 官方安装脚本
2. **安装位置**: `/usr/local/bin/helm`
3. **仓库初始化**: 自动添加 stable 和 bitnami 仓库
4. **版本支持**: 安装最新的 helm v3

配置完成后，root 用户登录即可直接使用：
- `kubectl get nodes` / `k get nodes`
- `k9s` (终端 UI 集群管理)
- `helm list` (包管理器)
- `kubectl cluster-info`

## 📝 版本历史

### v2.3.0 (最新)
- ⚡ **新增**: 自动节点初始化和性能优化功能
- 🔧 系统参数自动优化 (内核、网络、内存等)
- 🛠️ 自动安装系统工具和依赖
- 🏷️ 自动设置主机名和 DNS 优化
- 💾 内存和磁盘性能优化
- 🔥 防火墙和安全配置优化

### v2.2.0
- 🎯 **新增**: k9s 和 helm 自动安装功能
- 🖥️ 自动安装 k9s 终端 UI 管理工具
- 📦 自动安装 helm 包管理器并初始化仓库
- 🔧 优化 k9s 配置文件和用户体验

### v2.1.0
- 🎯 **新增**: 自动 kubectl 配置功能
- 🔗 自动创建 kubectl 软链接和环境变量
- 📝 为 root 用户配置 kubeconfig 文件
- ⚡ 简化集群管理操作

### v2.0.0
- ✨ 重构核心部署逻辑
- 🔧 修复 TLS 证书验证问题
- ⚡ 优化依赖管理，移除 90% 未使用的 gem
- 📊 改进集群状态检查和诊断
- 🛠️ 简化 Rakefile 和项目结构

### v1.x
- 初始版本，包含基础部署功能

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🔗 相关链接

- [RKE2 官方文档](https://docs.rke2.io/)
- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [HAProxy 文档](https://www.haproxy.org/download/2.4/doc/configuration.txt)

## 🎉 最新更新

### v2.0 - Ingress DaemonSet 模式

**新增功能:**
- ✅ **自动 Ingress DaemonSet 部署**: 默认在集群部署时自动配置
- ✅ **优化时间同步服务**: 修复 chronyd.service 别名问题，支持多种时间同步服务
- ✅ **移除内置 RKE2 Ingress**: 不再禁用 RKE2 内置 Ingress，改为部署优化的 DaemonSet 版本
- ✅ **宿主机网络模式**: 使用 hostNetwork 获得最佳网络性能
- ✅ **完整 RBAC 权限**: 配置完整的 ClusterRole 和权限管理

**性能优化:**
- 🚀 在每个工作节点运行 Ingress Controller
- 🚀 使用宿主机网络减少网络跳转
- 🚀 支持 SSL passthrough 和真实 IP 检测
- 🚀 自动负载分散，无需额外负载均衡器

**使用方法:**
```bash
# 完整集群部署（包含 Ingress DaemonSet）
bundle exec rake rke2:deploy

# 单独配置 Ingress DaemonSet
bundle exec rake rke2:configure_ingress_daemonset
```

**验证部署:**
```bash
# 检查 DaemonSet 状态
kubectl -n ingress-nginx get daemonset,pods -o wide

# 检查网络端口
ss -tlnp | grep -E ':80|:443'
```

---

**如有问题或建议，欢迎提交 Issue 或 Pull Request！** 🚀