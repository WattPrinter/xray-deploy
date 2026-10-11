#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
# 先解析整个代码块，避免管道模式切换终端输入后丢失尚未读取的脚本。
{
case ${1:-} in
    -h|--help)
        printf '用法：bash install.sh\nDebian 12 专用交互式安装器。支持完整仓库本地安装及 curl 管道安装，请以 root 执行。\n已有有效配置时保留身份、端口和目标网站；身份重置请使用 /root/xray-reconfigure。\n'
        exit 0 ;;
esac
(( $# == 0 )) || { printf '错误：安装器不接受参数。\n' >&2; exit 1; }
(( EUID == 0 )) || { printf '错误：请使用 root 执行安装器。\n' >&2; exit 1; }
source /etc/os-release
[[ $ID == debian && $VERSION_ID == 12 ]] || { printf '错误：仅支持 Debian 12 Bookworm。\n' >&2; exit 1; }
installer_source=${BASH_SOURCE[0]:-}
if [[ -z $installer_source ]]; then
    if ! { exec </dev/tty; } 2>/dev/null; then
        printf '错误：管道安装需要交互终端，请通过 SSH 终端运行，或完整下载仓库后本地安装。\n' >&2
        exit 1
    fi
fi
[[ -t 0 ]] || { printf '错误：安装密码需要交互终端，请在 SSH 终端中运行。\n' >&2; exit 1; }
work=''
active_pid=''
progress_active=0
listener_upgraded=0
# shellcheck disable=SC2329 # 通过 trap 或 run_step 间接调用。
cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [[ -n $active_pid ]]; then
        kill -TERM -- "-$active_pid" 2>/dev/null || true
        wait "$active_pid" 2>/dev/null || true
    fi
    if (( progress_active )); then printf '\r\033[2K'; fi
    if (( listener_upgraded )); then
        if install -m 600 "$work/previous.json" "$XRAY_CONFIG" && systemctl restart xray && xray_health; then
            printf '错误：双栈升级失败，已恢复原配置和服务。\n' >&2
        else
            printf '错误：恢复服务失败，原配置备份保存在 %s/previous.json。\n' "$work" >&2
            exit 1
        fi
    fi
    [[ -z $work ]] || rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT
# shellcheck disable=SC2329 # 通过信号 trap 间接调用。
cancel_install() {
    if (( progress_active )); then printf '\r\033[2K'; progress_active=0; fi
    printf '\n安装已取消。\n' >&2
    exit "$1"
}
trap 'cancel_install 130' INT
trap 'cancel_install 143' TERM
trap 'cancel_install 129' HUP
run_step() {
    local title=$1 log=$2 status=0 frame=0 line
    local frames=('|' '/' '-' $'\\')
    shift 2
    if [[ -t 1 ]]; then
        progress_active=1
    else
        printf '正在执行：%s……\n' "$title"
    fi
    # 独立进程组只包含本步骤的工作进程；取消时不触及 systemd 管理的 Xray。
    set -m
    ( set +m; trap - EXIT ERR INT TERM HUP; "$@" ) </dev/null >"$log" 2>&1 &
    active_pid=$!
    set +m
    while kill -0 "$active_pid" 2>/dev/null; do
        if (( progress_active )); then
            printf '\r\033[2K%s %s' "${frames[frame % 4]}" "$title"
            frame=$((frame + 1))
        fi
        sleep 0.15
    done
    wait "$active_pid" || status=$?
    active_pid=''
    if (( progress_active )); then printf '\r\033[2K'; fi
    progress_active=0
    if (( status == 0 )); then
        printf '✓ %s：已完成\n' "$title"
    else
        printf '✗ %s：失败（退出码 %s）\n' "$title" "$status" >&2
        if [[ $log == "$work/apt.log" ]]; then
            install -m 600 "$log" /root/xray-deploy-apt.log
            printf '错误：apt 操作失败，详细日志位于 /root/xray-deploy-apt.log。\n' >&2
        fi
        while IFS= read -r line; do
            [[ $line != 错误：* ]] || printf '%s\n' "$line" >&2
        done < "$log"
    fi
    return "$status"
}
printf '====================================\n       Xray 一键安装工具\n       Debian 12 专用\n====================================\n\n'
verify_password() {
    local salt='b46a145248b27761ecd3b16d81251989' expected='ec4e2b4307615e5d8f9a1a26f6dcae7ffeacb30526dea49e1029bc63e8a1b4dd' password digest attempt character
    for attempt in 1 2 3; do
        password=''
        printf '请输入安装密码：' >&2
        while true; do
            if ! IFS= read -rsn1 character; then
                unset password
                printf '\n错误：输入结束，已停止。\n' >&2
                return 1
            fi
            case $character in
                '') printf '\n' >&2; break ;;
                $'\177'|$'\b')
                    if [[ -n $password ]]; then
                        password=${password%?}
                        printf '\b \b' >&2
                    fi ;;
                $'\004')
                    unset password
                    printf '\n错误：输入结束，已停止。\n' >&2
                    return 1 ;;
                *) password+=$character; printf '*' >&2 ;;
            esac
        done
        digest=$(printf '%s%s' "$salt" "$password" | sha256sum)
        unset password
        if [[ ${digest%% *} == "$expected" ]]; then
            printf '密码验证成功。\n\n'
            return 0
        fi
        printf '安装密码错误，剩余尝试次数：%s\n' "$((3 - attempt))" >&2
    done
    printf '错误：连续三次密码验证失败，已停止。\n' >&2
    return 1
}
verify_password || exit 1
work=$(mktemp -d) || { printf '错误：创建安全临时目录失败。\n' >&2; exit 1; }
trap 'printf "错误：操作失败（第 %s 行），已停止。\n" "$LINENO" >&2' ERR
if [[ -n $installer_source ]]; then
    script_dir=$(cd -- "$(dirname -- "$installer_source")" && pwd)
