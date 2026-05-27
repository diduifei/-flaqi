#!/usr/bin/env bash
set -Eeuo pipefail

# FLVX custom full-stack installer.
# Defaults to diduifei/-flaqi and builds backend, agent, and frontend from source.

REPO_URL="${FLVX_REPO_URL:-https://github.com/diduifei/-flaqi.git}"
BRANCH="${FLVX_BRANCH:-main}"
APP_DIR="${FLVX_APP_DIR:-/opt/flvx}"
DATA_DIR="${FLVX_DATA_DIR:-/var/lib/flvx}"
CONFIG_DIR="${FLVX_CONFIG_DIR:-/etc/flvx}"
WEB_DIR="${FLVX_WEB_DIR:-/var/www/flvx}"
AGENT_CONFIG_DIR="${FLVX_AGENT_CONFIG_DIR:-/etc/flux_agent}"
BACKEND_ADDR="${FLVX_BACKEND_ADDR:-127.0.0.1:6365}"
PUBLIC_URL="${FLVX_PUBLIC_URL:-http://127.0.0.1:6365}"
AGENT_SECRET="${FLVX_AGENT_SECRET:-}"
GO_VERSION="${FLVX_GO_VERSION:-1.25.7}"
PNPM_VERSION="${FLVX_PNPM_VERSION:-11.3.0}"

log() {
  printf '\n==> %s\n' "$*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root." >&2
    exit 1
  fi
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;
  esac
}

install_base_packages() {
  log "Installing system dependencies"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl wget git gnupg lsb-release apt-transport-https \
    nftables build-essential openssl
  systemctl enable --now nftables || true
}

enable_kernel_forwarding() {
  log "Enabling Linux kernel IP forwarding"
  sysctl -w net.ipv4.ip_forward=1
  if grep -qE '^[#[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' /etc/sysctl.conf; then
    sed -i -E 's|^[#[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=.*|net.ipv4.ip_forward = 1|' /etc/sysctl.conf
  else
    printf '\nnet.ipv4.ip_forward = 1\n' >> /etc/sysctl.conf
  fi
  sysctl -p
}

install_caddy() {
  log "Installing Caddy"
  if ! command -v caddy >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/deb.deb.txt \
      -o /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
  fi
}

install_go() {
  log "Installing Go ${GO_VERSION}"
  if command -v go >/dev/null 2>&1 && go version | grep -q "go${GO_VERSION}"; then
    return
  fi
  local arch tarball
  arch="$(arch_name)"
  tarball="/tmp/go${GO_VERSION}.linux-${arch}.tar.gz"
  wget -O "$tarball" "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tarball"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
}

install_node_and_pnpm() {
  log "Installing Node.js and pnpm"
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
  fi
  corepack enable
  corepack prepare "pnpm@${PNPM_VERSION}" --activate
}

fetch_source() {
  log "Fetching source from ${REPO_URL}"
  rm -rf "$APP_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$APP_DIR" \
    || git clone --depth 1 "$REPO_URL" "$APP_DIR"
}

build_backend() {
  log "Building backend"
  cd "$APP_DIR/go-backend"
  /usr/local/go/bin/go env -w GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"
  /usr/local/go/bin/go build -o /usr/local/bin/flvx-server ./cmd/paneld
}

build_agent() {
  log "Building agent"
  cd "$APP_DIR/go-gost"
  CGO_ENABLED=0 /usr/local/go/bin/go build -ldflags="-s -w" -o /usr/local/bin/flvx-agent .
}

build_frontend() {
  log "Building frontend"
  cd "$APP_DIR/vite-frontend"
  corepack pnpm install --frozen-lockfile
  corepack pnpm run build
  rm -rf "$WEB_DIR"
  install -d -m 0755 "$WEB_DIR"
  cp -a dist/. "$WEB_DIR/"
}

write_backend_service() {
  log "Configuring backend service"
  install -d -m 0755 "$CONFIG_DIR" "$DATA_DIR"
  if [[ ! -f "$CONFIG_DIR/backend.env" ]]; then
    umask 077
    cat > "$CONFIG_DIR/backend.env" <<EOF
SERVER_ADDR=${BACKEND_ADDR}
DB_PATH=${DATA_DIR}/gost.db
JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || date +%s%N)
EOF
  fi

  cat > /etc/systemd/system/flvx-server.service <<EOF
[Unit]
Description=FLVX admin API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_DIR}/backend.env
WorkingDirectory=${DATA_DIR}
ExecStart=/usr/local/bin/flvx-server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

write_agent_service() {
  log "Configuring agent service"
  install -d -m 0755 "$AGENT_CONFIG_DIR"
  if [[ -n "$AGENT_SECRET" ]]; then
    cat > "$AGENT_CONFIG_DIR/config.json" <<EOF
{
  "addr": "${PUBLIC_URL}",
  "secret": "${AGENT_SECRET}",
  "http": 1,
  "tls": 1,
  "socks": 1
}
EOF
  elif [[ ! -f "$AGENT_CONFIG_DIR/config.json" ]]; then
    cat > "$AGENT_CONFIG_DIR/config.example.json" <<EOF
{
  "addr": "${PUBLIC_URL}",
  "secret": "paste-node-secret-here",
  "http": 1,
  "tls": 1,
  "socks": 1
}
EOF
  fi

  cat > /etc/systemd/system/flvx-agent.service <<EOF
[Unit]
Description=FLVX forwarding agent
After=network-online.target flvx-server.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${AGENT_CONFIG_DIR}
ExecStart=/usr/local/bin/flvx-agent
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

write_caddyfile() {
  log "Configuring Caddy"
  cat > /etc/caddy/Caddyfile <<EOF
:80 {
    root * ${WEB_DIR}
    encode gzip zstd
    try_files {path} {path}/ /index.html
    file_server

    reverse_proxy /api/* ${BACKEND_ADDR}
    reverse_proxy /system-info* ${BACKEND_ADDR}
}
EOF
}

start_services() {
  log "Starting services"
  systemctl daemon-reload
  systemctl enable --now flvx-server
  systemctl restart caddy
  if [[ -f "$AGENT_CONFIG_DIR/config.json" ]]; then
    systemctl enable --now flvx-agent
  else
    systemctl enable flvx-agent >/dev/null 2>&1 || true
    echo "Agent binary installed. Create ${AGENT_CONFIG_DIR}/config.json with a node secret, then run: systemctl start flvx-agent"
  fi
}

main() {
  need_root
  install_base_packages
  enable_kernel_forwarding
  install_caddy
  install_go
  install_node_and_pnpm
  fetch_source
  build_backend
  build_agent
  build_frontend
  write_backend_service
  write_agent_service
  write_caddyfile
  start_services

  local ip
  ip="$(curl -fsSL https://ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
  log "FLVX is ready"
  echo "Panel: http://${ip}"
  echo "Backend: ${BACKEND_ADDR}"
}

main "$@"
