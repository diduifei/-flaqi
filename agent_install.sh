#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${FLVX_REPO:-diduifei/-flaqi}"
RELEASE_TAG="${FLVX_AGENT_RELEASE_TAG:-latest-agent}"
BINARY_PATH="${FLVX_AGENT_BINARY:-/usr/local/bin/flvx-agent}"
SERVICE_NAME="${FLVX_AGENT_SERVICE:-flvx-agent}"
ENV_DIR="/etc/flvx-agent"
ENV_FILE="${ENV_DIR}/agent.env"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

SERVER_ADDR=""
NODE_SECRET=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo -e "${RED}参数错误。正确用法：${NC}" >&2
  echo "bash agent_install.sh -a 面板IP:端口 -s 通信密钥" >&2
  echo "示例：bash agent_install.sh -a 1.2.3.4:6365 -s your_token" >&2
}

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  echo -e "${RED}错误：$*${NC}" >&2
  exit 1
}

run_step() {
  local message="$1"
  shift
  if ! "$@"; then
    fail "$message"
  fi
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "请使用 root 权限运行本脚本。"
  fi
}

require_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    fail "未检测到 systemd/systemctl，无法创建 flvx-agent 守护进程。"
  fi
}

install_base_tools() {
  log "检查并安装基础依赖"
  if command -v apt-get >/dev/null 2>&1; then
    run_step "apt update 失败，请检查网络或软件源。" apt-get update
    run_step "安装基础依赖失败。" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ca-certificates curl wget nftables iptables iproute2
  elif command -v yum >/dev/null 2>&1; then
    run_step "安装基础依赖失败。" yum install -y \
      ca-certificates curl wget nftables iptables iproute
  elif command -v dnf >/dev/null 2>&1; then
    run_step "安装基础依赖失败。" dnf install -y \
      ca-certificates curl wget nftables iptables iproute
  else
    fail "未识别的 Linux 发行版，请手动安装 curl/wget/nftables/iptables/iproute2。"
  fi
}

detect_arch() {
  local raw_arch
  raw_arch="$(uname -m)"
  case "$raw_arch" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      fail "暂不支持当前系统架构：${raw_arch}，仅支持 amd64 和 arm64。"
      ;;
  esac
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 -o "$output" "$url"
    return $?
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
    return $?
  fi

  return 1
}

download_agent_binary() {
  local arch asset url tmp_file
  arch="$(detect_arch)"
  asset="flvx-agent-linux-${arch}"
  url="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${asset}"
  tmp_file="$(mktemp)"

  log "下载 FLVX Agent 二进制：${asset}"
  if ! download_file "$url" "$tmp_file"; then
    rm -f "$tmp_file"
    fail "下载 Agent 二进制失败：${url}"
  fi

  run_step "安装 Agent 二进制失败。" install -m 0755 "$tmp_file" "$BINARY_PATH"
  rm -f "$tmp_file"
}

systemd_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

write_env_file() {
  run_step "创建 Agent 配置目录失败。" mkdir -p "$ENV_DIR"
  umask 077
  cat > "$ENV_FILE" <<EOF
SERVER_ADDR=$(systemd_env_value "$SERVER_ADDR")
NODE_SECRET=$(systemd_env_value "$NODE_SECRET")
EOF
  chmod 600 "$ENV_FILE"
}

write_systemd_service() {
  log "写入 systemd 服务：${SERVICE_FILE}"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FLVX Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
WorkingDirectory=/usr/local/bin
ExecStart=${BINARY_PATH} -a \${SERVER_ADDR} -s \${NODE_SECRET}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

enable_ip_forward() {
  log "开启系统 IPv4 转发"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

  if [[ -f /etc/sysctl.conf ]]; then
    if ! grep -qE '^\s*net\.ipv4\.ip_forward\s*=' /etc/sysctl.conf; then
      echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    else
      sed -i 's/^\s*net\.ipv4\.ip_forward\s*=.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
    fi
  fi
}

start_agent_service() {
  log "启动 FLVX Agent systemd 服务"
  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  run_step "systemctl daemon-reload 失败。" systemctl daemon-reload
  run_step "启动 flvx-agent 服务失败。" systemctl enable --now "$SERVICE_NAME"

  sleep 3
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${RED}Agent 服务启动失败，最近日志如下：${NC}" >&2
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
    exit 1
  fi
}

while getopts ":a:s:h" opt; do
  case "$opt" in
    a) SERVER_ADDR="$OPTARG" ;;
    s) NODE_SECRET="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$SERVER_ADDR" || -z "$NODE_SECRET" ]]; then
  usage
  exit 1
fi

need_root
require_systemd
install_base_tools
download_agent_binary
write_env_file
write_systemd_service
enable_ip_forward
start_agent_service

echo -e "${GREEN}"
cat <<EOF
=========================================
FLVX Agent 裸机版安装成功！
=========================================
面板地址: ${SERVER_ADDR}
二进制路径: ${BINARY_PATH}
服务名称: ${SERVICE_NAME}

查看实时日志:
journalctl -u ${SERVICE_NAME} -f

查看服务状态:
systemctl status ${SERVICE_NAME}
=========================================
EOF
echo -e "${NC}"
