# Debian 12 Xray 一键部署工具

使用 Xray-core 官方稳定版、VLESS + REALITY、TCP、`xtls-rprx-vision` 和 systemd。仅支持 Debian 12 Bookworm，以 root 运行。一个入站支持 IPv4/IPv6；连接地址在生成链接或二维码时选择，不保存“默认 IP”。

## 安装

完整下载本仓库，保持以下五个文件在同一目录：

```text
install.sh
xray-link
xray-qrcode
xray-reconfigure
README.md
```

已安装 Git 的服务器可以执行：

```bash
git clone https://github.com/WattPrinter/xray-deploy.git
cd xray-deploy
bash install.sh
```

也可以通过 SCP 上传这五个文件，在任意目录以绝对路径运行安装器。路径可包含空格；项目直接位于 `/root/` 时也支持同文件安装。安装后可以删除源目录，服务与管理工具使用安装后的绝对路径。

### curl 一键安装

在 root SSH 交互终端运行，需已安装 `curl` 和 `ca-certificates`：

```bash
curl -fsSL https://raw.githubusercontent.com/WattPrinter/xray-deploy/main/install.sh | bash
```

安装器先完整解析代码块，再从 `/dev/tty` 读取交互输入，无交互终端时停止。密码正确后，将三个管理脚本下载至安全临时目录，验证非空、SHA-256 和 Bash 语法。管理脚本固定来自提交 `8c88aac953c3a3fedb7b9e40c0701fa56c8c65fe`，与当前仓库中的三个脚本完全一致；维护时须同时更新快照和安装器中的哈希。本地安装读取同目录脚本。

密码每个字符显示 `*`，支持 Backspace、Enter、Ctrl+C 和 Ctrl+D，最多尝试三次。源码只保留原有盐和哈希；密码请向维护者获取。这是轻量使用门槛，并非访问控制。`--help` 不需要密码。旧 `v1.0.0` 不包含当前密码与 IPv6 改动，本次功能使用 `main`。

耗时步骤显示中文单行 Spinner，结束后显示成功或失败；标准输出非终端时显示普通中文日志。安装结束打印链接、二维码，随后以退出码 0 返回 shell，不等待输入。失败或取消清理工作进程和临时目录。

安装器执行一次 `apt-get update`，安装 `curl`、`ca-certificates`、`openssl`、`jq`、`qrencode`、`iproute2`、`iptables`、`nftables`、`procps` 和 `unzip`。不安装面板、Docker、Python 或 Web 服务。apt 失败立即停止，原始诊断保存至 root-only 的 `/root/xray-deploy-apt.log`。

### 地址、监听与首次配置

安装时自动发现当前服务器地址，优先读取启用网卡的有效公网 IPv4 和全局 IPv6；没有本地公网 IPv4、但存在 IPv4 默认路由时，才通过 IPv4 HTTPS 服务查询出口地址。过滤内网、共享地址、环回及文档地址。NAT 出口地址不等于已建立入站映射，需管理员自行确认映射。只有一种地址族时正常安装；没有可用地址时给出中文错误。

安装过程只询问监听端口、REALITY 目标网站和安装确认，不询问连接 IP。默认端口 443、目标 `www.apple.com`；可选择 Microsoft、Cloudflare 或自定义域名。目标必须通过 TLS 1.3、证书和 SNI 检查，最终可用性仍以实际 REALITY 客户端连接为准。历史测试中 Microsoft 在该环境下通过 TLS 基础检查但 REALITY 握手失败，Apple 和 Cloudflare 成功。

