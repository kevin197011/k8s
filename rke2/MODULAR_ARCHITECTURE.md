# RKE2 部署工具 - 模块化架构设计

## 概述

RKE2 部署工具已重构为模块化架构，将原本单一的大类拆分为多个专门的模块，提高了代码的可维护性、可测试性和可复用性。

## 架构设计

### 🏗️ 核心模块

```
RKE2/
├── Base                    # 基础类，提供共同功能
├── Deployer               # 主部署编排器
├── NodeInitializer        # 节点初始化和系统优化
├── LoadBalancer          # 负载均衡器管理
├── ConfigGenerator       # 配置文件生成
├── NodeDeployer          # 节点部署执行
├── ClusterManager        # 集群管理和监控
├── ToolsInstaller        # kubectl, k9s, helm 工具安装
├── IngressController     # Ingress 控制器管理
└── Diagnostics           # 集群诊断和监控
```

### 📋 职责分工

| 模块 | 职责 | 主要方法 |
|------|------|----------|
| **Base** | 基础功能、配置管理、日志记录 | `initialize`, `log`, `token`, `lb_ip` |
| **Deployer** | 部署流程编排、模块协调 | `run`, `deploy_first_server`, `deploy_additional_servers` |
| **NodeInitializer** | 系统优化、内核参数、网络配置 | `initialize_all_nodes`, `initialize_node` |
| **LoadBalancer** | HAProxy 配置、负载均衡部署 | `deploy_lb_nodes`, `write_nginx_config` |
| **ConfigGenerator** | RKE2 配置文件生成 | `write_config_file`, `generate_*_config` |
| **NodeDeployer** | 安装脚本生成、节点部署执行 | `deploy_to_node`, `write_install_script` |
| **ClusterManager** | 集群状态监控、就绪性检查 | `wait_for_server_ready`, `check_cluster_readiness` |
| **ToolsInstaller** | kubectl/k9s/helm 安装配置 | `configure_kubectl_on_servers`, `install_k9s_helm_on_servers` |
| **IngressController** | Ingress DaemonSet、RBAC 管理 | `configure_ingress_daemonset`, `fix_ingress_rbac` |
| **Diagnostics** | 集群诊断、状态检查、故障排除 | `diagnose_cluster_status`, `quick_diagnosis` |

## 使用方法

### 🚀 基本使用

```ruby
require_relative 'lib/rke2_deploy'

# 1. 完整集群部署
deployer = RKE2.new('config.yml')
deployer.run

# 2. 使用工厂方法创建特定模块
diagnostics = RKE2.diagnostics('config.yml')
tools_installer = RKE2.tools_installer('config.yml')
ingress_controller = RKE2.ingress_controller('config.yml')
```

### 🔍 诊断功能

```ruby
# 快速诊断
RKE2.quick_diagnosis('config.yml')

# 全面诊断
RKE2.comprehensive_diagnosis('config.yml')

# 标准诊断
diagnostics = RKE2.diagnostics('config.yml')
diagnostics.diagnose_cluster_status
```

### 🛠️ 工具管理

```ruby
tools_installer = RKE2.tools_installer('config.yml')

# 配置 kubectl
tools_installer.configure_kubectl_on_servers

# 安装 k9s 和 helm
tools_installer.install_k9s_helm_on_servers

# 为特定节点配置工具
node = { 'name' => 'master-1', 'ip' => '10.0.0.1', 'role' => 'server' }
tools_installer.configure_kubectl_on_node(node)
```

### 🌐 Ingress 管理

```ruby
ingress_controller = RKE2.ingress_controller('config.yml')

# 配置 Ingress Controller 为 DaemonSet
ingress_controller.configure_ingress_daemonset

# 修复 RBAC 权限问题
ingress_controller.fix_ingress_rbac
```

### 🎛️ 集群管理

```ruby
cluster_manager = RKE2.cluster_manager('config.yml')

# 等待服务器就绪
server_node = { 'name' => 'master-1', 'ip' => '10.0.0.1', 'ssh_user' => 'root' }
cluster_manager.wait_for_server_ready(server_node)

# 监控启动进度
cluster_manager.monitor_startup_progress(server_node, 15)
```

## 命令行工具

### 主部署工具

