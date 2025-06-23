# Kubernetes Development Environment

这是一个用于快速搭建 Kubernetes 开发和测试环境的工具集。

## 功能特点

- 使用 Kind 快速创建多节点 Kubernetes 集群
- 自动安装和配置必要的工具链
- 支持 RKE2 生产级集群部署
- 完整的集群生命周期管理

## 环境要求

- Linux 或 macOS 操作系统
- Docker 已安装并运行
- Git
- Ruby >= 3.2.2（用于 RKE2 部署）

## 工具链

所有工具都会自动安装到最新稳定版：

- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/) - 用于本地 Kubernetes 开发
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes 命令行工具
- [kubectx](https://github.com/ahmetb/kubectx) - 快速切换集群上下文
- [Helm](https://helm.sh/) - Kubernetes 包管理器
- [Lens](https://github.com/lensapp/lens) - Kubernetes IDE（需要手动安装）

## 快速开始

### 本地开发环境

1. 克隆仓库：
```bash
git clone https://github.com/kevin197011/k8s.git
cd k8s
```

2. 安装依赖并启动集群：
```bash
rake install  # 安装必要工具
rake run      # 创建并启动集群
```

3. 验证集群状态：
```bash
kubectl cluster-info
kubectl get nodes
```

### 生产环境部署 (RKE2)

如果需要部署生产级 RKE2 集群，请参考 [RKE2 部署文档](./rke2/README.md)。

## 集群配置

### Kind 多节点集群

默认配置创建一个包含 1 个控制平面节点和 3 个工作节点的集群：

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
```

## 常用命令

```bash
# 创建集群
rake run

# 查看节点状态
kubectl get nodes

# 删除集群
kind delete cluster --name k8s

# 切换集群上下文
kubectx

# 推送更改到仓库
rake push
```

## 版本信息

当前支持的组件版本：

- Kubernetes: v1.29.2
- Kind: 最新稳定版
- Helm: v3.14.2
- kubectl: v1.29.2
- kubectx: v0.9.5

## 故障排除

1. 如果集群创建失败：
   - 确保 Docker 正在运行
   - 检查系统资源是否充足
   - 查看 Kind 日志

2. 如果工具安装失败：
   - 检查网络连接
   - 确保有足够的磁盘空间
   - 验证系统权限

## 贡献

欢迎提交 Pull Request 和 Issue。在提交之前，请：

1. 确保代码符合项目规范
2. 更新相关文档
3. 添加必要的测试

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件
