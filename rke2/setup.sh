#!/bin/bash

# 设置错误时退出
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 未安装"
        return 1
    fi
    return 0
}

# 安装 asdf
install_asdf() {
    if ! check_command "asdf"; then
        log_info "正在安装 asdf..."

        case "$(uname)" in
            "Darwin")
                if ! check_command "brew"; then
                    log_error "请先安装 Homebrew: https://brew.sh/"
                    exit 1
                fi
                brew install asdf
                echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
                source ~/.zshrc
                ;;

            "Linux")
                git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1

                # 根据不同的 shell 添加配置
                if [ -f "$HOME/.bashrc" ]; then
                    echo -e "\n. \$HOME/.asdf/asdf.sh" >> ~/.bashrc
                    source ~/.bashrc
                elif [ -f "$HOME/.zshrc" ]; then
                    echo -e "\n. \$HOME/.asdf/asdf.sh" >> ~/.zshrc
                    source ~/.zshrc
                else
                    log_error "未找到支持的 shell 配置文件"
                    exit 1
                fi
                ;;

            *)
                log_error "不支持的操作系统"
                exit 1
                ;;
        esac
    fi
}

# 安装 Ruby
install_ruby() {
    local ruby_version="3.2.2"

    log_info "正在安装 Ruby ${ruby_version}..."

    # 添加 Ruby 插件
    if ! asdf plugin list | grep -q "ruby"; then
        asdf plugin add ruby
    fi

    # 安装必要的系统依赖
    case "$(uname)" in
        "Darwin")
            # macOS 依赖
            brew install openssl readline
            ;;

        "Linux")
            if command -v apt-get &> /dev/null; then
                # Debian/Ubuntu 依赖
                sudo apt-get update
                sudo apt-get install -y autoconf patch build-essential rustc libssl-dev libyaml-dev \
                    libreadline6-dev zlib1g-dev libgmp-dev libncurses5-dev libffi-dev libgdbm6 \
                    libgdbm-dev libdb-dev uuid-dev
            elif command -v yum &> /dev/null; then
                # RHEL/CentOS 依赖
                sudo yum groupinstall -y "Development Tools"
                sudo yum install -y openssl-devel readline-devel zlib-devel
            fi
            ;;
    esac

    # 安装指定版本的 Ruby
    asdf install ruby $ruby_version

    # 设置全局 Ruby 版本
    asdf global ruby $ruby_version

    # 验证安装
    if ! check_command "ruby"; then
        log_error "Ruby 安装失败"
        exit 1
    fi

    log_info "Ruby ${ruby_version} 安装完成"
}

# 安装或更新 bundler
install_bundler() {
    if ! check_command "bundle"; then
        log_info "正在安装 bundler..."
        gem install bundler
    else
        log_info "正在更新 bundler..."
        gem update bundler
    fi
}

# 安装系统依赖（如果需要）
install_system_dependencies() {
    case "$(uname)" in
        "Darwin")
            # macOS
            if ! check_command "brew"; then
                log_error "请先安装 Homebrew: https://brew.sh/"
                exit 1
            fi

            # 检查并安装必要的系统依赖
            local brew_packages=("openssl" "readline")
            for package in "${brew_packages[@]}"; do
                if ! brew list "$package" &>/dev/null; then
                    log_info "正在安装 $package..."
                    brew install "$package"
                fi
            done
            ;;

        "Linux")
            # 检查包管理器并安装依赖
            if command -v apt-get &> /dev/null; then
                log_info "正在安装系统依赖..."
                sudo apt-get update
                sudo apt-get install -y build-essential libssl-dev libreadline-dev zlib1g-dev
            elif command -v yum &> /dev/null; then
                log_info "正在安装系统依赖..."
                sudo yum groupinstall -y "Development Tools"
                sudo yum install -y openssl-devel readline-devel zlib-devel
            else
                log_warn "未能识别的包管理器，请手动安装必要的系统依赖"
            fi
            ;;

        *)
            log_warn "未知的操作系统，请手动安装必要的系统依赖"
            ;;
    esac
}

# 主函数
main() {
    log_info "开始设置 RKE2 管理工具环境..."

    # 安装 asdf
    install_asdf

    # 安装 Ruby
    install_ruby

    # 安装系统依赖
    install_system_dependencies

    # 安装/更新 bundler
    install_bundler

    # 安装 gem 依赖
    log_info "正在安装 gem 依赖..."
    bundle config set --local path 'vendor/bundle'
    bundle install

    # 设置可执行权限
    log_info "设置文件权限..."
    chmod +x run.rb

    log_info "环境设置完成！"
    log_info "你可以通过以下命令查看使用帮助："
    log_info "  ./run.rb --help"
}

# 执行主函数
main "$@"