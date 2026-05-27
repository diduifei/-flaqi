#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_IMAGE="${FLVX_AGENT_IMAGE:-diduigege/flvx-agent:latest}"
CONTAINER_NAME="${FLVX_AGENT_CONTAINER:-flvx-agent}"
SERVER_ADDR=""
NODE_SECRET=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo -e "${RED}❌ 参数错误！正确用法：${NC}" >&2
  echo "bash agent_install.sh -a 面板IP:端口 -s 通信密钥" >&2
  echo "示例：bash agent_install.sh -a 1.2.3.4:6365 -s your_token" >&2
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
    fail "请使用 Root 权限运行本脚本。"
  fi
}

install_base_tools() {
  if command -v apt-get >/dev/null 2>&1; then
    run_step "apt update 失败，请检查网络或软件源！" apt-get update
    run_step "安装基础依赖失败！" env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
  elif command -v yum >/dev/null 2>&1; then
    run_step "安装基础依赖失败！" yum install -y ca-certificates curl
  elif command -v dnf >/dev/null 2>&1; then
    run_step "安装基础依赖失败！" dnf install -y ca-certificates curl
  fi
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "未检测到 Docker，正在自动安装"
    if ! curl -fsSL https://get.docker.com | bash; then
      fail "Docker 安装失败，请检查网络！"
    fi
  fi

  systemctl enable --now docker >/dev/null 2>&1 || true
  if ! docker info >/dev/null 2>&1; then
    fail "Docker 服务未正常运行，请先检查 systemctl status docker。"
  fi
}

deploy_agent() {
  log "清理旧节点容器"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  log "拉取节点镜像：${AGENT_IMAGE}"
  if ! docker pull "$AGENT_IMAGE"; then
    fail "拉取节点 Docker 镜像失败，请检查网络或 Docker Hub 镜像是否存在！"
  fi

  log "启动节点容器"
  if ! docker run -d \
    --name "$CONTAINER_NAME" \
    --network host \
    --restart always \
    --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$AGENT_IMAGE" ./flvx-agent -a "$SERVER_ADDR" -s "$NODE_SECRET"; then
    fail "docker run 执行失败，节点容器未创建成功！"
  fi

  health_check_agent
}

print_agent_logs() {
  echo -e "${YELLOW}========== ${CONTAINER_NAME} 最近 15 行日志 ==========${NC}" >&2
  docker logs --tail 15 "$CONTAINER_NAME" 2>&1 || true
  echo -e "${YELLOW}===============================================${NC}" >&2
}

health_check_agent() {
  local status

  log "等待节点启动并执行健康检查"
  sleep 3

  if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    fail "节点容器不存在，部署失败！"
  fi

  status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [[ "$status" != "running" ]]; then
    echo -e "${RED}❌ 节点端安装失败，容器启动失败或不断崩溃！当前状态: ${status:-unknown}${NC}" >&2
    print_agent_logs
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
install_base_tools
install_docker
deploy_agent

echo -e "${GREEN}🎉 节点端安装成功，已尝试连接到面板！${NC}"
echo -e "${GREEN}面板地址: ${SERVER_ADDR}${NC}"
echo -e "${GREEN}容器名称: ${CONTAINER_NAME}${NC}"
