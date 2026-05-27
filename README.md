# FLVX

高性能的流量中转 / 端口转发管理面板。

---

## 部署流程 (Docker Compose 部署)

换到任何全新的服务器上，确保系统已安装 Docker 和 Docker Compose，直接复制运行以下单行命令，系统会自动拉取专属源码并现场构建 Docker 容器跑起来。

### 快速部署 (一键安装)

**面板端 (Panel)：**

```bash
git clone https://github.com/diduifei/-flaqi.git /root/flvx && cd /root/flvx && docker compose up -d --build
```

**节点端 (Agent)：**

由于当前版本已经集成 nftables 内核态转发，节点端也必须现场克隆你的魔改源码并本地 Build，不能拉取官方旧镜像。把面板生成的主控 IP 和通讯 Token 填进去后，在中转机上运行：

```bash
git clone https://github.com/diduifei/-flaqi.git /root/flvx_agent && cd /root/flvx_agent/go-backend && docker build -t flvx-agent-local . && docker run -d --name flvx-agent --network host --restart always --privileged -v /var/run/docker.sock:/var/run/docker.sock flvx-agent-local ./flvx-agent -a 你的主控IP:6365 -s 你的通讯Token
```

## 默认管理账户

首次安装完成后，访问前端 `http://你的服务器IP` (默认 80 端口)，使用以下初始凭据登录面板：

```text
账号: admin_user
密码: admin_user
```

安全提示：首次登录成功后，请立即前往面板设置修改默认密码。

## 免责声明

本项目仅供个人学习与研究使用，基于开源项目进行二次开发。

使用本项目所带来的任何风险均由使用者自行承担，包括但不限于：

- 配置不当或使用错误导致的服务异常或不可用；
- 使用本项目引发的网络攻击、封禁、滥用等行为；
- 服务器因使用本项目被入侵、渗透、滥用导致的数据泄露、资源消耗或损失；
- 因违反当地法律法规所产生的任何法律责任。

本项目为开源的流量转发工具，仅限合法、合规用途。使用者必须确保其使用行为符合所在国家或地区的法律法规。

作者不对因使用本项目导致的任何法律责任、经济损失或其他后果承担责任。禁止将本项目用于任何违法或未经授权的行为，包括但不限于网络攻击、数据窃取、非法访问等。

如不同意上述条款，请立即停止使用本项目。
