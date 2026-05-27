#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${FLVX_REPO:-diduifei/-flaqi}"
VERSION="${FLVX_AGENT_VERSION:-latest-agent}"
INSTALL_DIR="${FLVX_AGENT_INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${FLVX_AGENT_CONFIG_DIR:-/etc/flvx-agent}"
SERVICE_FILE="/etc/systemd/system/flvx-agent.service"
SERVER_ADDR=""
NODE_SECRET=""
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<USAGE
Usage: bash install.sh -a <panel-address:port> -s <node-secret>

Options:
  -a    Panel server address, for example 1.2.3.4:6365
  -s    Node communication secret/token
  -v    Release tag to install, defaults to latest-agent
  -h    Show this help
USAGE
}

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  echo -e "${RED}❌ 错误：$*${NC}" >&2
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
    fail "Please run as root."
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

install_base_tools() {
  if command -v apt-get >/dev/null 2>&1; then
    run_step "apt update failed, please check network or apt sources." apt-get update
    run_step "failed to install base tools." env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
  elif command -v yum >/dev/null 2>&1; then
    run_step "failed to install base tools." yum install -y ca-certificates curl
  elif command -v dnf >/dev/null 2>&1; then
    run_step "failed to install base tools." dnf install -y ca-certificates curl
  fi
}

download_agent() {
  local arch url tmp
  arch="$(detect_arch)"
  tmp="/tmp/flvx-agent-linux-${arch}"

  if [[ "$VERSION" == "latest" ]]; then
    url="https://github.com/${REPO}/releases/latest/download/flvx-agent-linux-${arch}"
  else
    url="https://github.com/${REPO}/releases/download/${VERSION}/flvx-agent-linux-${arch}"
  fi

  log "Downloading flvx-agent (${arch}) from ${url}"
  run_step "failed to download flvx-agent binary from GitHub Releases." curl -fL "$url" -o "$tmp"
  run_step "failed to install flvx-agent into ${INSTALL_DIR}." install -m 0755 "$tmp" "${INSTALL_DIR}/flvx-agent"
}

write_service() {
  log "Writing systemd service"
  run_step "failed to create config directory." install -d -m 0755 "$CONFIG_DIR"

  if ! cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "addr": "${SERVER_ADDR}",
  "secret": "${NODE_SECRET}",
  "http": 1,
  "tls": 1,
  "socks": 1
}
EOF
  then
    fail "failed to write agent config."
  fi
  run_step "failed to protect agent config permissions." chmod 0600 "${CONFIG_DIR}/config.json"

  if ! cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FLVX forwarding agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${CONFIG_DIR}
ExecStart=${INSTALL_DIR}/flvx-agent -a ${SERVER_ADDR} -s ${NODE_SECRET}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  then
    fail "failed to write systemd service."
  fi
}

start_service() {
  log "Starting flvx-agent"
  run_step "systemctl daemon-reload failed." systemctl daemon-reload
  run_step "failed to enable/start flvx-agent service." systemctl enable --now flvx-agent
  health_check_agent
}

health_check_agent() {
  log "Waiting for flvx-agent health check"
  sleep 5

  if ! systemctl is-active --quiet flvx-agent; then
    echo -e "${RED}❌ 致命错误：flvx-agent 启动失败或不断崩溃！${NC}" >&2
    echo -e "${YELLOW}========== flvx-agent 最近 15 行日志 ==========${NC}" >&2
    journalctl -u flvx-agent -n 15 --no-pager || true
    echo -e "${YELLOW}===============================================${NC}" >&2
    exit 1
  fi
}

while getopts ":a:s:v:h" opt; do
  case "$opt" in
    a) SERVER_ADDR="$OPTARG" ;;
    s) NODE_SECRET="$OPTARG" ;;
    v) VERSION="$OPTARG" ;;
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
install_base_tools
download_agent
write_service
start_service

log "FLVX agent installed successfully"
echo -e "${GREEN}Panel: ${SERVER_ADDR}${NC}"
echo -e "${GREEN}Service: systemctl status flvx-agent${NC}"
