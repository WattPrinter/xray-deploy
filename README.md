# Debian 12 Xray 一键部署工具

使用 Bash、Xray-core 官方稳定版、VLESS + REALITY、TCP、`xtls-rprx-vision` 和 systemd。仅支持 Debian 12 Bookworm，请以 root 运行。

## 安装

完整下载此仓库，保持以下五个文件在同一目录：

```text
install.sh
xray-link
xray-qrcode
xray-reconfigure
README.md
```

本仓库为 Public。Debian 12 服务器已安装 Git 时，以 root 执行：

```bash
git clone https://github.com/WattPrinter/xray-deploy.git
cd xray-deploy
bash install.sh
```

也可以通过 SCP 将这五个文件上传到服务器后运行安装器。本地执行时，仍需保持三个管理脚本与安装器在同一目录。

### curl 一键安装

在 Debian 12 的 root SSH 交互终端执行（需已安装 `curl` 和 `ca-certificates`）：

```bash
curl -fsSL https://raw.githubusercontent.com/WattPrinter/xray-deploy/main/install.sh | bash
```

安装器通过标准输入执行时，先完整解析代码，再从 `/dev/tty` 读取密码及后续交互输入；无交互终端时会停止。密码正确后，在权限仅允许当前用户访问的随机临时目录下载三个管理脚本，并检查非空、SHA-256 和 Bash 语法。全部验证通过后才进入原有 apt、配置和部署流程。下载失败、校验失败、安装结束或失败退出时删除临时目录，不留下临时脚本。

远程管理脚本固定来自提交 `6bf36a421e09fb30f2fb3afb9a71a4a5e0c1e5e5`，与当前安装器配套的三个管理脚本内容完全相同，并在安装器中固定对应校验值。因此下载期间 `main` 变化不会混入其他版本。后续维护如修改管理脚本，必须同步更新固定快照和校验值。

本地执行仍从安装器自身目录读取管理脚本，不下载远程副本。两种入口均安装到 `/root/xray-link`、`/root/xray-qrcode` 和 `/root/xray-reconfigure`，重复安装继续保留已有身份参数。

安装器要求输入安装密码，输入不会回显，最多尝试三次。密码请向维护者获取；源码仅保存随机盐和 SHA-256 哈希。验证成功后才执行依赖安装和原有部署流程，`--help` 无需密码。三个管理工具的行为不变。

这是轻量使用门槛：修改源码即可绕过哈希验证，并非真正的访问控制，也不能保护公开源码或阻止离线猜测。

现有 `v1.0.0` 是此前发布的版本，不含安装密码验证；新增验证目前应使用 `main` 分支。不会覆盖已发布的正式版本。