```bash
# 使用新的模块化架构部署
ruby run.rb config.yml
```

### 诊断工具

```bash
# 快速诊断
ruby diagnose.rb quick

# 标准诊断
ruby diagnose.rb standard

# 全面诊断
ruby diagnose.rb comprehensive

# 使用指定配置文件
ruby diagnose.rb comprehensive my-config.yml
```

### Rake 任务

```bash
# 查看所有可用任务
rake rke2:help

# 部署集群 (模块化架构)
rake rke2:deploy

# 各种诊断模式
rake rke2:diagnose
rake rke2:quick_diagnose
rake rke2:comprehensive_diagnose

# 工具配置
rake rke2:configure_kubectl
rake rke2:install_k9s_helm

# Ingress 管理
rake rke2:configure_ingress_daemonset
rake rke2:fix_ingress_rbac
```

## 扩展和定制

### 📦 添加新模块

1. 创建新模块文件 `lib/rke2/my_module.rb`
2. 继承 `RKE2::Base` 类
3. 在 `lib/rke2.rb` 中添加 require 和工厂方法

```ruby
# lib/rke2/my_module.rb
module RKE2
  class MyModule < Base
    def my_function
      log('执行自定义功能...')
      # 实现逻辑
    end
  end
end

# lib/rke2.rb
require_relative 'rke2/my_module'

module RKE2
  def self.my_module(config_file)
    MyModule.new(config_file)
  end
end
```

### 🔧 模块间协作

```ruby
class MyDeployer < RKE2::Base
  def initialize(config_file)
    super
    @diagnostics = RKE2::Diagnostics.new(config_file)
    @tools_installer = RKE2::ToolsInstaller.new(config_file)
  end

  def custom_deployment
    # 先诊断
    @diagnostics.quick_diagnosis

    # 然后配置工具
    @tools_installer.configure_kubectl_on_servers

    # 自定义逻辑
    log('执行自定义部署逻辑...')
  end
end
```

## 优势

### ✅ 模块化优势

1. **单一职责**: 每个模块专注于特定功能
2. **低耦合**: 模块间依赖最小化
3. **高内聚**: 相关功能集中在同一模块
4. **可测试**: 每个模块可独立测试
5. **可复用**: 模块可在不同场景下复用
6. **易维护**: 修改某个功能只需要关注特定模块

### 🔄 与原有架构的兼容性

```ruby
# 原有用法仍然支持
deployer = RKE2Deployer.new('config.yml')
deployer.run

# 新的模块化用法
deployer = RKE2.new('config.yml')
deployer.run
```

## 最佳实践

### 🎯 使用建议

1. **选择合适的模块**: 根据需求选择特定模块而非完整部署器
2. **工厂方法优先**: 使用 `RKE2.diagnostics()` 而非直接实例化
3. **错误处理**: 在模块调用外包装异常处理
4. **日志记录**: 利用基类的 `log()` 方法统一日志格式
5. **配置复用**: 多个模块可共享同一配置文件

### 📋 示例工作流

```ruby
# 完整的运维工作流
config_file = 'config.yml'

begin
  # 1. 快速诊断集群状态
  puts "1. 快速诊断..."
  RKE2.quick_diagnosis(config_file)

  # 2. 如果需要，修复 Ingress 问题
  puts "2. 修复 Ingress RBAC..."
  ingress = RKE2.ingress_controller(config_file)
  ingress.fix_ingress_rbac

  # 3. 确保工具正确配置
  puts "3. 配置管理工具..."
  tools = RKE2.tools_installer(config_file)
  tools.configure_kubectl_on_servers

  # 4. 最终验证
  puts "4. 最终验证..."
  diagnostics = RKE2.diagnostics(config_file)
  diagnostics.diagnose_cluster_status

  puts "✅ 运维任务完成!"

rescue StandardError => e
  puts "❌ 运维过程出错: #{e.message}"
end
```

## 版本信息

- **当前版本**: v2.1.0
- **架构**: 模块化设计
- **兼容性**: 向后兼容原有接口
- **Ruby 版本**: >= 2.7.0

---

*此文档展示了 RKE2 部署工具的新模块化架构设计，为开发者和运维人员提供了更灵活和强大的集群管理能力。*