else
    command -v curl >/dev/null || { printf '错误：管道安装需要 curl，请先安装 curl 和 ca-certificates。\n' >&2; exit 1; }
    # 此快照的三个管理脚本与本版本所附文件完全相同，按固定提交及校验值下载。
    helper_revision=8c88aac953c3a3fedb7b9e40c0701fa56c8c65fe
    script_dir=$work
    # shellcheck disable=SC2329 # 通过 trap 或 run_step 间接调用。
    download_helpers() {
        for script in xray-link xray-qrcode xray-reconfigure; do
            case $script in
                xray-link) expected=70d1054655a5ae080aaec42cb94ed2d4faf76e6a8070f6f00e7588cf76abfd80 ;;
                xray-qrcode) expected=fffb708bce856032db3fb90958a950121f5918934d63d6fb19e7fa8ba65730fb ;;
                xray-reconfigure) expected=5293998b4a7c1a7275b623550d5a72ae64c55c130088a19d164e0a416f9edff9 ;;
            esac
            curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
                "https://raw.githubusercontent.com/WattPrinter/xray-deploy/$helper_revision/$script" \
                -o "$script_dir/$script" >"$work/download.log" 2>&1 || {
                    local status=$?
                    printf '错误：下载管理脚本 %s 失败，已停止安装。\n' "$script" >&2; return "$status"
                }
            if [[ ! -s $script_dir/$script ]] ||
                ! printf '%s  %s\n' "$expected" "$script_dir/$script" | sha256sum -c - >"$work/download.log" 2>&1 ||
                ! bash -n "$script_dir/$script" >"$work/download.log" 2>&1; then
                printf '错误：管理脚本 %s 的完整性或语法验证失败，已停止安装。\n' "$script" >&2
                return 1
            fi
        done
    }
    run_step '下载并验证三个管理脚本' "$work/helpers.log" download_helpers
fi
for script in xray-link xray-qrcode xray-reconfigure; do
    [[ -s $script_dir/$script ]] || { printf '错误：仓库缺少 %s，请完整下载仓库。\n' "$script" >&2; exit 1; }
done
source "$script_dir/xray-link"
xray_lock
printf '[1/5] 安装必要依赖\n'
# 第三方命令输出保存在 root-only 临时文件；界面始终使用中文。
export DEBIAN_FRONTEND=noninteractive
run_step '更新软件索引' "$work/apt.log" apt-get update
run_step '安装必要依赖' "$work/apt.log" \
    apt-get install -y --no-install-recommends curl ca-certificates openssl jq qrencode iproute2 iptables nftables procps unzip

