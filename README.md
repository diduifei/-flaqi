# FLVX

高性能流量中转 / 端口转发管理面板。

## 面板端快速部署

在全新的 Debian / Ubuntu 服务器上执行下面这条命令。脚本会打开交互菜单，可选择安装/更新、彻底卸载、修改前后端端口；安装时会自动安装 Docker 和 Docker Compose Plugin，直接拉取 Docker Hub 预构建镜像启动服务，不再在服务器上克隆源码和现场构建镜像。

```bash
curl -L https://raw.githubusercontent.com/diduifei/-flaqi/main/panel_install.sh -o panel_install.sh && bash panel_install.sh
```

默认镜像：

```text
diduifei/flvx-panel:latest
diduifei/flvx-frontend:latest
```

## 节点端快速部署

在面板中添加节点后，复制节点 Token，并在中转机上运行：

```bash
curl -L https://raw.githubusercontent.com/diduifei/-flaqi/main/install.sh -o install.sh && bash install.sh -a 你的主控IP:6365 -s 你的通讯Token
```

节点脚本会自动识别 `linux/amd64` 或 `linux/arm64`，从 GitHub Releases 下载最新 `flvx-agent` 二进制，安装到 `/usr/local/bin/`，并创建 `flvx-agent.service` 由 systemd 托管运行。

## 默认管理账户

首次安装完成后，访问 `http://你的服务器IP:前端端口`，使用以下初始凭据登录：

```text
账号: admin_user
密码: admin_user
```

首次登录后请立即修改默认密码。

## 免责声明

本项目仅供个人学习与研究使用，仅限合法、合规用途。使用者必须确保其使用行为符合所在国家或地区的法律法规，并自行承担因配置、使用或运维不当产生的风险。
