#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${FLVX_REPO_URL:-https://github.com/diduifei/-flaqi.git}"
BRANCH="${FLVX_BRANCH:-main}"
APP_DIR="${FLVX_APP_DIR:-/root/flvx}"

log() {
  printf '\n==> %s\n' "$*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root." >&2
    exit 1
  fi
}

install_base_tools() {
  log "Installing base tools"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and Docker Compose are ready"
    return
  fi

  log "Installing Docker"
  curl -fsSL https://get.docker.com | bash
  systemctl enable --now docker
}

stop_existing_stack() {
  if [[ -f "${APP_DIR}/docker-compose.yml" || -f "${APP_DIR}/compose.yml" ]]; then
    log "Stopping existing FLVX containers"
    (cd "$APP_DIR" && docker compose down) || true
  fi
}

sync_source() {
  if [[ -d "$APP_DIR/.git" ]]; then
    log "Syncing existing source"
    stop_existing_stack
    cd "$APP_DIR"
    git remote set-url origin "$REPO_URL" || true
    git fetch --all
    git reset --hard "origin/${BRANCH}"
    git pull origin "$BRANCH"
    return
  fi

  if [[ -e "$APP_DIR" ]]; then
    log "Replacing non-git directory at ${APP_DIR}"
    stop_existing_stack
    rm -rf "$APP_DIR"
  fi

  log "Cloning source"
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
}

rebuild_stack() {
  log "Building and starting Docker Compose stack"
  cd "$APP_DIR"
  docker compose up -d --build --force-recreate
}

run_caddy_setup() {
  if [[ ! -f "${APP_DIR}/install.sh" ]]; then
    log "install.sh not found, skipping Caddy setup"
    return
  fi

  log "Starting optional Caddy/domain setup"
  cd "$APP_DIR"
  bash install.sh
}

main() {
  need_root
  install_base_tools
  install_docker
  sync_source
  rebuild_stack
  run_caddy_setup

  log "FLVX panel deploy/update completed"
  echo "Source: ${APP_DIR}"
}

main "$@"