ask_port() {
    local value
    while true; do
        read -r -p '请输入 Xray 监听端口 [443]: ' value || return 1
        value=${value:-443}
        if [[ ! $value =~ ^[0-9]{1,5}$ ]] || (( 10#$value < 1 || 10#$value > 65535 )); then
            printf '输入错误：端口必须是 1 至 65535 的整数。\n'; continue
        fi
        port=$((10#$value))
        if xray_port_free "$port"; then return 0; fi
        printf '端口 %s 已被其他进程占用，请选择其他端口；不会停止占用进程。\n' "$port"
    done
}
ask_target() {
    local choice value
    while true; do
        printf '\n请选择 REALITY 目标网站：\n\n  1. www.apple.com\n  2. www.microsoft.com\n  3. www.cloudflare.com\n  4. 自定义网站\n\n'
        read -r -p '请选择 [1]: ' choice || return 1
        case ${choice:-1} in
            1) target=www.apple.com ;;
            2) target=www.microsoft.com ;;
            3) target=www.cloudflare.com ;;
            4) read -r -p '请输入目标域名 [www.apple.com]: ' value || return 1; target=${value:-www.apple.com} ;;
            *) printf '输入错误：请选择 1 至 4。\n'; continue ;;
        esac
        if [[ ${#target} -gt 253 || ! $target =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]; then
            printf '输入错误：请只输入有效域名，不要包含协议、路径或端口。\n'; continue
        fi
        target=${target,,}
        printf '正在检查 %s 的 TLS 1.3、证书和 SNI 连通性……\n' "$target"
        if timeout 15 openssl s_client -connect "$target:443" -servername "$target" -tls1_3 \
            -verify_hostname "$target" -verify_return_error -CApath /etc/ssl/certs \
            </dev/null >"$work/tls.log" 2>&1 && grep -q 'Verify return code: 0 (ok)' "$work/tls.log"; then
            printf '目标网站 TLS 基本检查通过。\n'; return 0
        fi
        printf '目标网站 TLS 检查失败，请重新选择可从本机访问的域名。\n'
    done
}

# 只对已知、可识别的本地入站防火墙添加一个端口规则。
# shellcheck disable=SC2329 # 通过 trap 或 run_step 间接调用。
firewall() {
    local rules chains family table chain backend='' command4='' command6=''
    nft -j list ruleset >"$work/nft.json" 2>/dev/null || { xray_error '无法读取 nftables 规则，不能确认端口可放行。'; return 1; }
    iptables-save >"$work/iptables" 2>/dev/null || { xray_error '无法读取 IPv4 防火墙规则。'; return 1; }
    ip6tables-save >"$work/ip6tables" 2>/dev/null || { xray_error '无法读取 IPv6 防火墙规则。'; return 1; }
    chains=$(jq -c '[.nftables[] | .chain? // empty | select(.hook == "input" or .hook == "prerouting")]' "$work/nft.json")
    if command -v ufw >/dev/null && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
        # 额外的原生入站链可能在 UFW 之后再次丢弃数据包，不能声称已放行。
        if jq -e '.[] | select(.table != "filter" or (.name != "INPUT" and .name != "PREROUTING"))' <<< "$chains" >/dev/null; then
            xray_error 'UFW 与其他入站防火墙链并存，无法可靠确认放行方式，请手动处理所选端口。'; return 1
        fi
        if [[ -n $XRAY_IPV6 ]] && ! grep -Eq '^IPV6=yes$' /etc/default/ufw; then
            xray_error 'UFW 未启用 IPv6 管理，请先配置 IPv6 防火墙；未声称双栈端口已放行。'; return 1
        fi
        LC_ALL=C ufw insert 1 allow "$port/tcp" >"$work/firewall.log" 2>&1 || { xray_error 'UFW 添加 TCP 放行规则失败。'; return 1; }
        printf 'UFW：已在用户规则前部持久化放行 TCP %s（保留原规则及 SSH）。\n' "$port"
        return 0
    fi
    # nft 后端为空时仍要检查 legacy iptables，避免漏掉另一个内核规则集。
    for rules in iptables ip6tables; do
        if grep -Eq '^:INPUT (DROP|REJECT)|^-A (INPUT|PREROUTING)' "$work/$rules"; then backend=iptables; fi
    done
    if [[ $backend == iptables ]]; then
        # 标准 INPUT 链、无跳转/额外入站表；不尝试推断自定义链。
        if grep -qE '^-A PREROUTING' "$work/iptables" "$work/ip6tables" ||
            grep -E '^-A INPUT' "$work/iptables" "$work/ip6tables" |
            grep -E ' -[jg] ' | grep -Ev ' -j (ACCEPT|DROP|REJECT|LOG)( |$)' >/dev/null; then
            xray_error '存在自定义 iptables 入站跳转，无法安全自动放行，请手动处理所选端口。'; return 1
        fi
        if [[ $(jq 'length' <<< "$chains") -gt 2 ]] ||
            jq -e '.[] | select(.table != "filter" or .name != "INPUT")' <<< "$chains" >/dev/null; then
            xray_error '存在额外 nftables 入站链，无法安全自动放行。'; return 1
        fi
        systemctl is-enabled --quiet netfilter-persistent ||
            { xray_error 'iptables 规则没有可识别的持久化服务，请先配置 netfilter-persistent；本工具不会保存或覆盖整套规则。'; return 1; }
        command4="iptables -C INPUT -p tcp --dport $port -m comment --comment xray-deploy -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport $port -m comment --comment xray-deploy -j ACCEPT"
        command6="ip6tables -C INPUT -p tcp --dport $port -m comment --comment xray-deploy -j ACCEPT 2>/dev/null || ip6tables -I INPUT 1 -p tcp --dport $port -m comment --comment xray-deploy -j ACCEPT"
    elif [[ $(jq 'length' <<< "$chains") == 0 ]]; then
        printf '未发现生效的本地入站过滤规则，不额外启用防火墙。\n'; return 0
    else
        [[ $(jq 'length' <<< "$chains") == 1 ]] || { xray_error '存在多条入站基础链，无法可靠自动放行，请手动处理所选端口。'; return 1; }
        family=$(jq -r '.[0].family' <<< "$chains")
        table=$(jq -r '.[0].table' <<< "$chains")
        chain=$(jq -r '.[0].name' <<< "$chains")
        [[ $family == inet && $table =~ ^[a-zA-Z0-9_]+$ && $chain =~ ^[a-zA-Z0-9_]+$ &&
           $(jq -r '.[0].hook' <<< "$chains") == input ]] ||
            { xray_error '只自动处理单个 inet 入站基础链，请手动处理当前防火墙。'; return 1; }
        if ! systemctl is-enabled --quiet nftables || ! nft -c -f /etc/nftables.conf >/dev/null 2>&1; then
            xray_error 'nftables 缺少有效的开机持久化配置，不能只添加临时规则。'; return 1
        fi
        backend=nftables
        command4="nft -a list chain inet $table $chain | grep -q 'tcp dport $port accept comment \"xray-deploy\"' || nft insert rule inet $table $chain tcp dport $port accept comment '\"xray-deploy\"'"
    fi
    # 独立启动单元只重放本工具的端口规则；不导出、不清空原有防火墙。
    install -d -m 755 /usr/local/libexec
    {
        printf '#!/bin/bash\nset -eu\nPATH=/usr/sbin:/usr/bin:/sbin:/bin\n'
        printf '%s\n' "$command4"
        [[ -z $command6 ]] || printf '%s\n' "$command6"
    } > /usr/local/libexec/xray-deploy-firewall
    chmod 700 /usr/local/libexec/xray-deploy-firewall
    cat > /etc/systemd/system/xray-deploy-firewall.service <<'UNIT'
[Unit]
Description=Xray TCP 端口放行
After=nftables.service netfilter-persistent.service
Before=xray.service
[Service]
Type=oneshot
ExecStart=/usr/local/libexec/xray-deploy-firewall
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable xray-deploy-firewall >/dev/null 2>&1
    systemctl restart xray-deploy-firewall >/dev/null 2>&1 || { xray_error '添加端口规则失败，请检查原防火墙配置。'; return 1; }
    printf '%s：已为 TCP %s 添加独立的开机放行规则，未覆盖原有规则。\n' "$backend" "$port"
}

xray_discover_addresses
[[ -n $XRAY_IPV4 || -n $XRAY_IPV6 ]] || { xray_error '未找到可用的公网 IPv4 或全局 IPv6。'; exit 1; }
listen=0.0.0.0
[[ -z $XRAY_IPV6 ]] || listen=::
printf '当前可用地址：IPv4 %s；IPv6 %s\n' "${XRAY_IPV4:-无}" "${XRAY_IPV6:-无}"

printf '\n[2/5] 基本配置\n'
existing=0
if [[ -s $XRAY_CONFIG ]]; then
    if [[ ! -x $XRAY_BIN ]] || ! xray_validate "$XRAY_CONFIG"; then
        xray_error '发现现有配置，但核心缺失或配置无效；已保留原文件，请手动检查。'; exit 1
    fi
    xray_read
    existing=1
    port=$XRAY_PORT
    # 已有服务必须确实使用当前文件，否则停止，避免重写其他部署方式。
    start=$(systemctl show xray -p ExecStart --value)
    [[ $start == *"$XRAY_CONFIG"* && $start != *"-confdir"* ]] || { xray_error '现有服务使用其他配置或多文件配置，已停止且未覆盖。'; exit 1; }
    if ! xray_port_free "$port"; then
        pid=$(systemctl show xray -p MainPID --value)
        [[ $pid != 0 && $(ss -H -ltnp "sport = :$port") == *"pid=$pid,"* ]] ||
            { xray_error "端口 $port 被其他进程占用，已停止。"; exit 1; }
    fi
    old_listen=$(jq -r --argjson i "$XRAY_INDEX" '.inbounds[$i].listen // "0.0.0.0"' "$XRAY_CONFIG")
    if [[ $old_listen != 0.0.0.0 && $old_listen != :: ]] ||
        jq -e --argjson i "$XRAY_INDEX" '.inbounds[$i].streamSettings.sockopt.v6only == true' "$XRAY_CONFIG" >/dev/null; then
        xray_error '现有配置限制了监听地址或仅 IPv6，无法安全自动升级，已保留原配置。'; exit 1
    fi
    printf '检测到有效安装，保留原 UUID、密钥、Short ID、端口及目标网站。\n'

else
    ask_port
    ask_target
    printf '\n------------------------------------\n配置确认\n\n监听端口：%s\n目标网站：%s\n\n' "$port" "$target"
    while true; do
        read -r -p '确认开始安装？[Y/n]: ' answer || exit 1
        case $answer in
            ''|y|Y|yes|YES) break ;;
            n|N|no|NO) printf '已取消安装。\n'; exit 0 ;;
            *) printf '输入错误：请输入 y 或 n，直接回车表示确认。\n' ;;
        esac
    done
