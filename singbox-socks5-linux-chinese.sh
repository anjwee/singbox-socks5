#!/bin/bash

# sing-box socks5 configuration script (Linux version - compatible with 1.12.0+)
# Suitable for general Linux systems

RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

yellow() {
  echo -e "${YELLOW}$1${RESET}"
}
green() {
  echo -e "${GREEN}$1${RESET}"
}
red() {
  echo -e "${RED}$1${RESET}"
}

# Working directory
INSTALL_PATH="$HOME/singbox"
CONFIG_FILE="$INSTALL_PATH/config.json"
SINGBOX_BIN="$INSTALL_PATH/sing-box"

# Create working directory
create_workdir() {
  if [[ ! -d "$INSTALL_PATH" ]]; then
    mkdir -p "$INSTALL_PATH"
    green "已创建工作目录: $INSTALL_PATH"
  fi
}

# Detect system architecture
detect_arch() {
  local arch=$(uname -m)
  case $arch in
    x86_64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l)
      echo "armv7"
      ;;
    *)
      red "Unsupported architecture: $arch"
      return 1
      ;;
  esac
}

# Download sing-box
download_singbox() {
  cd "$INSTALL_PATH"

  if [[ -f "$SINGBOX_BIN" ]]; then
    yellow "检测到已有sing-box，是否重新下载? [y/n] [n]:"
    read -p "" input
    input=${input:-n}
    if [[ "$input" != "y" ]]; then
      return 0
    fi
  fi

  local arch=$(detect_arch)
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  yellow "正在获取最新版本..."
  local latest_version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

  if [[ -z "$latest_version" ]]; then
    red "获取版本失败"
    return 1
  fi

  local download_url="https://github.com/SagerNet/sing-box/releases/download/v${latest_version}/sing-box-${latest_version}-linux-${arch}.tar.gz"

  green "下载地址: $download_url"
  yellow "正在下载sing-box..."

  if ! wget -O sing-box.tar.gz "$download_url"; then
    red "下载失败"
    return 1
  fi

  yellow "正在解压..."
  tar -xzf sing-box.tar.gz

  # Find extracted executable
  local extracted_dir=$(tar -tzf sing-box.tar.gz | head -1 | cut -f1 -d"/")
  if [[ -f "$extracted_dir/sing-box" ]]; then
    mv "$extracted_dir/sing-box" ./sing-box
    chmod +x ./sing-box
    rm -rf "$extracted_dir" sing-box.tar.gz
    green "sing-box 下载完成"
  else
    red "解压失败"
    return 1
  fi
}

# Generate socks5 config (compatible with sing-box 1.12.0+)
make_socks5_config() {
  local port=$1
  local username=$2
  local password=$3

  cat <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "8.8.8.8"
      },
      {
        "tag": "local",
        "address": "local",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "local"
      }
    ],
    "final": "google"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "username": "$username",
          "password": "$password"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true
  }
}
EOF
}

# Configure socks5
config_socks5() {
  cd "$INSTALL_PATH"

  if [[ -f "$CONFIG_FILE" ]]; then
    yellow "检测到已有配置文件:"
    cat "$CONFIG_FILE"
    echo ""
    read -p "$(echo -e "${RED}继续将覆盖现有配置，是否继续? [y/n] [n]${RESET} ")" input
    input=${input:-n}
    if [[ "$input" != "y" ]]; then
      return 1
    fi
  fi

  # Read port
  read -p "请输入SOCKS5监听端口 [默认 1080]: " port
  port=${port:-1080}

  # Validate port number
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    red "端口号无效"
    return 1
  fi

  # Read username and password
  read -p "请输入SOCKS5用户名: " username
  if [[ -z "$username" ]]; then
    red "用户名不能为空"
    return 1
  fi

  read -p "请输入SOCKS5密码: " password
  if [[ -z "$password" ]]; then
    red "密码不能为空"
    return 1
  fi

  # Generate config file
  make_socks5_config "$port" "$username" "$password" > "$CONFIG_FILE"

  green "配置文件已生成: $CONFIG_FILE"

  # Display config info
  echo ""
  yellow "========================="
  green "SOCKS5 配置信息:"
  echo "监听地址: 0.0.0.0:$port"
  echo "用户名: $username"
  echo "密码: $password"
  yellow "========================="
}