存在全局 IPv6 时使用单个 `listen: "::"` 入站，同时接收 IPv6 和 IPv4；IPv4-only 主机沿用 `0.0.0.0`。不设置 `sockopt.v6only`，不修改系统全局 IPv6 内核参数。[官方监听说明](https://xtls.github.io/en/config/inbound.html)解释了通配地址及 `v6only` 的行为。TCP 使用 `network: "raw"`，REALITY 使用 `target`；分享链接使用 `type=tcp` 和 `pbk`。

确认后调用 [XTLS 官方安装器](https://github.com/XTLS/Xray-install) 安装最新稳定版，不下载地理数据，按原有方式生成 UUID、X25519 密钥和 16 位十六进制 Short ID。需服务器能访问 GitHub API 和 Release 下载地址。IPv6-only 网络如果无法访问这些 IPv4-only 下载端点，官方在线安装会失败；本工具没有额外下载代理。可由管理员下载并校验官方发行 ZIP，再使用官方安装器的 `--local` 方式准备核心。自动地址发现支持 IPv6-only，不代表上游下载服务支持 IPv6。

### 已有安装与升级

重复安装保留现有身份、端口、目标及核心版本。旧版单客户端 IPv4 通配监听在发现 IPv6 后只升级 `listen` 为 `::`，候选通过核心校验后应用；升级启动或健康检查失败会恢复原配置和服务。不会因启用 IPv6 重新生成身份。

只管理一个 VLESS + REALITY 入站、一个 Vision 客户端和一个 Short ID。无效配置、多 REALITY 入站、多客户端、多配置入口、指定地址绑定或明确的 `sockopt.v6only: true` 会停止自动升级并保留文件，需管理员处理。已有 `::` 不因暂时缺少 IPv6 地址而降级。

## 安装后的文件

```text
/root/xray-link
/root/xray-qrcode
/root/xray-reconfigure
/usr/local/etc/xray/config.json
/etc/systemd/system/xray.service.d/20-xray-deploy.conf
```

`config.json` 是唯一的身份和协议参数来源。公钥通过 OpenSSL 从当前私钥推导，不另行保存。三个管理工具不读取或创建 `deploy.json`；成功安装后移除只含旧 `server_ip` 字段的该文件，含其他字段的文件保留。

配置目录权限 700、配置 600、工具 700，归 root 所有。沿用官方 systemd 单元，通过补充配置以 root 读取配置。服务启动在 `/run/xray-deploy/config.sha256` 记录所加载配置校验值；手动改配置而未重启时，工具拒绝输出过时链接。安装和重置共用 `flock` 锁。重复安装会重启服务，产生短暂连接中断。

## 管理工具

### 分享链接

```bash
/root/xray-link
```

每次执行重新发现当前地址。两个地址族同时存在时，菜单输出到 stderr：

```text
请选择连接地址：

  1. IPv6：xxxx:xxxx::xxxx（默认）
  2. IPv4：xxx.xxx.xxx.xxx

请选择 [1]:
```

回车选 IPv6，输入 `2` 选 IPv4。只有一个地址时直接使用，不显示菜单。无可用地址时不输出 URI。非交互执行可以明确传入地址：

```bash
/root/xray-link 你的公网IPv4
/root/xray-link 你的全局IPv6
```

URI 单独输出到 stdout，提示输出到 stderr。IPv6 使用 `@[IPv6]:端口` 方括号形式；链接包含当前有效的 UUID、publicKey、Short ID、SNI、flow 和端口，以及 `type`、`security`、`fp`。查询参数与节点名称正确进行 URI 编码。显式地址只用于本次输出，不校验入站可达性，不修改服务配置和身份。

### 二维码

```bash
/root/xray-qrcode
/root/xray-qrcode 你的全局IPv6
```

二维码使用 `xray-link` 的公共地址发现和选择函数，一次选择后以显式地址调用连接工具，将同一 URI 交给 `qrencode`，不会再次弹出菜单。支持 IPv6 URI。UTF-8、ANSI 颜色和等宽字体的终端可显示二维码。

### 身份重置

```bash
/root/xray-reconfigure
```

默认取消，输入 `y` 后重新生成 UUID、REALITY X25519 密钥和 Short ID。其余配置保持原样，公钥从新私钥推导。候选校验成功后原子替换并重启；启动或监听检查失败则恢复原配置和服务。恢复失败时保留备份并报告路径。

成功后显示新参数、链接和二维码；有两个地址族时只选择一次 IP，链接与二维码共用该次选择。没有切换服务 IP 的菜单，不保存默认地址。成功输出包含私钥，请勿上传或写入公开日志。

三个工具均支持 `--help`。

## 防火墙与外部验证

只处理选定的 Xray TCP 端口，保留 SSH 和其他规则：

- 启用 UFW：在用户规则前部持久化放行 IPv4/IPv6；发现 IPv6 但 UFW 未启用 IPv6 管理时报告错误，不修改全局设置。
- 简单 iptables：标准 INPUT 链，已有启用的 `netfilter-persistent`；分别使用 iptables/ip6tables 放行，独立单元在恢复原规则后重放。
- 简单 nftables：一个 `inet` 输入基础链，已有启用且语法有效的 `/etc/nftables.conf`，一个 TCP 规则同时覆盖两个地址族。
- 没有生效的入站过滤规则：不额外开启防火墙。
- 混合或无法识别的规则：报告中文错误并停止。

需要重放时安装 `/usr/local/libexec/xray-deploy-firewall` 和 `xray-deploy-firewall.service`，不导出或清空原规则。另行重载防火墙后应重启该单元并验证端口。Vultr Cloud Firewall 独立管理，本工具不调用云 API；若启用，需在控制台放行对应地址族的 TCP 端口。

安装器检查配置、systemd active、开机启用、Xray 主进程监听及本地防火墙；这些检查不能替代外部 REALITY 请求。部署后从另一台设备导入链接，通过代理访问 HTTPS，并在重启后再验证。

```bash
systemctl is-active xray
systemctl is-enabled xray
ss -lntp
```

## 本轮 IPv6 测试（2026-10-11）

新 Vultr Debian 12 测试机使用官方 Xray-core v26.3.27、UFW 和单个 `listen: "::"` 入站。网卡 IPv4 属于 `100.64.0.0/10` 共享范围且没有 IPv4 默认路由，仅全局 IPv6 可用。该地址未被当作公网 IPv4。未修改全局 IPv6 内核参数。

| 项目 | 结果 |
| --- | --- |
| 自动识别地址 | 实测通过，识别全局 IPv6，排除共享 IPv4 |
| 单入站双地址族监听 | 实测通过，IPv6 公网和 SSH 转发到服务器 IPv4 回环的客户端均完成真实 REALITY + Vision HTTPS |
| IPv6 公网代理 HTTPS | 实测通过，返回的 IPv6 出口与 VPS 一致 |
| IPv4 公网代理 HTTPS | 无法测试，本机没有公网 IPv4；IPv4 回环转发通过不等同于公网 IPv4 验证 |
| IPv6 默认、手选 IPv4 | 同一实际工具通过双地址测试 fixture 验证；不是公网 IPv4 连接测试 |
| 单一地址族 | IPv6-only 实机自动选择通过；IPv4-only fixture 通过 |
| IPv6 URI 解析、身份字段 | 实测通过，解析生成的 URI 并构造真实客户端请求 |
| 二维码只选择一次 | 实际二维码工具加双地址 fixture 通过，共享选择且编码与链接一致 |
| 身份重置及新链接 | 实测通过，仅身份字段变化；新链接和二维码只选择一次地址 |
| 旧 IPv4-only 配置升级 | 实测通过，仅监听地址改变，身份和其他配置完全保持 |
| 双栈升级失败恢复 | 实测通过，注入一次重启失败后原配置逐字节恢复，服务正常 |
| 重复安装身份不变 | 实测通过，本地重复安装与 curl 重复安装均保留完整配置和身份 |
| curl 安装与正常退出 | 候选 curl 管道实测通过，GitHub 固定快照下载和哈希校验通过，退出码 0 |
| VPS 实际重启后 | 实测通过，启动标识变化、完整配置不变；开机服务、防火墙、IPv6 公网 HTTPS 及 IPv4 回环转发均复验通过 |
| Bash 语法、ShellCheck | 通过 |

该 IPv6-only 测试机无法直接访问 GitHub Release 的 IPv4 下载端点，官方在线核心安装失败；测试使用已校验官方 ZIP 和官方 `--local` 安装器准备核心后验证部署、升级及重复安装。未将其记为全新在线安装通过。此前 IPv4 VPS 的在线首次安装和公网 REALITY 请求已有历史验收，本轮未在另一台公网 IPv4 VPS 重跑。

本轮没有实测 v2rayN GUI 扫码及原生 iptables/nftables 管理分支；实际防火墙走 UFW 分支。

## 仓库内容

只提交上述五个源码和文档文件。不提交 VPS 凭据、真实 UUID、REALITY 私钥、服务器配置、测试输出或恢复备份。测试和私有参数留在本地或测试 VPS。