fi

printf '\n[3/5] 检查所选端口的本地防火墙\n'
run_step '本地防火墙端口放行' "$work/firewall-step.log" firewall
cat "$work/firewall-step.log"
printf 'Vultr Cloud Firewall 独立于本地防火墙；如已启用，请在控制台放行 TCP %s。\n' "$port"

printf '\n[4/5] 安装官方稳定版与管理工具\n'
if (( ! existing )); then
    run_step '下载 Xray 官方安装器' "$work/download.log" \
        curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
        https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$work/install-release.sh"
    run_step '安装 Xray-core 官方稳定版' "$work/core.log" \
        bash "$work/install-release.sh" install -u root --without-geodata
    if [[ ! -x $XRAY_BIN ]] || ! "$XRAY_BIN" version >/dev/null 2>&1; then
        xray_error '安装后未找到可用的 Xray 核心。'; exit 1
    fi
    install -d -m 700 "$XRAY_DIR"
    # shellcheck disable=SC2329 # 通过 trap 或 run_step 间接调用。
    generate_config() {
        xray_identity
        jq -n --arg listen "$listen" --argjson port "$port" --arg target "$target" --arg uuid "$XRAY_UUID" --arg private "$XRAY_PRIVATE" --arg sid "$XRAY_SID" '{
            log: {loglevel:"warning"},
            inbounds: [{listen:$listen,port:$port,protocol:"vless",settings:{
                clients:[{id:$uuid,flow:"xtls-rprx-vision"}],decryption:"none"},
                streamSettings:{network:"raw",security:"reality",realitySettings:{
                    show:false,target:($target+":443"),xver:0,serverNames:[$target],privateKey:$private,shortIds:[$sid]}}}],
            outbounds:[{protocol:"freedom",tag:"direct"}]}' > "$work/candidate.json"
        xray_validate "$work/candidate.json" || { xray_error '首次生成的候选配置校验失败，未写入正式配置。'; return 1; }
    }
    run_step '生成并校验 REALITY 配置' "$work/config.log" generate_config
    install -m 600 "$work/candidate.json" "$XRAY_CONFIG"