# Start sing-box
start_singbox() {
  cd "$INSTALL_PATH"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    red "配置文件未找到，请先进行配置"
    return 1
  fi

  if [[ ! -f "$SINGBOX_BIN" ]]; then
    red "sing-box 未安装，请先安装"
    return 1
  fi

  # Check if already running
  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    yellow "sing-box 已在运行，是否重启? [y/n] [n]:"
    read -p "" input
    input=${input:-n}
    if [[ "$input" == "y" ]]; then
      stop_singbox
      sleep 2
    else
      return 0
    fi
  fi

  yellow "正在启动sing-box..."
  export ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true
  nohup "$SINGBOX_BIN" run -c "$CONFIG_FILE" > "$INSTALL_PATH/singbox.log" 2>&1 &

  sleep 2

  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    green "sing-box 启动成功"
    echo "日志文件: $INSTALL_PATH/singbox.log"
    echo ""
    yellow "查看日志: tail -f $INSTALL_PATH/singbox.log"
  else
    red "启动失败，请检查日志"
    tail -20 "$INSTALL_PATH/singbox.log"
  fi
}

# Stop sing-box
stop_singbox() {
  yellow "正在停止sing-box..."
  pkill -f "$SINGBOX_BIN"
  sleep 1

  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    red "停止失败，尝试强制终止..."
    pkill -9 -f "$SINGBOX_BIN"
  fi

  if ! pgrep -f "$SINGBOX_BIN" > /dev/null; then
    green "sing-box 已停止"
  else
    red "停止失败"
  fi
}

