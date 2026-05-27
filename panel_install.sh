#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${FLVX_APP_DIR:-/root/flvx}"
BACKEND_IMAGE="${FLVX_BACKEND_IMAGE:-diduifei/flvx-panel:latest}"
FRONTEND_IMAGE="${FLVX_FRONTEND_IMAGE:-diduifei/flvx-frontend:latest}"
FRONTEND_PORT=""
BACKEND_PORT=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  printf '\n==> %s\n' "$*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 root 用户运行本脚本。" >&2
    exit 1
  fi
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

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "正在安装 Docker"
    curl -fsSL https://get.docker.com | bash
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log "正在安装 Docker Compose Plugin"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
    else
      echo -e "${RED}Docker Compose Plugin 未安装，请手动安装后重试。${NC}" >&2
      exit 1
    fi
  fi

  systemctl enable --now docker >/dev/null 2>&1 || true
}

show_menu() {
  cat <<'MENU'
 ==================================
  欢迎使用 FLVX 面板一键管理脚本
 ==================================
  1. 安装/更新 FLVX 面板
  2. 彻底卸载 FLVX 面板
  3. 修改面板端口 (前端/后端)
  4. 退出脚本
 ==================================
MENU
  read -r -p "请输入数字选择 [1-4]: " MENU_CHOICE
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

is_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "sport = :${port}" 2>/dev/null | grep -q .
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN -Pn >/dev/null 2>&1
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\.)${port}$"
    return $?
  fi

  return 1
}

get_current_port() {
  local container_port="$1"
  local compose_file="${APP_DIR}/docker-compose.yml"

  [[ -f "$compose_file" ]] || return 0
  grep -Eo "\"[0-9]+:${container_port}\"" "$compose_file" \
    | head -n 1 \
    | tr -d '"' \
    | cut -d: -f1
}

read_port_with_check() {
  local prompt="$1"
  local default_port="$2"
  local allowed_current="${3:-}"
  local value

  while true; do
    printf "%s" "$prompt" >&2
    read -r value
    value="${value:-$default_port}"

    if ! is_valid_port "$value"; then
      echo -e "${RED}❌ 请输入 1-65535 之间的端口数字。${NC}" >&2
      continue
    fi

    if [[ -n "$allowed_current" && "$value" == "$allowed_current" ]]; then
      echo "$value"
      return
    fi

    if is_port_in_use "$value"; then
      echo -e "${YELLOW}⚠️ 端口 ${value} 已被占用，请换一个端口。${NC}" >&2
      continue
    fi

    echo "$value"
    return
  done
}

setup_ports() {
  local current_frontend current_backend frontend_default backend_default

  current_frontend="$(get_current_port 80 || true)"
  current_backend="$(get_current_port 6365 || true)"
  frontend_default="${current_frontend:-80}"
  backend_default="${current_backend:-6365}"

  FRONTEND_PORT="$(read_port_with_check "请输入您想为面板前端指定的公开访问端口（默认 ${frontend_default}）: " "$frontend_default" "$current_frontend")"

  while true; do
    BACKEND_PORT="$(read_port_with_check "请输入您想为面板后端指定的公开访问端口（默认 ${backend_default}）: " "$backend_default" "$current_backend")"
    if [[ "$BACKEND_PORT" != "$FRONTEND_PORT" ]]; then
      break
    fi
    echo -e "${RED}❌ 前端端口和后端端口不能相同，请重新输入后端端口。${NC}"
  done
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

get_or_create_jwt_secret() {
  local env_file="${APP_DIR}/.flvx.env"
  local secret=""

  if [[ -f "$env_file" ]]; then
    secret="$(grep -E '^JWT_SECRET=' "$env_file" | tail -n 1 | cut -d= -f2- || true)"
  fi

  if [[ -z "$secret" ]]; then
    secret="$(generate_secret)"
    mkdir -p "$APP_DIR"
    umask 077
    printf 'JWT_SECRET=%s\n' "$secret" > "$env_file"
  fi

  echo "$secret"
}

deploy_panel() {
  local jwt_secret
  jwt_secret="$(get_or_create_jwt_secret)"

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

  log "正在拉取镜像并启动 FLVX 面板"
  docker compose pull
  docker compose up -d --remove-orphans
}

install_or_update_panel() {
  install_base_tools
  install_docker
  setup_ports
  mkdir -p "$APP_DIR"
  deploy_panel

  local ip
  ip="$(curl -fsSL https://ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"
  log "FLVX 面板安装/更新完成"
  echo -e "${GREEN}✨ 前端地址: http://${ip}:${FRONTEND_PORT}${NC}"
  echo -e "${GREEN}✨ 后端端口: ${BACKEND_PORT}${NC}"
  echo "安装目录: ${APP_DIR}"
}

uninstall_panel() {
  local confirm
  read -r -p "⚠️ 警告：卸载将删除所有面板容器和数据，是否确定？(y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消卸载。"
    return
  fi

  if [[ -d "$APP_DIR" ]]; then
    if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
      log "正在停止并清理 FLVX 容器、镜像和数据卷"
      (cd "$APP_DIR" && docker compose down --rmi all --volumes) || true
    fi
    log "正在删除安装目录"
    rm -rf "$APP_DIR"
  else
    echo -e "${YELLOW}未检测到 ${APP_DIR}，无需清理安装目录。${NC}"
  fi

  echo -e "${GREEN}✨ FLVX 面板已成功从您的服务器彻底卸载！${NC}"
}

change_ports() {
  if [[ ! -d "$APP_DIR" || ! -f "${APP_DIR}/docker-compose.yml" ]]; then
    echo -e "${RED}❌ 未检测到已安装的面板，请先选择 1 进行安装！${NC}"
    return
  fi

  install_base_tools
  install_docker
  setup_ports
  deploy_panel

  echo -e "${GREEN}✨ 面板端口修改成功！您的新前端端口为: ${FRONTEND_PORT}，新后端端口为: ${BACKEND_PORT}${NC}"
}

main() {
  need_root
  show_menu

  case "$MENU_CHOICE" in
    1) install_or_update_panel ;;
    2) uninstall_panel ;;
    3) change_ports ;;
    4|0)
      echo "已退出。"
      ;;
    *)
      echo -e "${RED}❌ 无效选择，请重新运行脚本并输入 1-4。${NC}"
      exit 1
      ;;
  esac
}

main "$@"