else
    if [[ $old_listen != "$listen" && $listen == :: ]]; then
        jq --argjson i "$XRAY_INDEX" '.inbounds[$i].listen = "::"' "$XRAY_CONFIG" > "$work/candidate.json"
        xray_validate "$work/candidate.json" || { xray_error '双栈候选配置无效，原配置未改变。'; exit 1; }
        cp -p "$XRAY_CONFIG" "$work/previous.json"
        install -m 600 "$work/candidate.json" "$XRAY_CONFIG"
        listener_upgraded=1
        printf '仅升级通配监听为 ::，身份参数保持不变。\n'
    fi
    printf '已保留现有 Xray 版本和身份；重复安装不自动升级核心。\n'
fi
for script in xray-link xray-qrcode xray-reconfigure; do
    if [[ $script_dir/$script -ef /root/$script ]]; then
        chmod 700 "/root/$script"
    else
        install -m 700 "$script_dir/$script" "/root/$script"
    fi
done
chown root:root "$XRAY_DIR" "$XRAY_CONFIG"
chmod 700 "$XRAY_DIR"
chmod 600 "$XRAY_CONFIG"
# root 读取 root-only 配置；沿用官方 unit，固定单一配置入口及启动指纹。
install -d -m 755 /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/20-xray-deploy.conf <<'UNIT'
[Service]
User=root
Group=root
ExecStart=
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
RuntimeDirectory=xray-deploy
RuntimeDirectoryMode=0700
ExecStartPost=
ExecStartPost=/bin/sh -c 'umask 077; sha256sum /usr/local/etc/xray/config.json > /run/xray-deploy/config.sha256'
UNIT

