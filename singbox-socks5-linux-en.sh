#!/bin/bash

# sing-box socks5 configuration script Linux version compatible with 1.12.0+
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
    green "Created working directory: $INSTALL_PATH"
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
    yellow "Existing sing-box detected, re-download? [y/n] [n]:"
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

  yellow "Getting latest version..."
  local latest_version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

  if [[ -z "$latest_version" ]]; then
    red "Failed to get version"
    return 1
  fi

  local download_url="https://github.com/SagerNet/sing-box/releases/download/v${latest_version}/sing-box-${latest_version}-linux-${arch}.tar.gz"

  green "Download URL: $download_url"
  yellow "Downloading sing-box..."

  if ! wget -O sing-box.tar.gz "$download_url"; then
    red "Download failed"
    return 1
  fi

  yellow "Extracting..."
  tar -xzf sing-box.tar.gz

  # Find extracted executable
  local extracted_dir=$(tar -tzf sing-box.tar.gz | head -1 | cut -f1 -d"/")
  if [[ -f "$extracted_dir/sing-box" ]]; then
    mv "$extracted_dir/sing-box" ./sing-box
    chmod +x ./sing-box
    rm -rf "$extracted_dir" sing-box.tar.gz
    green "sing-box download completed"
  else
    red "Extraction failed"
    return 1
  fi
}

# Generate socks5 config compatible with sing-box 1.12.0+
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
    yellow "Existing config file detected:"
    cat "$CONFIG_FILE"
    echo ""
    read -p "$(echo -e "${RED}Continue will overwrite existing config, continue? [y/n] [n]${RESET} ")" input
    input=${input:-n}
    if [[ "$input" != "y" ]]; then
      return 1
    fi
  fi

  # Read port
  read -p "Enter SOCKS5 listen port [default 1080]: " port
  port=${port:-1080}

  # Validate port number
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    red "Invalid port number"
    return 1
  fi

  # Read username and password
  read -p "Enter SOCKS5 username: " username
  if [[ -z "$username" ]]; then
    red "Username cannot be empty"
    return 1
  fi

  read -p "Enter SOCKS5 password: " password
  if [[ -z "$password" ]]; then
    red "Password cannot be empty"
    return 1
  fi

  # Generate config file
  make_socks5_config "$port" "$username" "$password" > "$CONFIG_FILE"

  green "Config file generated: $CONFIG_FILE"

  # Display config info
  echo ""
  yellow "========================="
  green "SOCKS5 Configuration:"
  echo "Listen address: 0.0.0.0:$port"
  echo "Username: $username"
  echo "Password: $password"
  yellow "========================="
}

# Start sing-box
start_singbox() {
  cd "$INSTALL_PATH"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    red "Config file not found, please configure first"
    return 1
  fi

  if [[ ! -f "$SINGBOX_BIN" ]]; then
    red "sing-box not installed, please install first"
    return 1
  fi

  # Check if already running
  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    yellow "sing-box is already running, restart? [y/n] [n]:"
    read -p "" input
    input=${input:-n}
    if [[ "$input" == "y" ]]; then
      stop_singbox
      sleep 2
    else
      return 0
    fi
  fi

  yellow "Starting sing-box..."
  export ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true
  nohup "$SINGBOX_BIN" run -c "$CONFIG_FILE" > "$INSTALL_PATH/singbox.log" 2>&1 &

  sleep 2

  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    green "sing-box started successfully"
    echo "Log file: $INSTALL_PATH/singbox.log"
    echo ""
    yellow "View logs: tail -f $INSTALL_PATH/singbox.log"
  else
    red "Start failed, please check logs"
    tail -20 "$INSTALL_PATH/singbox.log"
  fi
}

# Stop sing-box
stop_singbox() {
  yellow "Stopping sing-box..."
  pkill -f "$SINGBOX_BIN"
  sleep 1

  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    red "Stop failed, trying force kill..."
    pkill -9 -f "$SINGBOX_BIN"
  fi

  if ! pgrep -f "$SINGBOX_BIN" > /dev/null; then
    green "sing-box stopped"
  else
    red "Stop failed"
  fi
}

