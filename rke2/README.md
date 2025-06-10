# RKE2 集群管理工具

这是一个用 Ruby 实现的 RKE2 Kubernetes 集群管理工具集，提供了完整的集群生命周期管理功能。

## 功能特点

- 自动化部署 RKE2 集群
- 多主节点高可用架构
- 自动化节点扩缩容
- 系统性能优化
- 版本管理和兼容性检查
- Rancher UI 集成
- 中国区镜像加速

## 系统要求

- Linux 操作系统（推荐 Ubuntu 20.04 或 CentOS 8）
- macOS 系统（需要安装 Homebrew）
- 每个节点至少 2 CPU，4GB 内存，20GB 磁盘空间
- 节点之间网络互通
- root 或 sudo 权限

## 快速开始

1. 克隆仓库：

```bash
git clone https://github.com/kevin197011/rke2-manager.git
cd rke2-manager
```

2. 运行安装脚本：

```bash
./setup.sh
```

安装脚本会自动完成以下任务：
- 安装 asdf 版本管理器
- 安装 Ruby 3.2.2
- 安装必要的系统依赖
- 安装 bundler 和项目依赖
- 设置正确的文件权限

3. 配置集群：

编辑 `config.yaml` 文件，设置节点信息和其他配置项。

## 使用方法

### 查看帮助

```bash
./run.rb --help
```

### 部署集群

```bash
./run.rb deploy
```

这将：
- 检查组件版本和兼容性
- 部署主节点
- 部署工作节点
- 安装 Rancher UI
- 配置本地 kubectl

### 优化集群

```bash
./run.rb optimize
```

这将对集群进行全面的性能优化，包括：
- 系统参数优化
- Kubernetes 组件优化
- 网络性能优化
- 资源配额优化

### 节点管理

添加工作节点：
```bash
./run.rb add-worker -h worker3.example.com -u root -n worker3
```

移除工作节点：
```bash
./run.rb remove-worker -n worker3
```

### 版本管理

检查组件版本：
```bash
./run.rb check-versions
```

检查版本兼容性：
```bash
./run.rb check-compatibility
```

## 配置说明

### 节点配置

在 `config.yaml` 中配置节点信息：

```yaml
master_nodes:
  - host: master1.example.com
    user: root
    name: master1
  - host: master2.example.com
    user: root
    name: master2

worker_nodes:
  - host: worker1.example.com
    user: root
    name: worker1
```

### 网络配置

```yaml
network:
  pod_cidr: 10.42.0.0/16
  service_cidr: 10.43.0.0/16
  cni: calico
  mtu: 1440
```

### 系统优化配置

```yaml
system:
  sysctl:
    net.ipv4.ip_forward: 1
    vm.swappiness: 10
  limits:
    nofile: 1048576
    nproc: 65535
```

### 镜像加速配置

```yaml
registry_mirrors:
  docker.io:
    - https://mirror.ccs.tencentyun.com
    - https://registry.docker-cn.com
```

## 项目结构

```
rke2/
├── lib/                    # 核心库文件
│   ├── cluster_manager.rb  # 集群管理主类
│   ├── node_manager.rb     # 节点管理
│   ├── system_optimizer.rb # 系统优化
│   └── version_manager.rb  # 版本管理
├── config.yaml            # 配置文件
├── run.rb                # 主执行文件
├── setup.sh              # 环境安装脚本
├── Gemfile               # 依赖管理
└── README.md             # 文档
```

## 故障排除

### 常见问题

1. 环境安装失败
   - 检查系统要求
   - 确认网络连接
   - 查看安装日志

2. 节点连接失败
   - 检查 SSH 密钥配置
   - 确认节点网络连通性
   - 验证用户权限

3. 组件版本不兼容
   - 运行 `./run.rb check-compatibility`
   - 根据提示调整版本

4. 性能问题
   - 运行 `./run.rb optimize`
   - 检查系统资源使用情况
   - 查看组件日志

### 日志位置

- RKE2 服务器：`/var/log/rke2/server.log`
- RKE2 代理：`/var/log/rke2/agent.log`
- 系统日志：`/var/log/syslog` 或 `/var/log/messages`

## 贡献

欢迎提交 Pull Request 和 Issue。在提交之前，请：

1. 确保通过所有测试
2. 更新相关文档
3. 遵循代码风格指南
4. 添加必要的测试用例

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。