也可以下载正式版本的 [Source code ZIP](https://github.com/WattPrinter/xray-deploy/archive/refs/tags/v1.0.0.zip)，在本机上传 VPS（替换服务器地址）：

```bash
scp xray-deploy-1.0.0.zip root@服务器地址:/root/
```

随后登录 Debian 12 VPS，以 root 解压并安装：

```bash
apt-get update
apt-get install -y --no-install-recommends unzip
unzip /root/xray-deploy-1.0.0.zip -d /root/
bash /root/xray-deploy-1.0.0/install.sh
```

上述手动准备解压工具的命令独立于安装器；安装器自身的 apt 操作仍在密码验证成功后执行。

项目可以放在 Debian 12 的任意目录，包括含空格的目录及 `/root/`。安装器使用 `${BASH_SOURCE[0]}` 定位自身目录，再读取同目录的三个管理脚本，不依赖运行命令时的当前工作目录。例如，项目位于 `/opt/xray-deploy/` 时，可以从其他目录调用：

```bash
cd /tmp
bash /opt/xray-deploy/install.sh
```

安装后管理脚本是 `/root/` 下的独立文件；如果项目本身就在 `/root/`，安装器只为同一文件设置执行权限，避免将文件复制到自身。Xray 核心、配置及 systemd 启动命令均使用安装后的绝对路径。安装完成后可以删除原项目目录，Xray 服务和三个管理工具仍可正常使用；以后重新执行安装器时，再获取完整项目即可。

安装器先执行一次 `apt-get update`，然后一次性安装必要依赖：`curl`、`ca-certificates`、`openssl`、`jq`、`qrencode`、`iproute2`、`iptables`、`nftables`、`procps` 和 `unzip`。不安装面板、Docker、Python 或 Web 服务。依赖安装失败立即停止。

apt 失败时使用中文报告，并将原始诊断输出保存到仅 root 可读的 `/root/xray-deploy-apt.log`，便于检查锁占用、软件源或网络问题。该文件只在失败时产生，不含 Xray 身份参数。

首次安装依次询问端口、REALITY 目标网站和公网 IPv4。默认端口为 443，默认目标为 `www.apple.com`。也可以选择 Microsoft、Cloudflare 或自定义域名。所有目标都必须通过本机 TLS 1.3 握手、证书验证和 SNI 检查；该检查不代替 REALITY 客户端测试。

公网 IPv4 自动检测只接受有效公网地址，排除内网、共享地址及环回地址。检测失败必须手动输入。不支持仅有 IPv6 或没有入站映射的共享 IPv4 服务器。自动检测得到的出口地址也可能经过 NAT；此时必须自行确认公网入站映射，并输入正确地址。端口已被其他程序占用时重新选择，不会停止占用程序。

显示配置摘要并确认后，安装器通过 [XTLS 官方安装器](https://github.com/XTLS/Xray-install) 安装最新非预发布稳定版，不下载无关的地理数据。首次安装自动生成 UUID、X25519 密钥和 16 位十六进制 Short ID。

依据[当前官方 REALITY 配置](https://xtls.github.io/en/config/transports/reality.html)，服务端使用 `target`（旧名称为 `dest`），TCP 传输使用 `network: "raw"`。分享链接仍使用客户端 URI 参数 `type=tcp` 和 `pbk`。这两种表示对应同一个 TCP + REALITY 连接方案。

## 安装后的文件

```text
/root/xray-link
/root/xray-qrcode
/root/xray-reconfigure
/usr/local/etc/xray/config.json
/usr/local/etc/xray/deploy.json
/etc/systemd/system/xray.service.d/20-xray-deploy.conf
```

`config.json` 是唯一的身份和协议参数来源。`deploy.json` 只记录服务器连接地址，不保存第二套 UUID、密钥、端口或目标网站。公钥通过 OpenSSL 从当前配置中的私钥推导，不另行保存。

配置目录权限为 700，配置及元数据为 600，三个管理脚本为 700，全部归 root 所有。通过官方 systemd 单元的补充配置让 Xray 以 root 读取这些文件。启动后在 `/run/xray-deploy/config.sha256` 保存所加载配置的校验值，连接工具会检查它；如果手动编辑配置但未重启服务，工具会停止输出链接并给出中文提示。

本工具管理一个 VLESS + REALITY 入站、一个客户端和一个 Short ID。其他入站和其他配置项在身份重置时保留。对于多客户端、多 REALITY 入站、多配置文件或无效的现有配置，安装器停止并保留文件，不尝试自动迁移。

## 管理工具

显示可导入 v2rayN 的完整 VLESS 分享链接：

```bash
/root/xray-link
```

本次输出临时使用另一个公网 IPv4，不修改保存的地址：

```bash
/root/xray-link 你的公网IPv4
```

链接包含 UUID、地址、端口及 `type`、`security`、`flow`、`sni`、`pbk`、`sid`、`fp`，查询参数和节点名称正确进行 URI 编码。该命令不修改配置，不生成新身份，也不输出私钥。

显示终端二维码：

```bash
/root/xray-qrcode
# 同样允许本次指定连接地址
/root/xray-qrcode 你的公网IPv4
```

二维码工具直接调用连接工具，再把同一条链接交给 `qrencode`，没有独立配置。普通支持 UTF-8 和 ANSI 颜色的 SSH 终端即可显示；字体应等宽。

重置身份：

```bash
/root/xray-reconfigure
```

默认取消，必须输入 `y` 确认。确认后只更改 UUID、REALITY 私钥及 Short ID，公钥从新私钥推导。端口、目标、`serverNames`、`flow` 及其他配置项保持原样。候选配置校验通过后原子替换并重启服务，检查服务和该进程的 TCP 监听。候选校验失败不动原配置；替换后启动或监听检查失败则恢复原配置并重启原服务。

成功时按要求在当前终端显示新的全部身份参数（包含私钥）、分享链接和二维码。不要将该终端输出上传到仓库、公开日志或公开工单。工具不把密钥发送给 systemd journal。若回滚服务失败，工具报告保留备份的路径，应按提示手动恢复。

所有工具均支持 `--help`。重新运行安装器可以补齐管理工具及依赖，保留现有配置、身份、端口和目标；不自动升级现有核心。安装和身份重置共用 `flock` 锁，避免并发修改。安装器会重启现有服务以应用服务补充配置，因此有短暂连接中断。

## 防火墙与连接验证

只处理用户选择的 Xray TCP 端口：

- 已启用 UFW：在用户规则前部添加对应的持久化 TCP 放行规则，保留 SSH 和其他规则。
- 简单 iptables：只支持标准 INPUT 链、不包含自定义入站跳转，并且已有启用的 `netfilter-persistent`；独立 systemd 单元在原规则恢复后重放本端口规则。
- 简单 nftables：只支持一个 `inet` 输入基础链，已有启用且语法有效的 `/etc/nftables.conf`；同样通过独立 systemd 单元重放本端口规则。
- 没有生效的本地入站过滤规则：不额外开启防火墙。
- 混合防火墙、多输入链或无法可靠识别的规则：使用中文报告并停止，请管理员手动处理目标端口。

需要独立持久化时，额外安装 `/usr/local/libexec/xray-deploy-firewall` 及 `/etc/systemd/system/xray-deploy-firewall.service`，只保存本工具的放行操作，不清空或导出整套防火墙。不要在 Xray 运行时另行重载原防火墙而不重放规则；如有重载，执行 `systemctl restart xray-deploy-firewall` 后重新验证端口。

Vultr Cloud Firewall 由云平台独立管理，本工具没有 Vultr API 授权，不修改云防火墙。如果已启用，请在控制台放行所选 TCP 端口。

安装器实际检查：Xray 配置校验、systemd 开机启动、服务 active、所选 TCP 端口由 Xray 主进程监听、本地防火墙处理。它不会把这些检查解释为公网可达或 REALITY 客户端连接成功。

部署后应从另一台设备导入链接，实际通过代理访问 HTTPS 网站，并在 VPS 重启后再次验证。这才能检查云防火墙、路由及 REALITY 端到端通信。

```bash
systemctl is-active xray
systemctl is-enabled xray
ss -lntp
```

## 当前开发测试记录

以下记录来自真实 Vultr Debian 12 测试机，使用 Xray 官方稳定版 v26.3.27。初始机器没有 Xray 配置，UFW 已启用且只开放 SSH。除特别注明外，均已实际执行。

| 验证项目 | 实际结果 |
| --- | --- |
| 首次安装、apt 依赖与官方核心安装 | 通过 |
| 最终默认交互参数：443、Apple、自动公网 IPv4、回车确认 | 通过 |
| 自定义端口 8443、自定义输入 `www.cloudflare.com` | 通过 |
| 端口越界、SSH 端口占用、错误域名、内网地址及确认输入纠错 | 通过，中文提示后可重新输入，SSH 保持正常 |
| 官方核心配置校验、systemd active、开机启用、Xray 主进程监听 | 通过 |
| 配置、元数据及管理脚本的 root 权限 | 通过 |
| UFW 为所选端口持久化放行且保留 SSH | 通过 |
| 分享链接、公钥推导、临时指定连接地址不写回配置 | 通过 |
| SSH 终端二维码生成 | 通过 |
| 重复安装与缺失二维码脚本修复 | 通过，配置和地址元数据的前后校验值完全一致 |
| 身份重置默认取消 | 通过，身份不变 |
| 确认后重置身份并重启服务 | 通过，仅 UUID、私钥和 Short ID 改变，公钥随私钥变化 |
| 无效私钥候选的失败保护 | 通过，在临时测试副本中注入无效候选，原配置及原运行进程不变 |
| 语法有效但实际无法启动的候选回滚 | 通过，在临时测试副本中令候选绑定被 SSH 占用的 22；启动失败后恢复原配置、原身份及正常服务，未停止 SSH |
| 手动修改配置但未重启时拒绝输出过时链接 | 通过 |
| 任意项目目录与跨工作目录调用 | 通过，在含空格的 `/opt/` 项目目录安装，从 `/tmp` 以绝对路径及 `/var/tmp` 以相对路径调用，配置与身份校验值未变 |
| 项目直接位于 `/root/` | 通过，复现并修复同文件复制问题，部署逻辑及身份不变 |
| 删除安装源目录后的管理工具与服务重启 | 通过，分享链接、终端二维码、身份重置默认取消及 Xray 重启均正常 |
| 实际重启 VPS 后 Xray 自动运行、443 监听、UFW 放行及身份保留 | 通过，以启动标识变化确认实际重启，配置与元数据校验值未变 |
| 重启后的公网独立客户端请求、二维码与私钥不进入 journal | 通过，当前及测试中旧私钥均未在服务日志中出现 |
| 本机独立官方 Xray 客户端通过公网链接代理 HTTPS | 443 + Apple、443 + Cloudflare、8443 + Cloudflare 均通过，代理出口与 VPS 一致 |
| 本机 Bash 语法及 ShellCheck | 通过，ShellCheck 仅忽略固定运行时 source 路径的 SC1091 |

首次实验的 Microsoft 目标通过了 TLS 1.3 基础检查，但同一环境中的 REALITY 握手失败；改用 Apple 和 Cloudflare 后真实代理请求成功。因此最终默认目标为 Apple，Microsoft 保留为可选项。基础 TLS 检查无法保证每个地域、DNS 返回的边缘节点和客户端组合都可用于 REALITY，应以实际客户端测试为准。

测试期间出现过 apt 安装失败，安装器立即停止，单独及随后重新运行均成功；最初失败的临时日志未保留，因此未确定原因。最终版本已补充 root-only 的失败诊断日志。

尚未实测：v2rayN 图形界面导入与扫码、原生 nftables/iptables 管理分支、Vultr 云防火墙 API 管理。分享链接已由独立 Xray 客户端使用；当前测试机实际走 UFW 分支。云防火墙没有授权，不执行 API 修改。

## 安装密码入口测试

新增入口通过本机隔离终端测试：正确密码进入原有 apt 入口；错误后重试成功；连续三次错误退出；终端 ECHO 关闭且密码不出现在输出中；失败时未执行锁操作、临时文件创建、apt 或安装命令；`--help` 无需密码。测试模拟 Debian 12 和 root 前置条件，并隔离 apt 等系统操作，不执行真实安装。

Bash 语法及 ShellCheck 通过。三个管理脚本逐字保持不变；除新增密码入口和欢迎信息的位置外，原安装逻辑与路径定位逐字保持不变。本次未重新进行 VPS 部署或代理连接测试，也未重置现有身份参数。

curl 管道入口另经本机隔离终端测试：本地跨目录调用、管道密码隐藏及终端读取、固定提交的三个管理脚本真实下载和 SHA-256 校验、下载失败、内容损坏、三次错误密码、无控制终端、退出后临时目录清理均通过。原管理脚本复制循环通过隔离目标目录验证，目的路径仍为 `/root/`，三个脚本内容一致且权限为 700。apt 和系统操作使用测试桩，不将这些入口测试等同于新 VPS 部署或端到端代理测试。

## 上传 GitHub 前

只上传上述五个源码与文档文件。不要上传 SSH 密码、SSH 密钥、服务器真实配置、`deploy.json`、实际 UUID、REALITY 密钥、测试输出或备份。测试 VPS 的工作配置可保留在 VPS 上。仓库示例不含实际凭据；发布前请再次确认暂存区文件清单。