# Show status
show_status() {
  if pgrep -f "$SINGBOX_BIN" > /dev/null; then
    green "sing-box is running"
    echo ""
    if [[ -f "$CONFIG_FILE" ]]; then
      local port=$(grep -oP '"listen_port":\s*\K\d+' "$CONFIG_FILE" | head -1)
      local username=$(grep -oP '"username":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
      yellow "Configuration info:"
      echo "Port: $port"
      echo "Username: $username"
      echo ""
      yellow "Process info:"
      ps aux | grep "$SINGBOX_BIN" | grep -v grep
    fi
  else
    red "sing-box is not running"
  fi
}

# Show logs
show_logs() {
  if [[ -f "$INSTALL_PATH/singbox.log" ]]; then
    tail -50 "$INSTALL_PATH/singbox.log"
  else
    red "Log file not found"
  fi
}

# Test connection
test_connection() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    red "Config file not found"
    return 1
  fi

  local port=$(grep -oP '"listen_port":\s*\K\d+' "$CONFIG_FILE" | head -1)
  local username=$(grep -oP '"username":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)
  local password=$(grep -oP '"password":\s*"\K[^"]+' "$CONFIG_FILE" | head -1)

  yellow "Testing SOCKS5 connection..."
  echo ""
  echo "You can test using the following methods:"
  echo ""
  echo "1. Test with curl:"
  echo "   curl -x socks5://$username:$password@127.0.0.1:$port https://ifconfig.me"
  echo ""
  echo "2. Set proxy in browser:"
  echo "   Type: SOCKS5"
  echo "   Address: 127.0.0.1"
  echo "   Port: $port"
  echo "   Username: $username"
  echo "   Password: $password"
  echo ""

  if command -v curl &> /dev/null; then
    read -p "Test with curl now? [y/n] [y]: " test_now
    test_now=${test_now:-y}
    if [[ "$test_now" == "y" ]]; then
      echo ""
      yellow "Testing..."
      if curl -s -x "socks5://$username:$password@127.0.0.1:$port" --max-time 10 https://ifconfig.me; then
        echo ""
        green "SOCKS5 proxy is working properly!"
      else
        echo ""
        red "Connection failed, please check config and firewall"
      fi
    fi
  fi
}

# Uninstall
uninstall() {
  read -p "Are you sure you want to uninstall sing-box? This will delete all configs [y/n] [n]: " input
  input=${input:-n}

  if [[ "$input" == "y" ]]; then
    stop_singbox

    # Remove systemd service if exists
    if [[ -f /etc/systemd/system/sing-box.service ]]; then
      sudo systemctl stop sing-box 2>/dev/null
      sudo systemctl disable sing-box 2>/dev/null
      sudo rm -f /etc/systemd/system/sing-box.service
      sudo systemctl daemon-reload
      yellow "Removed systemd service"
    fi

    rm -rf "$INSTALL_PATH"
    green "Uninstall completed"
  else
    yellow "Uninstall cancelled"
  fi
}

# Create systemd service optional
create_systemd_service() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    red "Please configure sing-box first"
    return 1
  fi

  yellow "Creating systemd service..."

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
  green "systemd service created"
  echo ""
  yellow "Use these commands to manage the service:"
  echo "Start: sudo systemctl start sing-box"
  echo "Stop: sudo systemctl stop sing-box"
  echo "Enable auto-start: sudo systemctl enable sing-box"
  echo "Check status: sudo systemctl status sing-box"
  echo "View logs: sudo journalctl -u sing-box -f"
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
    red "Missing dependencies: ${missing_deps[*]}"
    echo "Please install: sudo apt install ${missing_deps[*]} (Debian/Ubuntu)"
    echo "Or: sudo yum install ${missing_deps[*]} (CentOS/RHEL)"
    return 1
  fi

  return 0
}

# Main menu
show_menu() {
  clear
  echo -e "${BLUE}================================${RESET}"
  echo -e "${GREEN} sing-box SOCKS5 Management Script${RESET}"
  echo -e "${GREEN} For Linux Systems${RESET}"
  echo -e "${GREEN} Compatible with sing-box 1.12.0+${RESET}"
  echo -e "${BLUE}================================${RESET}"
  echo ""
  echo "1. Install sing-box"
  echo "2. Configure SOCKS5"
  echo "3. Start sing-box"
  echo "4. Stop sing-box"
  echo "5. Show status"
  echo "6. Show logs"
  echo "7. Test connection"
  echo "8. Create systemd service (recommended)"
  echo "9. Uninstall"
  echo "0. Exit"
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
    read -p "Please select [0-9]: " choice

    case $choice in
      1)
        download_singbox
        read -p "Press Enter to continue..."
        ;;
      2)
        config_socks5
        read -p "Press Enter to continue..."
        ;;
      3)
        start_singbox
        read -p "Press Enter to continue..."
        ;;
      4)
        stop_singbox
        read -p "Press Enter to continue..."
        ;;
      5)
        show_status
        read -p "Press Enter to continue..."
        ;;
      6)
        show_logs
        read -p "Press Enter to continue..."
        ;;
      7)
        test_connection
        read -p "Press Enter to continue..."
        ;;
      8)
        create_systemd_service
        read -p "Press Enter to continue..."
        ;;
      9)
        uninstall
        exit 0
        ;;
      0)
        green "Exiting script"
        exit 0
        ;;
      *)
        red "Invalid selection"
        sleep 2
        ;;
    esac
  done
}

# Run main program
main
