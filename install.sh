#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${FLVX_REPO:-diduifei/-flaqi}"
VERSION="${FLVX_AGENT_VERSION:-latest-agent}"
INSTALL_DIR="${FLVX_AGENT_INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${FLVX_AGENT_CONFIG_DIR:-/etc/flvx-agent}"
SERVICE_FILE="/etc/systemd/system/flvx-agent.service"
SERVER_ADDR=""
NODE_SECRET=""

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

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root." >&2
    exit 1
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
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl
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
  curl -fL "$url" -o "$tmp"
  install -m 0755 "$tmp" "${INSTALL_DIR}/flvx-agent"
}

write_service() {
  log "Writing systemd service"
  install -d -m 0755 "$CONFIG_DIR"

  cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "addr": "${SERVER_ADDR}",
  "secret": "${NODE_SECRET}",
  "http": 1,
  "tls": 1,
  "socks": 1
}
EOF
  chmod 0600 "${CONFIG_DIR}/config.json"

  cat > "$SERVICE_FILE" <<EOF
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
}

start_service() {
  log "Starting flvx-agent"
  systemctl daemon-reload
  systemctl enable --now flvx-agent
  systemctl status flvx-agent --no-pager || true
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
echo "Panel: ${SERVER_ADDR}"
echo "Service: systemctl status flvx-agent"
