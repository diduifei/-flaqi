#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${FLVX_APP_DIR:-/root/flvx}"
BACKEND_IMAGE="${FLVX_BACKEND_IMAGE:-diduifei/flvx-panel:latest}"
FRONTEND_IMAGE="${FLVX_FRONTEND_IMAGE:-diduifei/flvx-frontend:latest}"
FRONTEND_PORT=""
BACKEND_PORT=""

log() {
  printf '\n==> %s\n' "$*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root." >&2
    exit 1
  fi
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker"
    curl -fsSL https://get.docker.com | bash
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log "Installing Docker Compose plugin"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
    else
      echo "Docker Compose plugin is missing. Please install it manually." >&2
      exit 1
    fi
  fi

  systemctl enable --now docker >/dev/null 2>&1 || true
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

read_port() {
  local prompt default value
  prompt="$1"
  default="$2"

  while true; do
    read -r -p "${prompt}" value
    value="${value:-$default}"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )); then
      echo "$value"
      return
    fi
    echo "请输入 1-65535 之间的端口数字。"
  done
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

write_compose() {
  local jwt_secret
  jwt_secret="$(generate_secret)"

  mkdir -p "${APP_DIR}/data"
  cd "$APP_DIR"

  cat > docker-compose.yml <<EOF
services:
  flvx-server:
    image: ${BACKEND_IMAGE}
    container_name: flvx-server
    restart: always
    ports:
      - "${BACKEND_PORT}:6365"
    environment:
      SERVER_ADDR: ":6365"
      DB_PATH: "/app/data/gost.db"
      JWT_SECRET: "${jwt_secret}"
      TZ: "Asia/Shanghai"
      PANEL_DEPLOY_DIR: "${APP_DIR}"
      PANEL_BACKEND_CONTAINER: "flvx-server"
    volumes:
      - ./data:/app/data
      - /var/run/docker.sock:/var/run/docker.sock
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  flvx-frontend:
    image: ${FRONTEND_IMAGE}
    container_name: flvx-frontend
    restart: always
    ports:
      - "${FRONTEND_PORT}:80"
    depends_on:
      - flvx-server
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
}

start_stack() {
  log "Pulling images and starting FLVX"
  cd "$APP_DIR"
  docker compose pull
  docker compose up -d --remove-orphans
}

main() {
  need_root
  install_base_tools
  install_docker

  echo "请输入您想为面板前端指定的公开访问端口（默认 80）："
  FRONTEND_PORT="$(read_port "" "80")"
  echo "请输入您想为面板后端指定的公开访问端口（默认 6365）："
  BACKEND_PORT="$(read_port "" "6365")"

  mkdir -p "$APP_DIR"
  write_compose
  start_stack

  local ip
  ip="$(curl -fsSL https://ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
  log "FLVX panel installed successfully"
  echo "Frontend: http://${ip}:${FRONTEND_PORT}"
  echo "Backend:  http://${ip}:${BACKEND_PORT}"
  echo "Directory: ${APP_DIR}"
}

main "$@"