# Show status
show_status() {
  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    green "sing-box 正在运行"
    echo ""
    if [[ -f "$CONFIG_FILE" ]]; then
      local port=$(grep -oP '"listen_port":\s*\K\d+' "$CONFIG_FILE" | head -1)
      local username=$(grep -oP '"username":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
      yellow "配置信息:"
      echo "端口: $port"
      echo "用户名: $username"
      echo ""
      yellow "进程信息:"
      ps aux | grep "$SINGBOX_BIN" | grep -v grep
    fi
  else
    red "sing-box 未运行"
  fi
}

# Show logs
show_logs() {
  if [[ -f "$INSTALL_PATH/singbox.log" ]]; then
    tail -50 "$INSTALL_PATH/singbox.log"
  else
    red "日志文件未找到"
  fi
}

# Test connection
test_connection() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    red "配置文件未找到"
    return 1
  fi

  local port=$(grep -oP '"listen_port":\s*\K\d+' "$CONFIG_FILE" | head -1)
  local username=$(grep -oP '"username":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
  local password=$(grep -oP '"password":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)

  yellow "正在测试SOCKS5连接..."
  echo ""
  echo "你可以使用以下方法测试:"
  echo ""
  echo "1. 使用curl测试:"
  echo "   curl -x socks5://$username:$password@127.0.0.1:$port https://ifconfig.me"
  echo ""
  echo "2. 在浏览器中设置代理:"
  echo "   类型: SOCKS5"
  echo "   地址: 127.0.0.1"
  echo "   端口: $port"
  echo "   用户名: $username"
  echo "   密码: $password"
  echo ""

  if command -v curl &> /dev/null; then
    read -p "现在使用curl测试? [y/n] [y]: " test_now
    test_now=${test_now:-y}
    if [[ "$test_now" == "y" ]]; then
      echo ""
      yellow "正在测试..."
      if curl -s -x "socks5://$username:$password@127.0.0.1:$port" --max-time 10 https://ifconfig.me; then
        echo ""
        green "SOCKS5代理工作正常!"
      else
        echo ""
        red "连接失败，请检查配置和防火墙"
      fi
    fi
  fi
}

# Uninstall
uninstall() {
  read -p "确定要卸载sing-box吗？这将删除所有配置 [y/n] [n]: " input
  input=${input:-n}

  if [[ "$input" == "y" ]]; then
    stop_singbox

    # Remove systemd service if exists
    if [[ -f /etc/systemd/system/sing-box.service ]]; then
      sudo systemctl stop sing-box 2>/dev/null
      sudo systemctl disable sing-box 2>/dev/null
      sudo rm -f /etc/systemd/system/sing-box.service
      sudo systemctl daemon-reload
      yellow "已移除systemd服务"
    fi

    rm -rf "$INSTALL_PATH"
    green "卸载完成"
  else
    yellow "取消卸载"
  fi
}

# Create systemd service (optional)
create_systemd_service() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    red "请先配置sing-box"
    return 1
  fi

  yellow "正在创建systemd服务..."

  sudo tee /etc/systemd/system/sing-box.service > /dev/null <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
User=$USER
ExecStart=$SINGBOX_BIN run -c $CONFIG_FILE
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  green "systemd服务已创建"
  echo ""
  yellow "使用以下命令管理服务:"
  echo "启动: sudo systemctl start sing-box"
  echo "停止: sudo systemctl stop sing-box"
  echo "开机自启: sudo systemctl enable sing-box"
  echo "查看状态: sudo systemctl status sing-box"
  echo "查看日志: sudo journalctl -u sing-box -f"
}

# Check dependencies
check_dependencies() {
  local missing_deps=()

  for cmd in wget tar curl; do
    if ! command -v $cmd &> /dev/null; then
      missing_deps+=($cmd)
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    red "缺少依赖: ${missing_deps[*]}"
    echo "请安装: sudo apt install ${missing_deps[*]} (Debian/Ubuntu)"
    echo "或者: sudo yum install ${missing_deps[*]} (CentOS/RHEL)"
    return 1
  fi

  return 0
}

# Main menu
show_menu() {
  clear
  echo -e "${BLUE}================================${RESET}"
  echo -e "${GREEN} sing-box SOCKS5 管理脚本${RESET}"
  echo -e "${GREEN} Linux系统版本${RESET}"
  echo -e "${GREEN} 兼容 sing-box 1.12.0+${RESET}"
  echo -e "${BLUE}================================${RESET}"
  echo ""
  echo "1. 安装sing-box"
  echo "2. 配置SOCKS5"
  echo "3. 启动sing-box"
  echo "4. 停止sing-box"
  echo "5. 显示状态"
  echo "6. 显示日志"
  echo "7. 测试连接"
  echo "8. 创建systemd服务（推荐）"
  echo "9. 卸载"
  echo "0. 退出"
  echo ""
  echo -e "${BLUE}================================${RESET}"
}

# Main program
main() {
  # Check dependencies
  if ! check_dependencies; then
    exit 1
  fi

  # Create working directory
  create_workdir

  while true; do
    show_menu
    read -p "请选择 [0-9]: " choice

    case $choice in
      1)
        download_singbox
        read -p "按回车键继续..."
        ;;
      2)
        config_socks5
        read -p "按回车键继续..."
        ;;
      3)
        start_singbox
        read -p "按回车键继续..."
        ;;
      4)
        stop_singbox
        read -p "按回车键继续..."
        ;;
      5)
        show_status
        read -p "按回车键继续..."
        ;;
      6)
        show_logs
        read -p "按回车键继续..."
        ;;
      7)
        test_connection
        read -p "按回车键继续..."
        ;;
      8)
        create_systemd_service
        read -p "按回车键继续..."
        ;;
      9)
        uninstall
        exit 0
        ;;
      0)
        green "退出脚本"
        exit 0
        ;;
      *)
        red "无效选择"
        sleep 2
        ;;
    esac
  done
}

# Run main program
main