printf '\n[5/5] 验证配置、服务与监听端口\n'
xray_read
# shellcheck disable=SC2329 # 通过 trap 或 run_step 间接调用。
start_and_check() {
    xray_validate "$XRAY_CONFIG" || { xray_error '正式配置校验失败。'; return 1; }
    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1 || { xray_error 'Xray 启动失败，请检查 systemd 服务状态。'; return 1; }
    xray_health || { xray_error 'Xray 服务或指定端口监听检查失败。'; return 1; }
    xray_effective
}
run_step 'systemd 启动及配置、服务与监听检查' "$work/service.log" start_and_check
listener_upgraded=0
# 旧地址元数据只含默认 IP；新工具不再读取或写入它。
if [[ -f $XRAY_DIR/deploy.json ]] && jq -e 'keys == ["server_ip"]' "$XRAY_DIR/deploy.json" >/dev/null 2>&1; then
    rm -f "$XRAY_DIR/deploy.json"
fi
printf '\n====================================\n         Xray 部署成功\n====================================\n\n'
printf '✓ Xray 服务运行正常\n✓ systemd 开机启动已启用\n✓ TCP %s 正在监听\n✓ 本地防火墙检查完成\n' "$XRAY_PORT"
printf '本工具完成了本地检查；公网可达性与 REALITY 客户端连接仍需从外部验证。\n\nVLESS 连接：\n'
address=${XRAY_IPV6:-$XRAY_IPV4}
/root/xray-link "$address"
printf '\n客户端二维码：\n'
/root/xray-qrcode "$address"
printf '\n部署完成，可以关闭终端。\n'
# 管道模式已将标准输入切换到终端，必须显式退出，避免 Bash 继续读取命令。
exit 0
}
