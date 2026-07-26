#!/usr/bin/env bash

# VPS health and intermittent network diagnostic tool.
# Read-only: it does not change services, firewall rules, routes, or packages.

set -uo pipefail

VERSION="1.1.0"
PROJECT_URL="https://github.com/sanrokamlan-prog/vps-health-check"
HOURS=24
INTERVAL=5
WATCH_DURATION=""
RUN_MTR=0
LANGUAGE="zh"
NO_COLOR=0
OUTPUT_FILE=""
PROBE_LOG=""
MONITOR_LOG=""
MONITOR_LOG_AUTO=0
TARGETS=("1.1.1.1" "8.8.8.8")
TARGETS_OVERRIDDEN=0
SERVICES=()
PORTS=()
TCP_TARGETS=()

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
INFO_COUNT=0
TMP_DIR=""
BUNDLE_DIR=""
BUNDLE_ARCHIVE=""

# Diagnostic signals used to build recommendations and support material.
CPU_STEAL_PCT=0
CPU_IOWAIT_PCT=0
CGROUP_THROTTLE_PCT=0
CGROUP_CPU_LIMIT=""
CGROUP_MEMORY_PCT=0
PSI_CPU_AVG10=""
PSI_MEMORY_FULL_AVG10=""
PSI_IO_FULL_AVG10=""
FLAG_HIGH_LOAD=0
FLAG_HIGH_MEMORY=0
FLAG_HIGH_SWAP=0
FLAG_DISK=0
FLAG_INODE=0
FLAG_FAILED_UNITS=0
FLAG_SERVICE_DOWN=0
FLAG_OOM=0
FLAG_KERNEL_LOCKUP=0
FLAG_STORAGE_ERROR=0
FLAG_NIC_EVENT=0
FLAG_NIC_COUNTER=0
FLAG_CONNTRACK=0
FLAG_CPU_PRESSURE=0
FLAG_MEMORY_PRESSURE=0
FLAG_IO_PRESSURE=0
FLAG_CGROUP_THROTTLE=0
FLAG_DSTATE=0
FLAG_ZOMBIE=0
FLAG_FILE_HANDLES=0
FLAG_PID_LIMIT=0
FLAG_READONLY_ROOT=0
FLAG_RECENT_REBOOT=0
FLAG_KERNEL_CRASH=0
FLAG_TIMEKEEPING=0
FLAG_NETWORK_STACK=0
FLAG_TCP_RETRANS=0
FLAG_SYN_BACKLOG=0
FLAG_PORT_CHECK=0
FLAG_TCP_TARGET=0
DEFAULT_IFACE=""
NET_RX_ERRORS_START=0
NET_TX_ERRORS_START=0
NET_RX_DROPPED_START=0
NET_TX_DROPPED_START=0
NET_RX_ERROR_DELTA=0
NET_TX_ERROR_DELTA=0
NET_RX_DROP_DELTA=0
NET_TX_DROP_DELTA=0
TCP_RETRANS_PCT=0
PING_TESTS=0
PING_FAILURES=0
PING_WARNINGS=0
DNS_OK=-1
HTTPS_OK=-1
PROBE_LOST_COUNT=0
MONITOR_ANOMALY_COUNT=0
FLAG_PROCESS_MONITOR=0
WATCH_FAILURES=0
WATCH_TRANSITIONS=0
WATCH_STOP=0
RECOMMENDATIONS_ZH=()
RECOMMENDATIONS_EN=()
TICKET_FACTS=()

usage() {
    cat <<'EOF'
VPS 健康与网络诊断脚本

用法：
  sudo bash vps-health-check.sh [选项]

选项：
  --hours N          检查最近 N 小时的系统日志（默认：24）
  --target HOST      网络探测目标，可重复使用（默认：1.1.1.1、8.8.8.8）
  --service NAME     检查指定 systemd 服务，可重复使用
  --port N           检查本机 TCP 端口是否监听，可重复使用
  --tcp HOST:PORT    探测远端 TCP 端口，可重复使用（IPv4/主机名）
  --probe-log FILE   导入外部探针的 lost/back 记录并放入证据包
  --monitor-log FILE 导入 vps-health-monitor.sh 的后台异常日志
  --mtr              如果系统已安装 mtr，附加路由质量报告
  --watch [SECONDS]  持续探测网络；不填秒数则一直运行，按 Ctrl+C 停止
  --interval N       持续探测间隔秒数（默认：5）
  --output FILE      指定报告文件（默认：/tmp/vps-health-*.log）
  --lang zh|en       输出语言（默认：zh）
  --no-color         禁用终端颜色
  -h, --help         显示帮助

示例：
  sudo bash vps-health-check.sh
  sudo bash vps-health-check.sh --service xray --service nginx --mtr
  sudo bash vps-health-check.sh --port 22 --port 443 --tcp example.com:443
  sudo bash vps-health-check.sh --probe-log probe.log --mtr
  sudo bash vps-health-check.sh --monitor-log /var/log/vps-health-monitor/monitor.log
  sudo bash vps-health-check.sh --watch 3600 --interval 5
EOF
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

while (($# > 0)); do
    case "$1" in
        --hours)
            [[ $# -ge 2 ]] || { echo "--hours requires a value" >&2; exit 2; }
            HOURS="$2"
            shift 2
            ;;
        --target)
            [[ $# -ge 2 ]] || { echo "--target requires a value" >&2; exit 2; }
            if ((TARGETS_OVERRIDDEN == 0)); then
                TARGETS=()
                TARGETS_OVERRIDDEN=1
            fi
            TARGETS+=("$2")
            shift 2
            ;;
        --service)
            [[ $# -ge 2 ]] || { echo "--service requires a value" >&2; exit 2; }
            SERVICES+=("$2")
            shift 2
            ;;
        --port)
            [[ $# -ge 2 ]] || { echo "--port requires a value" >&2; exit 2; }
            PORTS+=("$2")
            shift 2
            ;;
        --tcp)
            [[ $# -ge 2 ]] || { echo "--tcp requires HOST:PORT" >&2; exit 2; }
            TCP_TARGETS+=("$2")
            shift 2
            ;;
        --probe-log)
            [[ $# -ge 2 ]] || { echo "--probe-log requires a value" >&2; exit 2; }
            PROBE_LOG="$2"
            shift 2
            ;;
        --monitor-log)
            [[ $# -ge 2 ]] || { echo "--monitor-log requires a value" >&2; exit 2; }
            MONITOR_LOG="$2"
            shift 2
            ;;
        --mtr)
            RUN_MTR=1
            shift
            ;;
        --watch)
            WATCH_DURATION=0
            if [[ $# -ge 2 ]] && is_uint "$2"; then
                WATCH_DURATION="$2"
                shift 2
            else
                shift
            fi
            ;;
        --interval)
            [[ $# -ge 2 ]] || { echo "--interval requires a value" >&2; exit 2; }
            INTERVAL="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { echo "--output requires a value" >&2; exit 2; }
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --lang)
            [[ $# -ge 2 ]] || { echo "--lang requires zh or en" >&2; exit 2; }
            LANGUAGE="$2"
            shift 2
            ;;
        --no-color)
            NO_COLOR=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! is_uint "$HOURS" || ((HOURS < 1)); then
    echo "--hours must be a positive integer" >&2
    exit 2
fi
if ! is_uint "$INTERVAL" || ((INTERVAL < 1)); then
    echo "--interval must be a positive integer" >&2
    exit 2
fi
if [[ "$LANGUAGE" != "zh" && "$LANGUAGE" != "en" ]]; then
    echo "--lang must be zh or en" >&2
    exit 2
fi
for port in "${PORTS[@]}"; do
    if ! is_uint "$port" || ((port < 1 || port > 65535)); then
        echo "--port must be between 1 and 65535: $port" >&2
        exit 2
    fi
done
for tcp_target in "${TCP_TARGETS[@]}"; do
    tcp_host="${tcp_target%:*}"
    tcp_port="${tcp_target##*:}"
    if [[ "$tcp_target" != *:* || ! "$tcp_host" =~ ^[A-Za-z0-9._-]+$ ]] || ! is_uint "$tcp_port" || ((tcp_port < 1 || tcp_port > 65535)); then
        echo "--tcp must use HOST:PORT with a valid IPv4 address or hostname: $tcp_target" >&2
        exit 2
    fi
done
if [[ -n "$PROBE_LOG" && ! -r "$PROBE_LOG" ]]; then
    echo "Cannot read probe log: $PROBE_LOG" >&2
    exit 2
fi
if [[ -z "$MONITOR_LOG" ]]; then
    if [[ -r /var/log/vps-health-monitor/monitor.log ]]; then
        MONITOR_LOG="/var/log/vps-health-monitor/monitor.log"
        MONITOR_LOG_AUTO=1
    elif [[ -r "${HOME:-/tmp}/.local/state/vps-health-monitor/monitor.log" ]]; then
        MONITOR_LOG="${HOME:-/tmp}/.local/state/vps-health-monitor/monitor.log"
        MONITOR_LOG_AUTO=1
    fi
fi
if [[ -n "$MONITOR_LOG" && ! -r "$MONITOR_LOG" ]]; then
    echo "Cannot read monitor log: $MONITOR_LOG" >&2
    exit 2
fi

tr_text() {
    if [[ "$LANGUAGE" == "zh" ]]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

host_name="$(hostname 2>/dev/null || printf 'unknown')"
safe_host="${host_name//[^A-Za-z0-9._-]/_}"
timestamp="$(date +%Y%m%d-%H%M%S)"
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="/tmp/vps-health-${safe_host}-${timestamp}.log"
fi
BUNDLE_DIR="${OUTPUT_FILE%.*}-evidence"
BUNDLE_ARCHIVE="${BUNDLE_DIR}.tar.gz"

output_dir="$(dirname -- "$OUTPUT_FILE")"
if [[ ! -d "$output_dir" ]] || [[ ! -w "$output_dir" ]]; then
    echo "Cannot write report directory: $output_dir" >&2
    exit 2
fi
: >"$OUTPUT_FILE" || { echo "Cannot write report: $OUTPUT_FILE" >&2; exit 2; }
if [[ -e "$BUNDLE_DIR" ]]; then
    echo "Evidence directory already exists: $BUNDLE_DIR" >&2
    exit 2
fi
mkdir -p -- "$BUNDLE_DIR/raw" || { echo "Cannot create evidence directory: $BUNDLE_DIR" >&2; exit 2; }

TMP_DIR="$(mktemp -d 2>/dev/null || true)"
if [[ -z "$TMP_DIR" || ! -d "$TMP_DIR" ]]; then
    echo "Cannot create temporary directory" >&2
    exit 2
fi

# Called indirectly by the EXIT trap.
# shellcheck disable=SC2317
cleanup() {
    rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

if [[ -t 1 && "$NO_COLOR" -eq 0 ]]; then
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_BLUE=$'\033[36m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_BLUE=""
    C_BOLD=""
    C_RESET=""
fi

plain_log() {
    printf '%s\n' "$*" >>"$OUTPUT_FILE"
}

section() {
    local title="$1"
    printf '\n%s== %s ==%s\n' "$C_BOLD" "$title" "$C_RESET"
    plain_log ""
    plain_log "== $title =="
}

status_line() {
    local level="$1"
    shift
    local message="$*" color=""
    case "$level" in
        PASS) color="$C_GREEN"; ((PASS_COUNT += 1)) ;;
        WARN) color="$C_YELLOW"; ((WARN_COUNT += 1)) ;;
        FAIL) color="$C_RED"; ((FAIL_COUNT += 1)) ;;
        INFO) color="$C_BLUE"; ((INFO_COUNT += 1)) ;;
    esac
    printf '%s[%s]%s %s\n' "$color" "$level" "$C_RESET" "$message"
    plain_log "[$level] $message"
}

append_block() {
    local label="$1"
    local content="$2"
    [[ -n "$content" ]] || return 0
    printf '%s\n%s\n' "$label" "$content"
    plain_log "$label"
    plain_log "$content"
}

percent_status() {
    local value="$1" warn_at="$2" fail_at="$3" label="$4"
    if ((value >= fail_at)); then
        status_line FAIL "$label: ${value}%"
    elif ((value >= warn_at)); then
        status_line WARN "$label: ${value}%"
    else
        status_line PASS "$label: ${value}%"
    fi
}

add_recommendation() {
    RECOMMENDATIONS_ZH+=("$1")
    RECOMMENDATIONS_EN+=("$2")
}

add_ticket_fact() {
    TICKET_FACTS+=("$1")
}

read_key_value() {
    local file="$1" key="$2"
    awk -v wanted="$key" '$1 == wanted {print $2; exit}' "$file" 2>/dev/null
}

psi_avg10() {
    local file="$1" mode="$2"
    awk -v wanted="$mode" '$1 == wanted {for (i = 2; i <= NF; i++) if ($i ~ /^avg10=/) {split($i, pair, "="); print pair[2]; exit}}' "$file" 2>/dev/null
}

decimal_ge() {
    awk -v value="${1:-0}" -v threshold="$2" 'BEGIN {exit !(value + 0 >= threshold + 0)}'
}

pressure_status() {
    local value="$1" warn_at="$2" fail_at="$3" label="$4" flag_name="$5"
    if decimal_ge "$value" "$fail_at"; then
        printf -v "$flag_name" '%s' 2
        status_line FAIL "$label: ${value}%"
    elif decimal_ge "$value" "$warn_at"; then
        printf -v "$flag_name" '%s' 1
        status_line WARN "$label: ${value}%"
    else
        status_line PASS "$label: ${value}%"
    fi
}

sample_cpu_contention() {
    [[ -r /proc/stat ]] || return 0

    local _cpu user nice system idle iowait irq softirq steal _guest _guest_nice
    local total_1 total_2 steal_1 steal_2 iowait_1 iowait_2 delta_total
    local cgroup_cpu_stat="/sys/fs/cgroup/cpu.stat"
    local periods_1=0 periods_2=0 throttled_1=0 throttled_2=0 delta_periods=0 delta_throttled=0
    if [[ -r "$cgroup_cpu_stat" ]]; then
        periods_1="$(read_key_value "$cgroup_cpu_stat" nr_periods)"
        throttled_1="$(read_key_value "$cgroup_cpu_stat" nr_throttled)"
        periods_1="${periods_1:-0}"
        throttled_1="${throttled_1:-0}"
    fi
    read -r _cpu user nice system idle iowait irq softirq steal _guest _guest_nice < /proc/stat
    total_1=$((user + nice + system + idle + iowait + irq + softirq + steal))
    steal_1=$steal
    iowait_1=$iowait
    sleep 2
    read -r _cpu user nice system idle iowait irq softirq steal _guest _guest_nice < /proc/stat
    total_2=$((user + nice + system + idle + iowait + irq + softirq + steal))
    steal_2=$steal
    iowait_2=$iowait
    delta_total=$((total_2 - total_1))
    if ((delta_total > 0)); then
        CPU_STEAL_PCT=$(((steal_2 - steal_1) * 100 / delta_total))
        CPU_IOWAIT_PCT=$(((iowait_2 - iowait_1) * 100 / delta_total))
    fi
    if [[ -r "$cgroup_cpu_stat" ]]; then
        periods_2="$(read_key_value "$cgroup_cpu_stat" nr_periods)"
        throttled_2="$(read_key_value "$cgroup_cpu_stat" nr_throttled)"
        periods_2="${periods_2:-0}"
        throttled_2="${throttled_2:-0}"
        delta_periods=$((periods_2 - periods_1))
        delta_throttled=$((throttled_2 - throttled_1))
        if ((delta_periods > 0 && delta_throttled > 0)); then
            CGROUP_THROTTLE_PCT=$((delta_throttled * 100 / delta_periods))
        fi
    fi
}

collect_kernel_log() {
    local file="$TMP_DIR/kernel.log"
    if command_exists journalctl; then
        journalctl -k --since "${HOURS} hours ago" --no-pager 2>/dev/null >"$file" || true
    elif command_exists dmesg; then
        dmesg --ctime 2>/dev/null >"$file" || dmesg 2>/dev/null >"$file" || true
    else
        : >"$file"
    fi
    printf '%s' "$file"
}

check_system() {
    section "$(tr_text '系统概况' 'System overview')"

    local os_name="unknown"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        os_name="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-unknown}")"
    fi
    status_line INFO "$(tr_text '主机名' 'Hostname'): $host_name"
    status_line INFO "$(tr_text '系统' 'OS'): $os_name"
    status_line INFO "$(tr_text '内核' 'Kernel'): $(uname -r 2>/dev/null || printf 'unknown')"
    if command_exists systemd-detect-virt; then
        status_line INFO "$(tr_text '虚拟化' 'Virtualization'): $(systemd-detect-virt 2>/dev/null || printf 'none')"
    fi

    local uptime_seconds=0 uptime_human="unknown"
    if [[ -r /proc/uptime ]]; then
        uptime_seconds="$(awk '{printf "%d", $1}' /proc/uptime)"
    fi
    if command_exists uptime; then
        uptime_human="$(uptime -p 2>/dev/null || uptime 2>/dev/null || printf 'unknown')"
    fi
    if ((uptime_seconds > 0 && uptime_seconds < HOURS * 3600)); then
        FLAG_RECENT_REBOOT=1
        if ((uptime_seconds < 600)); then
            status_line WARN "$(tr_text '系统在 10 分钟内启动过' 'System booted within the last 10 minutes'): $uptime_human"
        else
            status_line WARN "$(tr_text "系统在最近 ${HOURS} 小时内启动过" "System booted within the last ${HOURS} hours"): $uptime_human"
        fi
    else
        status_line PASS "$(tr_text '运行时间' 'Uptime'): $uptime_human"
    fi

    if ((EUID != 0)); then
        status_line WARN "$(tr_text '当前不是 root，部分内核和历史日志可能不可见；建议使用 sudo 运行' 'Not running as root; some kernel/history logs may be unavailable. Use sudo for a complete report')"
    fi

    if command_exists timedatectl; then
        local synced
        synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
        if [[ "$synced" == "yes" ]]; then
            status_line PASS "$(tr_text '系统时间已同步' 'System clock is synchronized')"
        elif [[ -n "$synced" ]]; then
            status_line WARN "$(tr_text '系统时间未确认同步' 'System clock is not confirmed synchronized'): $synced"
        fi
    fi

    if [[ -e /var/run/reboot-required ]]; then
        status_line INFO "$(tr_text '系统更新提示需要重启（不代表当前故障）' 'A package update requests a reboot; this does not itself indicate a current fault')"
    fi
}

check_resources() {
    section "$(tr_text '资源状态' 'Resource health')"

    local cpus=1 load1="0" load_pct=0
    cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
    [[ "$cpus" =~ ^[0-9]+$ ]] && ((cpus > 0)) || cpus=1
    if [[ -r /proc/loadavg ]]; then
        load1="$(awk '{print $1}' /proc/loadavg)"
        load_pct="$(awk -v lval="$load1" -v cpu="$cpus" 'BEGIN { printf "%d", (lval * 100) / cpu }')"
        if ((load_pct >= 200)); then
            FLAG_HIGH_LOAD=2
            status_line FAIL "$(tr_text '1 分钟负载明显高于 CPU 容量' '1-minute load is far above CPU capacity'): $load1 / ${cpus} CPU"
        elif ((load_pct >= 100)); then
            FLAG_HIGH_LOAD=1
            status_line WARN "$(tr_text '1 分钟负载高于 CPU 容量' '1-minute load is above CPU capacity'): $load1 / ${cpus} CPU"
        else
            status_line PASS "$(tr_text '1 分钟负载' '1-minute load'): $load1 / ${cpus} CPU"
        fi
    fi

    local mem_total=0 mem_available=0 mem_pct=0 swap_total=0 swap_free=0 swap_pct=0
    if [[ -r /proc/meminfo ]]; then
        mem_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        mem_available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
        swap_total="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
        swap_free="$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)"
        if ((mem_total > 0)); then
            mem_pct=$(((mem_total - mem_available) * 100 / mem_total))
            ((mem_pct >= 95)) && FLAG_HIGH_MEMORY=2
            ((mem_pct >= 85 && mem_pct < 95)) && FLAG_HIGH_MEMORY=1
            percent_status "$mem_pct" 85 95 "$(tr_text '内存使用率' 'Memory usage')"
        fi
        if ((swap_total > 0)); then
            swap_pct=$(((swap_total - swap_free) * 100 / swap_total))
            ((swap_pct >= 90)) && FLAG_HIGH_SWAP=2
            ((swap_pct >= 70 && swap_pct < 90)) && FLAG_HIGH_SWAP=1
            percent_status "$swap_pct" 70 90 "$(tr_text 'Swap 使用率' 'Swap usage')"
        else
            status_line INFO "$(tr_text '未配置 Swap（小内存 VPS 建议关注 OOM 风险）' 'No swap configured; watch for OOM risk on low-memory VPS instances')"
        fi
    fi

    if command_exists df; then
        local fs _blocks _used _available capacity mount pct
        while read -r fs _blocks _used _available capacity mount; do
            [[ "$capacity" =~ ^[0-9]+%$ ]] || continue
            pct="${capacity%%%}"
            if ((pct >= 95)); then
                FLAG_DISK=2
                status_line FAIL "$(tr_text '磁盘空间严重不足' 'Disk space critically low'): $mount ${pct}% ($fs)"
            elif ((pct >= 85)); then
                ((FLAG_DISK < 1)) && FLAG_DISK=1
                status_line WARN "$(tr_text '磁盘空间偏高' 'Disk usage is high'): $mount ${pct}% ($fs)"
            else
                status_line PASS "$(tr_text '磁盘使用率' 'Disk usage'): $mount ${pct}%"
            fi
        done < <(df -P -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR > 1')

        local _ifs _inodes _iused _ifree icap imount ipct
        while read -r _ifs _inodes _iused _ifree icap imount; do
            [[ "$icap" =~ ^[0-9]+%$ ]] || continue
            ipct="${icap%%%}"
            if ((ipct >= 95)); then
                FLAG_INODE=2
                status_line FAIL "$(tr_text 'inode 严重不足' 'Inodes critically low'): $imount ${ipct}%"
            elif ((ipct >= 85)); then
                ((FLAG_INODE < 1)) && FLAG_INODE=1
                status_line WARN "$(tr_text 'inode 使用率偏高' 'Inode usage is high'): $imount ${ipct}%"
            fi
        done < <(df -Pi -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR > 1')
    fi

    sample_cpu_contention
    if ((CPU_STEAL_PCT >= 15)); then
        status_line FAIL "$(tr_text 'CPU steal 很高，强烈提示宿主机 CPU 争用' 'CPU steal is very high, strongly indicating host CPU contention'): ${CPU_STEAL_PCT}%"
    elif ((CPU_STEAL_PCT >= 5)); then
        status_line WARN "$(tr_text 'CPU steal 偏高，可能存在宿主机 CPU 争用' 'CPU steal is elevated; host CPU contention is possible'): ${CPU_STEAL_PCT}%"
    else
        status_line PASS "CPU steal: ${CPU_STEAL_PCT}%"
    fi
    if ((CPU_IOWAIT_PCT >= 20)); then
        status_line FAIL "$(tr_text 'CPU I/O wait 很高，磁盘或宿主机存储可能拥堵' 'CPU I/O wait is very high; disk or host storage may be congested'): ${CPU_IOWAIT_PCT}%"
    elif ((CPU_IOWAIT_PCT >= 10)); then
        status_line WARN "$(tr_text 'CPU I/O wait 偏高' 'CPU I/O wait is elevated'): ${CPU_IOWAIT_PCT}%"
    else
        status_line PASS "CPU I/O wait: ${CPU_IOWAIT_PCT}%"
    fi
}

check_pressure_and_limits() {
    section "$(tr_text '压力、配额与进程健康' 'Pressure, quotas, and process health')"

    if [[ -r /proc/pressure/cpu ]]; then
        PSI_CPU_AVG10="$(psi_avg10 /proc/pressure/cpu some)"
        PSI_MEMORY_FULL_AVG10="$(psi_avg10 /proc/pressure/memory full)"
        PSI_IO_FULL_AVG10="$(psi_avg10 /proc/pressure/io full)"
        PSI_CPU_AVG10="${PSI_CPU_AVG10:-0}"
        PSI_MEMORY_FULL_AVG10="${PSI_MEMORY_FULL_AVG10:-0}"
        PSI_IO_FULL_AVG10="${PSI_IO_FULL_AVG10:-0}"
        pressure_status "$PSI_CPU_AVG10" 25 60 "$(tr_text 'CPU PSI some avg10' 'CPU PSI some avg10')" FLAG_CPU_PRESSURE
        pressure_status "$PSI_MEMORY_FULL_AVG10" 2 10 "$(tr_text '内存 PSI full avg10' 'Memory PSI full avg10')" FLAG_MEMORY_PRESSURE
        pressure_status "$PSI_IO_FULL_AVG10" 2 10 "$(tr_text 'I/O PSI full avg10' 'I/O PSI full avg10')" FLAG_IO_PRESSURE
    else
        status_line INFO "$(tr_text '内核未提供 PSI 压力指标' 'Kernel pressure stall information (PSI) is unavailable')"
    fi

    if [[ -r /sys/fs/cgroup/cpu.max ]]; then
        local quota period
        read -r quota period < /sys/fs/cgroup/cpu.max
        if [[ "$quota" != "max" && "$quota" =~ ^[0-9]+$ && "$period" =~ ^[0-9]+$ && "$period" -gt 0 ]]; then
            CGROUP_CPU_LIMIT="$(awk -v q="$quota" -v p="$period" 'BEGIN {printf "%.2f", q / p}')"
            status_line INFO "$(tr_text 'cgroup CPU 配额' 'cgroup CPU quota'): ${CGROUP_CPU_LIMIT} CPU"
        else
            status_line INFO "$(tr_text 'cgroup CPU 配额' 'cgroup CPU quota'): unlimited"
        fi
        if ((CGROUP_THROTTLE_PCT >= 50)); then
            FLAG_CGROUP_THROTTLE=2
            status_line FAIL "$(tr_text '采样期间 cgroup CPU 节流严重' 'Severe cgroup CPU throttling during sample'): ${CGROUP_THROTTLE_PCT}%"
        elif ((CGROUP_THROTTLE_PCT >= 20)); then
            FLAG_CGROUP_THROTTLE=1
            status_line WARN "$(tr_text '采样期间 cgroup CPU 节流偏高' 'Elevated cgroup CPU throttling during sample'): ${CGROUP_THROTTLE_PCT}%"
        else
            status_line PASS "$(tr_text 'cgroup CPU 节流周期占比' 'cgroup throttled-period ratio'): ${CGROUP_THROTTLE_PCT}%"
        fi
    fi

    if [[ -r /sys/fs/cgroup/memory.current && -r /sys/fs/cgroup/memory.max ]]; then
        local memory_current memory_max
        memory_current="$(cat /sys/fs/cgroup/memory.current)"
        memory_max="$(cat /sys/fs/cgroup/memory.max)"
        if [[ "$memory_max" != "max" && "$memory_current" =~ ^[0-9]+$ && "$memory_max" =~ ^[0-9]+$ && "$memory_max" -gt 0 ]]; then
            CGROUP_MEMORY_PCT="$(awk -v current="$memory_current" -v maximum="$memory_max" 'BEGIN {printf "%d", current * 100 / maximum}')"
            percent_status "$CGROUP_MEMORY_PCT" 85 95 "$(tr_text 'cgroup 内存使用率' 'cgroup memory usage')"
            if ((CGROUP_MEMORY_PCT >= 85 && FLAG_MEMORY_PRESSURE < 1)); then
                FLAG_MEMORY_PRESSURE=1
            fi
        fi
    fi

    if [[ -r /sys/fs/cgroup/pids.current && -r /sys/fs/cgroup/pids.max ]]; then
        local pids_current pids_max pids_pct
        pids_current="$(cat /sys/fs/cgroup/pids.current)"
        pids_max="$(cat /sys/fs/cgroup/pids.max)"
        if [[ "$pids_max" != "max" && "$pids_current" =~ ^[0-9]+$ && "$pids_max" =~ ^[0-9]+$ && "$pids_max" -gt 0 ]]; then
            pids_pct=$((pids_current * 100 / pids_max))
            if ((pids_pct >= 95)); then
                FLAG_PID_LIMIT=2
                status_line FAIL "$(tr_text 'cgroup PID 配额接近耗尽' 'cgroup PID quota is nearly exhausted'): $pids_current/$pids_max (${pids_pct}%)"
            elif ((pids_pct >= 80)); then
                FLAG_PID_LIMIT=1
                status_line WARN "$(tr_text 'cgroup PID 使用率偏高' 'cgroup PID usage is high'): $pids_current/$pids_max (${pids_pct}%)"
            else
                status_line PASS "$(tr_text 'cgroup PID 使用率' 'cgroup PID usage'): $pids_current/$pids_max (${pids_pct}%)"
            fi
        fi
    fi

    if command_exists ps; then
        local d_count z_count
        d_count="$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^D/ {count++} END {print count + 0}')"
        z_count="$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^Z/ {count++} END {print count + 0}')"
        if ((d_count >= 5)); then
            FLAG_DSTATE=2
            status_line FAIL "$(tr_text '不可中断睡眠（D 状态）进程较多' 'Many processes are in uninterruptible D state'): $d_count"
        elif ((d_count > 0)); then
            FLAG_DSTATE=1
            status_line WARN "$(tr_text '发现不可中断睡眠（D 状态）进程' 'Processes in uninterruptible D state found'): $d_count"
        else
            status_line PASS "$(tr_text '没有 D 状态进程' 'No processes in uninterruptible D state')"
        fi
        if ((z_count >= 20)); then
            FLAG_ZOMBIE=2
            status_line FAIL "$(tr_text '僵尸进程过多' 'Too many zombie processes'): $z_count"
        elif ((z_count > 0)); then
            FLAG_ZOMBIE=1
            status_line WARN "$(tr_text '发现僵尸进程' 'Zombie processes found'): $z_count"
        else
            status_line PASS "$(tr_text '没有僵尸进程' 'No zombie processes')"
        fi
    fi

    if [[ -r /proc/sys/fs/file-nr ]]; then
        local file_allocated _file_unused file_max file_pct
        read -r file_allocated _file_unused file_max < /proc/sys/fs/file-nr
        if ((file_max > 0)); then
            file_pct=$((file_allocated * 100 / file_max))
            if ((file_pct >= 90)); then
                FLAG_FILE_HANDLES=2
                status_line FAIL "$(tr_text '系统文件句柄接近耗尽' 'System file handles are nearly exhausted'): $file_allocated/$file_max (${file_pct}%)"
            elif ((file_pct >= 70)); then
                FLAG_FILE_HANDLES=1
                status_line WARN "$(tr_text '系统文件句柄使用率偏高' 'System file-handle usage is high'): $file_allocated/$file_max (${file_pct}%)"
            else
                status_line PASS "$(tr_text '系统文件句柄使用率' 'System file-handle usage'): $file_allocated/$file_max (${file_pct}%)"
            fi
        fi
    fi

    if command_exists findmnt; then
        local root_options
        root_options="$(findmnt -rn -o OPTIONS / 2>/dev/null || true)"
        if [[ ",$root_options," == *,ro,* ]]; then
            FLAG_READONLY_ROOT=1
            status_line FAIL "$(tr_text '根文件系统处于只读状态' 'Root filesystem is mounted read-only'): $root_options"
        elif [[ -n "$root_options" ]]; then
            status_line PASS "$(tr_text '根文件系统可写' 'Root filesystem is writable')"
        fi
    fi
}

check_services_and_reboots() {
    section "$(tr_text '服务与启动记录' 'Services and boot history')"

    if command_exists systemctl && [[ -d /run/systemd/system ]]; then
        local failed_units system_state
        system_state="$(systemctl is-system-running 2>/dev/null || true)"
        if [[ "$system_state" == "running" ]]; then
            status_line PASS "systemd: running"
        elif [[ -n "$system_state" ]]; then
            FLAG_FAILED_UNITS=1
            status_line WARN "$(tr_text 'systemd 系统状态异常' 'systemd system state is not healthy'): $system_state"
        fi
        failed_units="$(systemctl --failed --no-legend --plain 2>/dev/null || true)"
        if [[ -n "$failed_units" ]]; then
            FLAG_FAILED_UNITS=1
            status_line FAIL "$(tr_text '存在失败的 systemd 单元' 'Failed systemd units were found')"
            append_block "$(tr_text '失败单元：' 'Failed units:')" "$failed_units"
        else
            status_line PASS "$(tr_text '没有失败的 systemd 单元' 'No failed systemd units')"
        fi

        local service active restarts
        for service in "${SERVICES[@]}"; do
            active="$(systemctl is-active "$service" 2>/dev/null || true)"
            restarts="$(systemctl show "$service" -p NRestarts --value 2>/dev/null || true)"
            if [[ "$active" == "active" ]]; then
                status_line PASS "$(tr_text '服务正常' 'Service is active'): $service (NRestarts=${restarts:-unknown})"
            else
                FLAG_SERVICE_DOWN=1
                status_line FAIL "$(tr_text '服务未运行' 'Service is not active'): $service (${active:-unknown})"
            fi
        done
    else
        status_line INFO "$(tr_text '未检测到 systemd，跳过失败单元检查' 'systemd not detected; skipped failed-unit checks')"
    fi

    if command_exists last; then
        local boot_history
        boot_history="$(last -x -F 2>/dev/null | head -n 12 || true)"
        append_block "$(tr_text '最近启动/关机记录：' 'Recent boot/shutdown history:')" "$boot_history"
    fi
}

show_kernel_matches() {
    local kernel_log="$1" regex="$2" label_zh="$3" label_en="$4" severity="$5" flag_name="${6:-}"
    local matches count
    matches="$(grep -Eai "$regex" "$kernel_log" 2>/dev/null | tail -n 20 || true)"
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
    if ((count > 0)); then
        [[ -n "$flag_name" ]] && printf -v "$flag_name" '%s' 1
        status_line "$severity" "$(tr_text "$label_zh" "$label_en"): $count"
        append_block "$(tr_text '最近记录：' 'Recent entries:')" "$matches"
    else
        status_line PASS "$(tr_text "未发现：${label_zh}" "No ${label_en,,} found")"
    fi
}

check_kernel_events() {
    local kernel_log="$1"
    section "$(tr_text "最近 ${HOURS} 小时异常日志" "Anomalies in the last ${HOURS} hours")"

    if [[ ! -s "$kernel_log" ]]; then
        status_line WARN "$(tr_text '无法读取内核日志；请确认以 root 运行且 journal 可用' 'Could not read kernel logs; run as root and verify journal availability')"
        return
    fi

    show_kernel_matches "$kernel_log" \
        'oom-kill|out of memory|killed process [0-9]+' \
        'OOM/内存不足事件' 'OOM/out-of-memory events' FAIL FLAG_OOM
    show_kernel_matches "$kernel_log" \
        'kernel panic|soft lockup|hard lockup|watchdog.*lockup|blocked for more than|hung task' \
        '内核卡死/看门狗事件' 'kernel lockup/watchdog events' FAIL FLAG_KERNEL_LOCKUP
    show_kernel_matches "$kernel_log" \
        'I/O error|buffer I/O|EXT[234]-fs error|XFS.*(corrupt|error)|BTRFS.*(corrupt|error)|blk_update_request' \
        '磁盘或文件系统错误' 'disk/filesystem errors' FAIL FLAG_STORAGE_ERROR
    show_kernel_matches "$kernel_log" \
        'NETDEV WATCHDOG|transmit queue.*timed out|link is down|lost carrier|NIC Link is Down' \
        '网卡掉线/发送超时事件' 'NIC link-down/transmit-timeout events' WARN FLAG_NIC_EVENT
    show_kernel_matches "$kernel_log" \
        'segfault|general protection fault|machine check|hardware error|MCE:' \
        '进程崩溃/硬件异常事件' 'process-crash/hardware-error events' WARN FLAG_KERNEL_CRASH
    show_kernel_matches "$kernel_log" \
        'clocksource.*unstable|timekeeping watchdog|time jumped backwards|Time went backwards' \
        '时钟源/时间跳变事件' 'clocksource/time-jump events' WARN FLAG_TIMEKEEPING
    show_kernel_matches "$kernel_log" \
        'nf_conntrack: table full|possible SYN flooding|TCP: out of memory|too many orphaned sockets|Neighbour table overflow' \
        '内核网络栈溢出/洪泛事件' 'kernel network-stack overflow/flood events' FAIL FLAG_NETWORK_STACK
}

default_interface() {
    local target="${TARGETS[0]}"
    ip route get "$target" 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

read_counter() {
    local iface="$1" counter="$2" file
    file="/sys/class/net/$iface/statistics/$counter"
    if [[ -r "$file" ]]; then
        tr -cd '0-9' <"$file"
    else
        printf '0'
    fi
}

check_network_interface() {
    section "$(tr_text '网络接口与路由' 'Network interface and routing')"

    if ! command_exists ip; then
        status_line FAIL "$(tr_text '缺少 ip 命令，无法检查路由和网卡' 'The ip command is missing; cannot inspect routes or interfaces')"
        return
    fi

    local iface route operstate rx_errors tx_errors rx_dropped tx_dropped
    iface="$(default_interface)"
    DEFAULT_IFACE="$iface"
    route="$(ip route show default 2>/dev/null | head -n 3 || true)"
    if [[ -z "$iface" ]]; then
        status_line FAIL "$(tr_text '没有找到可用的默认出口接口' 'No usable default egress interface found')"
        append_block "$(tr_text '默认路由：' 'Default route:')" "$route"
        return
    fi

    operstate="$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || printf 'unknown')"
    if [[ "$operstate" == "up" || "$operstate" == "unknown" ]]; then
        status_line PASS "$(tr_text '默认出口接口' 'Default egress interface'): $iface ($operstate)"
    else
        status_line FAIL "$(tr_text '默认出口接口状态异常' 'Default egress interface state is abnormal'): $iface ($operstate)"
    fi
    append_block "$(tr_text '默认路由：' 'Default route:')" "$route"

    rx_errors="$(read_counter "$iface" rx_errors)"
    tx_errors="$(read_counter "$iface" tx_errors)"
    rx_dropped="$(read_counter "$iface" rx_dropped)"
    tx_dropped="$(read_counter "$iface" tx_dropped)"
    NET_RX_ERRORS_START=$rx_errors
    NET_TX_ERRORS_START=$tx_errors
    NET_RX_DROPPED_START=$rx_dropped
    NET_TX_DROPPED_START=$tx_dropped
    status_line INFO "$(tr_text '网卡累计计数' 'Lifetime NIC counters'): RX errors=$rx_errors, TX errors=$tx_errors, RX dropped=$rx_dropped, TX dropped=$tx_dropped"
    if ((rx_errors > 0 || tx_errors > 0)); then
        FLAG_NIC_COUNTER=1
        status_line WARN "$(tr_text '网卡存在累计错误包；需结合运行时间和增量判断' 'NIC error counters are non-zero; compare their growth over time')"
    fi
    if ((rx_dropped > 1000 || tx_dropped > 1000)); then
        FLAG_NIC_COUNTER=1
        status_line WARN "$(tr_text '网卡累计丢包较多；需再次运行脚本比较是否持续增长' 'NIC drop counters are high; rerun later to check whether they keep increasing')"
    fi

    if [[ -r /proc/sys/net/netfilter/nf_conntrack_count && -r /proc/sys/net/netfilter/nf_conntrack_max ]]; then
        local conn_count conn_max conn_pct
        conn_count="$(cat /proc/sys/net/netfilter/nf_conntrack_count)"
        conn_max="$(cat /proc/sys/net/netfilter/nf_conntrack_max)"
        if ((conn_max > 0)); then
            conn_pct=$((conn_count * 100 / conn_max))
            if ((conn_pct >= 90)); then
                FLAG_CONNTRACK=2
                status_line FAIL "$(tr_text '连接跟踪表接近耗尽' 'Conntrack table is nearly exhausted'): $conn_count/$conn_max (${conn_pct}%)"
            elif ((conn_pct >= 70)); then
                FLAG_CONNTRACK=1
                status_line WARN "$(tr_text '连接跟踪表使用率较高' 'Conntrack usage is high'): $conn_count/$conn_max (${conn_pct}%)"
            else
                status_line PASS "$(tr_text '连接跟踪表' 'Conntrack table'): $conn_count/$conn_max (${conn_pct}%)"
            fi
        fi
    fi

    if command_exists ss; then
        local socket_summary
        socket_summary="$(ss -s 2>/dev/null || true)"
        append_block "$(tr_text '连接摘要：' 'Socket summary:')" "$socket_summary"
    fi
}

ping_target() {
    local target="$1" ping_output loss avg
    ((PING_TESTS += 1))
    ping_output="$(ping -n -c 5 -W 2 "$target" 2>&1 || true)"
    loss="$(printf '%s\n' "$ping_output" | sed -nE 's/.* ([0-9]+([.][0-9]+)?)% packet loss.*/\1/p' | tail -n 1)"
    avg="$(printf '%s\n' "$ping_output" | awk -F'=' '/(rtt|round-trip) min\/avg\/max/ {gsub(/^[[:space:]]+/, "", $2); split($2, a, "/"); print a[2]; exit}')"
    if [[ -z "$loss" ]]; then
        ((PING_FAILURES += 1))
        status_line FAIL "$(tr_text '无法完成 Ping' 'Ping did not complete'): $target"
        append_block "Ping output:" "$ping_output"
        return
    fi

    local loss_int="${loss%.*}"
    if ((loss_int == 0)); then
        status_line PASS "Ping $target: loss=${loss}%, avg=${avg:-unknown} ms"
    elif ((loss_int <= 20)); then
        ((PING_WARNINGS += 1))
        status_line WARN "Ping $target: loss=${loss}%, avg=${avg:-unknown} ms"
    else
        ((PING_FAILURES += 1))
        status_line FAIL "Ping $target: loss=${loss}%, avg=${avg:-unknown} ms"
    fi
}

check_connectivity() {
    section "$(tr_text '外网连通性' 'Internet connectivity')"

    if command_exists ping; then
        local target
        for target in "${TARGETS[@]}"; do
            ping_target "$target"
        done
    else
        status_line WARN "$(tr_text '缺少 ping 命令，跳过 ICMP 丢包检查' 'ping is unavailable; skipped ICMP loss checks')"
    fi

    if command_exists getent; then
        if getent ahosts example.com >/dev/null 2>&1; then
            DNS_OK=1
            status_line PASS "$(tr_text 'DNS 解析正常' 'DNS resolution works')"
        else
            DNS_OK=0
            status_line FAIL "$(tr_text 'DNS 解析失败' 'DNS resolution failed')"
        fi
    else
        status_line INFO "$(tr_text '缺少 getent，跳过 DNS 检查' 'getent is unavailable; skipped DNS check')"
    fi

    if command_exists curl; then
        local http_code
        http_code="$(curl -sSIL --connect-timeout 5 --max-time 10 -o /dev/null -w '%{http_code}' https://example.com 2>/dev/null || true)"
        if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
            HTTPS_OK=1
            status_line PASS "HTTPS: example.com ($http_code)"
        else
            HTTPS_OK=0
            status_line FAIL "$(tr_text 'HTTPS 出站检查失败' 'Outbound HTTPS check failed'): example.com (${http_code:-no response})"
        fi
    else
        status_line INFO "$(tr_text '缺少 curl，跳过 HTTPS 检查' 'curl is unavailable; skipped HTTPS check')"
    fi

    if ((RUN_MTR == 1)); then
        if command_exists mtr; then
            local mtr_target mtr_output
            for mtr_target in "${TARGETS[@]}"; do
                mtr_output="$(mtr -n -r -w -c 20 "$mtr_target" 2>&1 || true)"
                printf '%s\n' "$mtr_output" >"$BUNDLE_DIR/raw/mtr-${mtr_target//[^A-Za-z0-9._-]/_}.txt"
                append_block "MTR $mtr_target:" "$mtr_output"
            done
        else
            status_line WARN "$(tr_text '未安装 mtr，无法生成路由质量报告' 'mtr is not installed; route-quality report skipped')"
        fi
    fi
}

netstat_field() {
    local file="$1" protocol="$2" field="$3"
    awk -v proto="$protocol" -v wanted="$field" '
        $1 == proto && !seen_header {
            for (i = 2; i <= NF; i++) if ($i == wanted) field_index = i
            seen_header = 1
            next
        }
        $1 == proto && seen_header && field_index > 0 {print $field_index; exit}
    ' "$file" 2>/dev/null
}

check_network_stack_and_ports() {
    section "$(tr_text 'TCP 栈、增量丢包与端口' 'TCP stack, drop deltas, and ports')"

    if [[ -n "$DEFAULT_IFACE" && -d "/sys/class/net/$DEFAULT_IFACE" ]]; then
        local rx_errors_end tx_errors_end rx_dropped_end tx_dropped_end
        rx_errors_end="$(read_counter "$DEFAULT_IFACE" rx_errors)"
        tx_errors_end="$(read_counter "$DEFAULT_IFACE" tx_errors)"
        rx_dropped_end="$(read_counter "$DEFAULT_IFACE" rx_dropped)"
        tx_dropped_end="$(read_counter "$DEFAULT_IFACE" tx_dropped)"
        NET_RX_ERROR_DELTA=$((rx_errors_end - NET_RX_ERRORS_START))
        NET_TX_ERROR_DELTA=$((tx_errors_end - NET_TX_ERRORS_START))
        NET_RX_DROP_DELTA=$((rx_dropped_end - NET_RX_DROPPED_START))
        NET_TX_DROP_DELTA=$((tx_dropped_end - NET_TX_DROPPED_START))
        if ((NET_RX_ERROR_DELTA < 0 || NET_TX_ERROR_DELTA < 0 || NET_RX_DROP_DELTA < 0 || NET_TX_DROP_DELTA < 0)); then
            FLAG_NIC_EVENT=1
            status_line WARN "$(tr_text '检查期间网卡计数器被重置，可能发生接口重建' 'NIC counters reset during the check; the interface may have been recreated')"
        elif ((NET_RX_ERROR_DELTA > 0 || NET_TX_ERROR_DELTA > 0 || NET_RX_DROP_DELTA > 0 || NET_TX_DROP_DELTA > 0)); then
            FLAG_NIC_COUNTER=1
            status_line WARN "$(tr_text '本次检查期间网卡错误/丢包计数增长' 'NIC errors/drops increased during this check'): RXerr=+$NET_RX_ERROR_DELTA TXerr=+$NET_TX_ERROR_DELTA RXdrop=+$NET_RX_DROP_DELTA TXdrop=+$NET_TX_DROP_DELTA"
        else
            status_line PASS "$(tr_text '本次检查期间网卡错误/丢包计数未增长' 'NIC errors/drop counters did not increase during this check')"
        fi
    fi

    if [[ -r /proc/net/snmp ]]; then
        local out_segments retrans_segments
        out_segments="$(netstat_field /proc/net/snmp 'Tcp:' OutSegs)"
        retrans_segments="$(netstat_field /proc/net/snmp 'Tcp:' RetransSegs)"
        out_segments="${out_segments:-0}"
        retrans_segments="${retrans_segments:-0}"
        if ((out_segments > 0)); then
            TCP_RETRANS_PCT="$(awk -v retrans="$retrans_segments" -v sent="$out_segments" 'BEGIN {printf "%d", retrans * 100 / sent}')"
            if ((out_segments >= 1000 && TCP_RETRANS_PCT >= 15)); then
                FLAG_TCP_RETRANS=2
                status_line FAIL "$(tr_text 'TCP 累计重传率很高' 'Lifetime TCP retransmission ratio is very high'): ${TCP_RETRANS_PCT}% ($retrans_segments/$out_segments)"
            elif ((out_segments >= 1000 && TCP_RETRANS_PCT >= 5)); then
                FLAG_TCP_RETRANS=1
                status_line WARN "$(tr_text 'TCP 累计重传率偏高' 'Lifetime TCP retransmission ratio is elevated'): ${TCP_RETRANS_PCT}% ($retrans_segments/$out_segments)"
            else
                status_line PASS "$(tr_text 'TCP 累计重传率' 'Lifetime TCP retransmission ratio'): ${TCP_RETRANS_PCT}% ($retrans_segments/$out_segments)"
            fi
        fi
    fi

    if [[ -r /proc/net/netstat ]]; then
        local listen_overflows listen_drops backlog_drops
        listen_overflows="$(netstat_field /proc/net/netstat 'TcpExt:' ListenOverflows)"
        listen_drops="$(netstat_field /proc/net/netstat 'TcpExt:' ListenDrops)"
        backlog_drops="$(netstat_field /proc/net/netstat 'TcpExt:' TCPBacklogDrop)"
        listen_overflows="${listen_overflows:-0}"
        listen_drops="${listen_drops:-0}"
        backlog_drops="${backlog_drops:-0}"
        if ((listen_overflows > 0 || listen_drops > 0 || backlog_drops > 0)); then
            FLAG_SYN_BACKLOG=1
            status_line WARN "$(tr_text 'TCP 监听/积压队列存在累计丢弃' 'TCP listen/backlog queues have cumulative drops'): overflow=$listen_overflows listen_drop=$listen_drops backlog_drop=$backlog_drops"
        else
            status_line PASS "$(tr_text '未发现 TCP 监听/积压队列丢弃' 'No TCP listen/backlog queue drops found')"
        fi
    fi

    if [[ -r /proc/net/softnet_stat ]]; then
        local _processed_hex dropped_hex squeezed_hex _rest softnet_dropped=0 softnet_squeezed=0
        while read -r _processed_hex dropped_hex squeezed_hex _rest; do
            [[ "$dropped_hex" =~ ^[0-9A-Fa-f]+$ ]] && softnet_dropped=$((softnet_dropped + 16#$dropped_hex))
            [[ "$squeezed_hex" =~ ^[0-9A-Fa-f]+$ ]] && softnet_squeezed=$((softnet_squeezed + 16#$squeezed_hex))
        done < /proc/net/softnet_stat
        if ((softnet_dropped > 0 || softnet_squeezed > 0)); then
            FLAG_NETWORK_STACK=1
            status_line WARN "$(tr_text '内核 softnet 存在累计丢包/处理挤压' 'Kernel softnet has cumulative drops/time-squeeze events'): dropped=$softnet_dropped squeezed=$softnet_squeezed"
        else
            status_line PASS "$(tr_text '内核 softnet 没有累计丢包' 'No cumulative kernel softnet drops')"
        fi
    fi

    if command_exists ss; then
        local state_summary syn_recv
        state_summary="$(ss -Hant 2>/dev/null | awk '{count[$1]++} END {for (state in count) printf "%s=%d ", state, count[state]}' || true)"
        syn_recv="$(ss -Hant state syn-recv 2>/dev/null | wc -l | tr -d ' ')"
        append_block "$(tr_text 'TCP 状态摘要：' 'TCP state summary:')" "$state_summary"
        if ((syn_recv >= 1000)); then
            FLAG_SYN_BACKLOG=2
            status_line FAIL "$(tr_text 'SYN-RECV 连接异常多，疑似连接洪泛或应用拥堵' 'Extremely high SYN-RECV count; possible flood or application congestion'): $syn_recv"
        elif ((syn_recv >= 100)); then
            FLAG_SYN_BACKLOG=1
            status_line WARN "$(tr_text 'SYN-RECV 连接较多' 'Elevated SYN-RECV count'): $syn_recv"
        else
            status_line PASS "SYN-RECV: $syn_recv"
        fi

        local port listen_line
        for port in "${PORTS[@]}"; do
            listen_line="$(ss -H -lnt 2>/dev/null | awk -v suffix=":$port" '$4 ~ suffix "$" {print; exit}')"
            if [[ -n "$listen_line" ]]; then
                status_line PASS "$(tr_text '本机 TCP 端口正在监听' 'Local TCP port is listening'): $port"
            else
                FLAG_PORT_CHECK=1
                status_line FAIL "$(tr_text '本机 TCP 端口未监听' 'Local TCP port is not listening'): $port"
            fi
        done
    elif ((${#PORTS[@]} > 0)); then
        status_line WARN "$(tr_text '缺少 ss，无法检查指定监听端口' 'ss is unavailable; requested listening-port checks were skipped')"
    fi

    if ((${#TCP_TARGETS[@]} > 0)); then
        if command_exists timeout; then
            local tcp_target host port
            for tcp_target in "${TCP_TARGETS[@]}"; do
                host="${tcp_target%:*}"
                port="${tcp_target##*:}"
                if timeout 5 bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null; then
                    status_line PASS "$(tr_text '远端 TCP 端口可连接' 'Remote TCP port is reachable'): $tcp_target"
                else
                    FLAG_TCP_TARGET=1
                    status_line FAIL "$(tr_text '远端 TCP 端口连接失败' 'Remote TCP connection failed'): $tcp_target"
                fi
            done
        else
            status_line WARN "$(tr_text '缺少 timeout，无法安全执行远端 TCP 探测' 'timeout is unavailable; remote TCP probes were skipped safely')"
        fi
    fi
}

import_probe_log() {
    [[ -n "$PROBE_LOG" ]] || return 0
    section "$(tr_text '外部探针证据' 'External probe evidence')"

    cp -- "$PROBE_LOG" "$BUNDLE_DIR/raw/external-probe.log"
    PROBE_LOST_COUNT="$(grep -Eic 'lost|down|offline|unreachable|不可达|中断|掉线' "$PROBE_LOG" 2>/dev/null || true)"
    if ((PROBE_LOST_COUNT > 0)); then
        status_line WARN "$(tr_text '外部探针记录到不可达事件' 'External probe recorded unreachable events'): $PROBE_LOST_COUNT"
        add_ticket_fact "External monitoring recorded ${PROBE_LOST_COUNT} unreachable/lost events."
    else
        status_line INFO "$(tr_text '已导入探针日志，但没有识别到 lost/down 关键词' 'Probe log imported, but no lost/down keywords were recognized')"
    fi
    append_block "$(tr_text '探针日志末尾（完整文件已进入证据包）：' 'Probe log tail (full file is in the evidence bundle):')" "$(tail -n 50 "$PROBE_LOG" 2>/dev/null || true)"
}

import_process_monitor_log() {
    [[ -n "$MONITOR_LOG" ]] || return 0
    section "$(tr_text '后台异常进程证据' 'Background process-monitor evidence')"

    cp -- "$MONITOR_LOG" "$BUNDLE_DIR/raw/process-monitor.log"
    MONITOR_ANOMALY_COUNT="$(grep -c '\[ANOMALY\]' "$MONITOR_LOG" 2>/dev/null || true)"
    if ((MONITOR_ANOMALY_COUNT > 0)); then
        FLAG_PROCESS_MONITOR=1
        status_line WARN "$(tr_text '后台监控捕获到异常快照' 'Background monitor captured anomaly snapshots'): $MONITOR_ANOMALY_COUNT"
        add_ticket_fact "The background process monitor captured ${MONITOR_ANOMALY_COUNT} anomaly snapshots."
    elif ((MONITOR_LOG_AUTO == 1)); then
        status_line PASS "$(tr_text '已自动导入后台监控日志，暂未发现异常快照' 'Automatically imported the monitor log; no anomaly snapshots were found')"
    else
        status_line PASS "$(tr_text '后台监控日志中没有异常快照' 'No anomaly snapshots were found in the monitor log')"
    fi
    append_block "$(tr_text '后台监控日志末尾（完整文件已进入证据包）：' 'Monitor log tail (full file is in the evidence bundle):')" "$(tail -n 80 "$MONITOR_LOG" 2>/dev/null || true)"
}

build_recommendations() {
    section "$(tr_text '建议与下一步' 'Recommendations and next steps')"

    if ((FLAG_HIGH_LOAD > 0)); then
        add_recommendation \
            "系统负载高于可用 CPU。先查看 evidence/raw/processes.txt 和 top，判断是本机进程占用还是 CPU steal 同时偏高；只有排除本机负载后，才应把方向转向宿主机争用。" \
            "System load exceeds available CPU capacity. Review evidence/raw/processes.txt and top to distinguish guest workload from elevated CPU steal; investigate host contention only after guest load is ruled out."
    fi

    if ((FLAG_CPU_PRESSURE > 0 || FLAG_CGROUP_THROTTLE > 0)); then
        add_recommendation \
            "检测到 CPU PSI 压力或 cgroup 节流。先对照进程 Top 与 CPU 配额；如果业务负载不高但 PSI/节流持续出现，保存多次样本并要求厂商检查宿主机 CPU 争用或套餐限额。" \
            "CPU PSI pressure or cgroup throttling was detected. Compare process activity with the CPU quota; if guest workload is low while pressure/throttling persists, preserve repeated samples and ask the provider to inspect host contention or plan limits."
        add_ticket_fact "CPU pressure or cgroup throttling was detected during guest-side checks."
    fi

    if ((FLAG_MEMORY_PRESSURE > 0 || FLAG_IO_PRESSURE > 0)); then
        add_recommendation \
            "PSI 显示任务因内存或 I/O 持续等待。结合 resources.txt、D 状态进程和 cgroup 内存上限判断；本机没有重负载时，I/O full 压力可作为宿主机存储争用线索。" \
            "PSI shows tasks stalled on memory or I/O. Correlate resources.txt, D-state tasks, and the cgroup memory limit; persistent I/O full pressure without guest load can indicate host storage contention."
    fi

    if ((CPU_STEAL_PCT >= 5)); then
        add_recommendation \
            "CPU steal=${CPU_STEAL_PCT}%，这是宿主机 CPU 争用/超售的线索。先在不跑业务压测时重复检查 3 次；若持续偏高，把证据包提交 VPS 厂商，要求检查宿主机 CPU steal、负载和邻居实例争用。" \
            "CPU steal is ${CPU_STEAL_PCT}%, which can indicate host CPU contention or oversubscription. Repeat the check three times while the guest is otherwise idle; if it persists, send the evidence bundle to the provider and ask them to inspect host load and noisy-neighbor contention."
        add_ticket_fact "CPU steal was measured at ${CPU_STEAL_PCT}% during the diagnostic sample."
    fi

    if ((CPU_IOWAIT_PCT >= 10)); then
        add_recommendation \
            "CPU I/O wait=${CPU_IOWAIT_PCT}%，先用 iostat -xz 1 10 和 pidstat -d 1 10 排除 VPS 内部进程；如果本机磁盘活动不大但 await/iowait 持续高，建议提交厂商检查宿主机存储拥堵。" \
            "CPU I/O wait is ${CPU_IOWAIT_PCT}%. Use iostat -xz 1 10 and pidstat -d 1 10 to rule out guest workloads. If guest disk activity is low while await/iowait stays high, ask the provider to inspect host storage contention."
        add_ticket_fact "CPU I/O wait was measured at ${CPU_IOWAIT_PCT}% during the diagnostic sample."
    fi

    if ((FLAG_OOM > 0 || FLAG_HIGH_MEMORY > 0 || FLAG_HIGH_SWAP > 0)); then
        add_recommendation \
            "存在内存压力或 OOM 线索。查看 evidence/raw/processes.txt 和 journalctl -k，确认被杀进程；限制异常进程、修复内存泄漏，必要时增加 Swap 或升级内存。" \
            "Memory pressure or OOM evidence was found. Review evidence/raw/processes.txt and journalctl -k to identify killed processes; cap or fix the offending process and add swap or RAM if appropriate."
    fi

    if ((FLAG_DISK > 0 || FLAG_INODE > 0)); then
        add_recommendation \
            "磁盘空间或 inode 偏高。使用 du -xhd1 / 和 df -i 定位目录；先处理日志、缓存或大量小文件，不要直接删除不明系统文件。" \
            "Disk space or inode usage is high. Use du -xhd1 / and df -i to locate the source; clean known logs, caches, or excessive small files without deleting unknown system data."
    fi

    if ((FLAG_STORAGE_ERROR > 0)); then
        add_recommendation \
            "内核记录到 I/O/文件系统错误。立即备份重要数据，保存原始内核日志并提交厂商；不要只做重启掩盖问题。" \
            "Kernel I/O or filesystem errors were found. Back up important data immediately, preserve the raw kernel log, and contact the provider instead of masking the issue with a reboot."
        add_ticket_fact "The guest kernel log contains storage or filesystem I/O errors."
    fi

    if ((FLAG_KERNEL_CRASH > 0)); then
        add_recommendation \
            "内核日志记录到进程崩溃、general protection fault 或硬件错误。先定位对应程序与时间；若出现 MCE/hardware error 或多个无关进程同时崩溃，应把原始内核日志提交厂商。" \
            "Kernel logs contain process crashes, general-protection faults, or hardware errors. Identify the program and timestamp; MCE/hardware errors or crashes across unrelated processes should be escalated with raw kernel logs."
    fi

    if ((FLAG_TIMEKEEPING > 0)); then
        add_recommendation \
            "发现时钟源不稳定或时间跳变，可能影响 TLS、定时任务和探针时间线。确认 NTP 状态；虚拟机 clocksource 持续异常时要求厂商检查 hypervisor 时间同步。" \
            "Clocksource instability or time jumps were found, which can affect TLS, scheduled jobs, and monitoring timelines. Verify NTP and ask the provider to inspect hypervisor timekeeping if it persists."
    fi

    if ((FLAG_FAILED_UNITS > 0 || FLAG_SERVICE_DOWN > 0)); then
        add_recommendation \
            "存在失败或未运行的服务。先执行 systemctl status <服务名> 和 journalctl -u <服务名> --since \"${HOURS} hours ago\"，这类问题通常应先在 VPS 内部处理。" \
            "Failed or inactive services were found. Run systemctl status <unit> and journalctl -u <unit> --since \"${HOURS} hours ago\"; these issues usually need guest-side remediation first."
    fi

    if ((FLAG_DSTATE > 0 || FLAG_ZOMBIE > 0)); then
        add_recommendation \
            "发现 D 状态或僵尸进程。D 状态通常需要检查磁盘/NFS/块设备等待，僵尸进程需要定位其父进程；后台监控日志可以确认它们是否反复出现。" \
            "D-state or zombie processes were found. Investigate disk/NFS/block-device waits for D-state tasks and identify parent processes for zombies; the background monitor can confirm whether they recur."
    fi

    if ((FLAG_FILE_HANDLES > 0 || FLAG_PID_LIMIT > 0)); then
        add_recommendation \
            "系统文件句柄或 PID 配额接近上限，新进程或新连接可能随机失败。检查高句柄进程、进程风暴和 cgroup pids.max，再决定调整限制或修复程序。" \
            "File handles or the PID quota are close to exhaustion, which can cause random process or connection failures. Find high-handle processes and process storms before changing limits."
    fi

    if ((FLAG_READONLY_ROOT > 0)); then
        add_recommendation \
            "根文件系统已变为只读。立即备份并检查内核 I/O/文件系统错误，优先联系厂商处理存储问题，不要强制写入或反复重启。" \
            "The root filesystem is read-only. Back up data and inspect kernel I/O/filesystem errors; contact the provider about storage before forcing writes or repeatedly rebooting."
        add_ticket_fact "The guest root filesystem was observed mounted read-only."
    fi

    if ((FLAG_RECENT_REBOOT > 0)); then
        add_recommendation \
            "系统在检查窗口内重启过。将 last -x、上一启动日志和外部探针时间对齐；若没有客户机重启命令或内核原因，要求厂商核查宿主机重启/迁移记录。" \
            "The system rebooted within the review window. Correlate last -x, previous-boot logs, and external monitoring; if no guest-side cause exists, ask the provider for host reboot or migration records."
    fi

    if ((FLAG_CONNTRACK > 0)); then
        add_recommendation \
            "连接跟踪表使用率偏高，检查 ss -s、连接洪泛、NAT/代理并发和防火墙规则；耗尽时会表现为新连接随机失败。" \
            "Conntrack usage is high. Inspect ss -s, connection floods, NAT/proxy concurrency, and firewall rules; table exhaustion can cause random new-connection failures."
    fi

    if ((FLAG_NETWORK_STACK > 0 || FLAG_TCP_RETRANS > 0 || FLAG_SYN_BACKLOG > 0)); then
        add_recommendation \
            "TCP 栈存在重传、监听队列溢出、SYN 堆积或内核网络告警。先检查是否遭受连接洪泛以及应用 accept 速度；若网卡增量也异常，再提交厂商检查节点网络。" \
            "The TCP stack shows retransmissions, listen-queue overflow, SYN buildup, or kernel network warnings. Check connection floods and application accept performance; escalate to the provider if NIC deltas are also abnormal."
    fi

    if ((FLAG_PORT_CHECK > 0)); then
        add_recommendation \
            "指定的本机 TCP 端口没有监听。先检查对应服务状态、监听地址和启动日志，再检查防火墙；端口本身未监听时不应先归因于线路或厂商。" \
            "A requested local TCP port is not listening. Check the service state, bind address, and startup logs before the firewall; a non-listening port is a guest-side issue before it is a provider/network issue."
    fi

    if ((FLAG_TCP_TARGET > 0)); then
        add_recommendation \
            "指定的远端 TCP 目标连接失败。结合 DNS、Ping、路由和目标服务状态判断；只有多个不同目标同时失败时，才更像本机出口或上游问题。" \
            "A requested remote TCP target failed. Correlate DNS, Ping, routing, and the destination service; failures across multiple unrelated targets more strongly indicate guest egress or upstream trouble."
    fi

    if ((FLAG_NIC_EVENT > 0 || FLAG_NIC_COUNTER > 0)); then
        add_recommendation \
            "发现网卡链路事件或错误计数。短时间重复运行并比较计数是否增长；若 virtio/ens 网卡出现 link down、watchdog 或发送超时，建议连同时间点提交厂商检查虚拟网卡和宿主机网络。" \
            "NIC link events or error counters were found. Rerun the check and compare counter growth; virtio/ens link-down, watchdog, or transmit-timeout events should be escalated to the provider with timestamps."
        add_ticket_fact "The guest recorded NIC link events or non-zero NIC error/drop counters."
    fi

    if ((PING_FAILURES > 0 || PING_WARNINGS > 0 || DNS_OK == 0 || HTTPS_OK == 0)); then
        add_recommendation \
            "当前存在丢包或外网连通异常。分别从本地、另一台稳定 VPS 和故障 VPS 做 MTR；只有中间跳丢包但终点正常不能作为故障证据，重点看终点丢包和 lost/back 时间。" \
            "Packet loss or outbound connectivity issues were detected. Run MTR from your local network, a stable VPS, and the affected VPS; intermediate-hop ICMP loss alone is not proof, so focus on destination loss and lost/back timestamps."
    fi

    if ((PROBE_LOST_COUNT > 0)); then
        if ((FLAG_NIC_EVENT == 0 && FLAG_OOM == 0 && FLAG_KERNEL_LOCKUP == 0 && FLAG_SERVICE_DOWN == 0)); then
            add_recommendation \
                "外部探针记录了失联，但客户机侧没有对应 OOM、内核卡死、服务停止或网卡 link-down 证据。优先把证据包提交 VPS 厂商，要求核查宿主机超售/资源争用、上游路由、DDoS 清洗或节点网络事件。此组合只能说明厂商侧值得排查，不能单独证明具体原因。" \
                "External monitoring recorded outages while the guest showed no matching OOM, lockup, stopped-service, or NIC link-down evidence. Send the bundle to the provider and ask them to inspect host contention/oversubscription, upstream routing, DDoS mitigation, and node network events. This pattern justifies investigation but does not prove a specific root cause."
            add_ticket_fact "The guest showed no matching OOM, kernel lockup, stopped-service, or NIC link-down event at the time of review."
        else
            add_recommendation \
                "外部失联与客户机内部异常同时存在，暂时不能只归因于厂商。先按报告处理本机异常，再把同一时间线和证据包交给厂商或有经验的管理员复核。" \
                "External outages and guest-side anomalies both exist, so the provider cannot yet be treated as the sole cause. Address the guest findings and share the aligned timeline and bundle with the provider or an experienced administrator."
        fi
    fi

    if ((WATCH_FAILURES > 0 || WATCH_TRANSITIONS > 0)); then
        add_recommendation \
            "持续监测捕获到 ${WATCH_FAILURES} 次失败、${WATCH_TRANSITIONS} 次状态变化。保留 EVENT 时间点，并与厂商宿主机日志、外部探针和 MTR 对齐。" \
            "Continuous monitoring captured ${WATCH_FAILURES} failed probes and ${WATCH_TRANSITIONS} state changes. Preserve the EVENT timestamps and correlate them with provider host logs, external probes, and MTR."
        add_ticket_fact "Continuous monitoring captured ${WATCH_FAILURES} failed probes and ${WATCH_TRANSITIONS} state changes."
    fi

    if ((FLAG_PROCESS_MONITOR > 0)); then
        add_recommendation \
            "后台监控捕获到 ${MONITOR_ANOMALY_COUNT} 个异常快照。按时间查看 process-monitor.log 中的 Top CPU/内存、D 状态、steal、iowait 和 PSI，并与探针 lost/back 时间对齐后再定责。" \
            "The background monitor captured ${MONITOR_ANOMALY_COUNT} anomaly snapshots. Correlate Top CPU/memory, D-state, steal, iowait, and PSI in process-monitor.log with external lost/back timestamps before assigning cause."
    fi

    if ((${#RECOMMENDATIONS_ZH[@]} == 0)); then
        add_recommendation \
            "本次快照没有发现明确异常，但这不能排除间歇性进程或资源故障。如果你仍感觉 VPS 有问题，建议运行：sudo bash vps-health-monitor.sh start --interval 3 --cpu 70 --memory 40 --load 120 --cooldown 60 --max-log-mb 20，让后台自动抓取异常 Top 快照；网络问题同时使用 --watch 和外部探针。" \
            "No clear anomaly was found in this snapshot, but intermittent process or resource faults are not ruled out. If the VPS still feels unhealthy, run: sudo bash vps-health-monitor.sh start --interval 3 --cpu 70 --memory 40 --load 120 --cooldown 60 --max-log-mb 20, and use --watch plus external monitoring for network issues."
    fi

    add_recommendation \
        "如果结论仍不明确，把整个 evidence.tar.gz 交给有经验的管理员或 AI 辅助审查；不要只贴一张结果截图，也不要公开密码、密钥或完整公网拓扑。" \
        "If the result remains unclear, give the complete evidence.tar.gz to an experienced administrator or an AI reviewer. Avoid sharing only a screenshot, and never expose passwords, keys, or a sensitive network topology."

    local i
    for ((i = 0; i < ${#RECOMMENDATIONS_ZH[@]}; i++)); do
        if [[ "$LANGUAGE" == "zh" ]]; then
            printf '%d. %s\n' "$((i + 1))" "${RECOMMENDATIONS_ZH[$i]}"
            plain_log "$((i + 1)). ${RECOMMENDATIONS_ZH[$i]}"
        else
            printf '%d. %s\n' "$((i + 1))" "${RECOMMENDATIONS_EN[$i]}"
            plain_log "$((i + 1)). ${RECOMMENDATIONS_EN[$i]}"
        fi
    done
}

collect_raw_evidence() {
    cp -- "$TMP_DIR/kernel.log" "$BUNDLE_DIR/raw/kernel-${HOURS}h.txt" 2>/dev/null || true

    {
        date --iso-8601=seconds 2>/dev/null || date
        uname -a 2>/dev/null || true
        [[ -r /etc/os-release ]] && cat /etc/os-release
        uptime 2>/dev/null || true
        if command_exists systemd-detect-virt; then
            systemd-detect-virt 2>/dev/null || true
        fi
        if command_exists last; then
            last -x -F 2>/dev/null | head -n 30 || true
        fi
    } >"$BUNDLE_DIR/raw/system.txt"

    {
        free -h 2>/dev/null || true
        printf '\n-- df -h --\n'
        df -h 2>/dev/null || true
        printf '\n-- df -i --\n'
        df -i 2>/dev/null || true
        printf '\n-- vmstat --\n'
        if command_exists vmstat; then
            vmstat 1 3 2>/dev/null || true
        fi
        printf '\n-- top processes (arguments excluded) --\n'
        ps -eo pid,ppid,user,%cpu,%mem,stat,comm --sort=-%cpu 2>/dev/null | head -n 30 || true
        printf '\n-- top memory processes (arguments excluded) --\n'
        ps -eo pid,ppid,user,%cpu,%mem,rss,stat,comm --sort=-%mem 2>/dev/null | head -n 30 || true
    } >"$BUNDLE_DIR/raw/resources.txt"

    {
        printf '%s\n' '-- pressure stall information --'
        for pressure_file in /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io; do
            [[ -r "$pressure_file" ]] || continue
            printf '[%s]\n' "$(basename -- "$pressure_file")"
            cat "$pressure_file"
        done
        printf '\n%s\n' '-- cgroup v2 limits --'
        for cgroup_file in cpu.max cpu.stat memory.current memory.max memory.events pids.current pids.max; do
            [[ -r "/sys/fs/cgroup/$cgroup_file" ]] || continue
            printf '[%s]\n' "$cgroup_file"
            cat "/sys/fs/cgroup/$cgroup_file"
        done
        printf '\n%s\n' '-- file handles --'
        [[ -r /proc/sys/fs/file-nr ]] && cat /proc/sys/fs/file-nr
        printf '\n%s\n' '-- process states --'
        ps -eo pid,ppid,user,stat,etimes,%cpu,%mem,rss,comm 2>/dev/null | awk 'NR == 1 || $4 ~ /^[DZ]/' || true
        printf '\n%s\n' '-- mounts --'
        if command_exists findmnt; then
            findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
        fi
    } >"$BUNDLE_DIR/raw/pressure-and-limits.txt"

    {
        if command_exists ip; then
            ip address show 2>/dev/null || true
        fi
        printf '\n-- routes --\n'
        if command_exists ip; then
            ip route show table all 2>/dev/null || true
        fi
        printf '\n-- link counters --\n'
        if command_exists ip; then
            ip -s link show 2>/dev/null || true
        fi
        printf '\n-- socket summary --\n'
        if command_exists ss; then
            ss -s 2>/dev/null || true
            printf '\n-- TCP states --\n'
            ss -Hant 2>/dev/null | awk '{count[$1]++} END {for (state in count) print state, count[state]}' || true
            printf '\n-- listening TCP/UDP sockets --\n'
            ss -H -lntu 2>/dev/null || true
        fi
        printf '\n-- /proc/net/snmp --\n'
        [[ -r /proc/net/snmp ]] && cat /proc/net/snmp
        printf '\n-- /proc/net/netstat --\n'
        [[ -r /proc/net/netstat ]] && cat /proc/net/netstat
        printf '\n-- /proc/net/softnet_stat --\n'
        [[ -r /proc/net/softnet_stat ]] && cat /proc/net/softnet_stat
        printf '\n-- resolver --\n'
        [[ -r /etc/resolv.conf ]] && cat /etc/resolv.conf
    } >"$BUNDLE_DIR/raw/network.txt"

    {
        if command_exists systemctl && [[ -d /run/systemd/system ]]; then
            systemctl --failed --no-legend --plain 2>/dev/null || true
            local service
            for service in "${SERVICES[@]}"; do
                printf '\n-- %s --\n' "$service"
                systemctl status "$service" --no-pager -l 2>/dev/null || true
            done
        fi
    } >"$BUNDLE_DIR/raw/services.txt"

    if command_exists journalctl; then
        journalctl -b -1 -p warning..alert --no-pager 2>/dev/null >"$BUNDLE_DIR/raw/previous-boot-warnings.txt" || true
    fi
}

write_summary_markdown() {
    local overall="PASS" i
    ((FAIL_COUNT > 0)) && overall="FAIL"
    ((FAIL_COUNT == 0 && WARN_COUNT > 0)) && overall="WARN"
    {
        printf '# VPS Health Check Summary\n\n'
        printf -- '- Host: %s\n' "$host_name"
        printf -- '- Generated: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf -- '- Overall: **%s**\n' "$overall"
        printf -- '- Checks: PASS=%d, WARN=%d, FAIL=%d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
        printf -- '- CPU steal sample: %s%%\n' "$CPU_STEAL_PCT"
        printf -- '- CPU I/O wait sample: %s%%\n' "$CPU_IOWAIT_PCT"
        printf -- '- CPU PSI some avg10: %s%%\n' "${PSI_CPU_AVG10:-unavailable}"
        printf -- '- Memory PSI full avg10: %s%%\n' "${PSI_MEMORY_FULL_AVG10:-unavailable}"
        printf -- '- I/O PSI full avg10: %s%%\n' "${PSI_IO_FULL_AVG10:-unavailable}"
        printf -- '- cgroup throttled-period sample: %s%%\n' "$CGROUP_THROTTLE_PCT"
        printf -- '- TCP lifetime retransmission ratio: %s%%\n' "$TCP_RETRANS_PCT"
        printf -- '- External lost events imported: %s\n' "$PROBE_LOST_COUNT"
        printf -- '- Background anomaly snapshots imported: %s\n\n' "$MONITOR_ANOMALY_COUNT"
        printf '## Recommendations (Chinese)\n\n'
        for ((i = 0; i < ${#RECOMMENDATIONS_ZH[@]}; i++)); do
            printf '%d. %s\n' "$((i + 1))" "${RECOMMENDATIONS_ZH[$i]}"
        done
        printf '\n## Recommendations (English)\n\n'
        for ((i = 0; i < ${#RECOMMENDATIONS_EN[@]}; i++)); do
            printf '%d. %s\n' "$((i + 1))" "${RECOMMENDATIONS_EN[$i]}"
        done
        printf '\n> Automated signals are diagnostic clues, not proof of provider fault or oversubscription. Correlate them with external monitoring and provider host logs.\n'
    } >"$BUNDLE_DIR/summary.md"
}

write_support_ticket() {
    local fact
    {
        printf 'Subject: Request to investigate repeated VPS instability\n\n'
        printf 'Hello,\n\n'
        printf 'My VPS has experienced instability or intermittent network interruptions. I ran a guest-side diagnostic and collected an evidence bundle.\n\n'
        if ((${#TICKET_FACTS[@]} > 0)); then
            printf 'Observed facts:\n'
            for fact in "${TICKET_FACTS[@]}"; do
                printf -- '- %s\n' "$fact"
            done
            printf '\n'
        fi
        printf 'Could you please check the host node and upstream network around the recorded timestamps, including:\n\n'
        printf -- '- Host CPU and storage contention or possible oversubscription\n'
        printf -- '- Virtual NIC and host networking events\n'
        printf -- '- Upstream routing or packet loss\n'
        printf -- '- DDoS attack or mitigation events\n\n'
        printf 'Please let me know what you find on the host side. I can provide the attached report, raw evidence, external probe timestamps, and MTR output.\n\n'
        printf 'Thank you.\n'
        if [[ -n "$PROBE_LOG" ]]; then
            printf '\nOutage records supplied by external monitoring:\n\n'
            tail -n 100 "$PROBE_LOG" 2>/dev/null || true
        fi
    } >"$BUNDLE_DIR/provider-ticket-en.txt"
}

write_review_prompt() {
    cat >"$BUNDLE_DIR/review-prompt.txt" <<'EOF'
请审查这个 VPS 健康检查证据包，目标是判断故障更可能属于：
1. VPS 内部资源或服务问题；
2. 宿主机 CPU/存储争用或疑似超售；
3. 虚拟网卡、上游路由、DDoS 清洗或线路问题；
4. 短时异常进程、cgroup 限额、PSI 压力或 TCP 栈拥堵；
5. 当前证据不足。

请先阅读 summary.md 和 report.txt，再核对 raw/ 下的原始证据；如果存在 process-monitor.log，请把异常快照与外部探针时间线对齐。请按“已确认事实、合理推断、仍缺证据”三层输出，不要仅凭单次 CPU steal、单个 MTR 中间跳丢包或一次 Ping 失败就断定厂商责任。最后列出需要补采的命令、应提交厂商的问题，以及是否建议迁移节点。

注意：不要要求用户提供密码、私钥、API Key 或其他秘密。
EOF
}

finalize_evidence_bundle() {
    collect_raw_evidence
    write_summary_markdown
    write_support_ticket
    write_review_prompt
    plain_log "[INFO] Evidence directory: $BUNDLE_DIR"
    cp -- "$OUTPUT_FILE" "$BUNDLE_DIR/report.txt"

    printf '%s[INFO]%s %s: %s\n' "$C_BLUE" "$C_RESET" "$(tr_text '证据目录' 'Evidence directory')" "$BUNDLE_DIR"
    if command_exists tar && tar -czf "$BUNDLE_ARCHIVE" -C "$(dirname -- "$BUNDLE_DIR")" "$(basename -- "$BUNDLE_DIR")" 2>/dev/null; then
        printf '%s[INFO]%s %s: %s\n' "$C_BLUE" "$C_RESET" "$(tr_text '可分享证据包' 'Shareable evidence bundle')" "$BUNDLE_ARCHIVE"
    else
        printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$(tr_text '未能创建 tar.gz，证据目录仍可直接使用' 'Could not create tar.gz; the evidence directory remains available')"
    fi
}

print_summary() {
    section "$(tr_text '检查结论' 'Summary')"
    local overall
    if ((FAIL_COUNT > 0)); then
        overall="FAIL"
    elif ((WARN_COUNT > 0)); then
        overall="WARN"
    else
        overall="PASS"
    fi
    printf '%sPASS=%d  WARN=%d  FAIL=%d%s\n' "$C_BOLD" "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$C_RESET"
    plain_log "PASS=$PASS_COUNT  WARN=$WARN_COUNT  FAIL=$FAIL_COUNT"
    status_line INFO "$(tr_text '总体状态' 'Overall status'): $overall"
    status_line INFO "$(tr_text '报告文件' 'Report file'): $OUTPUT_FILE"
    status_line INFO "$(tr_text '说明：VPS 内部检查无法单独证明入站线路中断；应与外部探针的 lost/back 时间对照' 'Note: an on-VPS check alone cannot prove inbound route loss; correlate it with external probe lost/back timestamps')"
}

watch_network() {
    [[ -n "$WATCH_DURATION" ]] || return 0
    section "$(tr_text '持续网络监测' 'Continuous network monitoring')"

    if ! command_exists ping; then
        status_line FAIL "$(tr_text '缺少 ping，无法持续监测' 'ping is unavailable; cannot start continuous monitoring')"
        return 1
    fi

    local target="${TARGETS[0]}" start now elapsed=0 state="unknown" new_state
    local checks=0 failures=0 transitions=0
    start="$(date +%s)"
    status_line INFO "$(tr_text '探测目标' 'Probe target'): $target; $(tr_text '间隔' 'interval')=${INTERVAL}s; $(tr_text '持续时间' 'duration')=$([[ "$WATCH_DURATION" == "0" ]] && printf 'until Ctrl+C' || printf '%ss' "$WATCH_DURATION")"

    WATCH_STOP=0
    trap 'WATCH_STOP=1' INT TERM

    while ((WATCH_STOP == 0)); do
        now="$(date +%s)"
        elapsed=$((now - start))
        if ((WATCH_DURATION > 0 && elapsed >= WATCH_DURATION)); then
            break
        fi

        ((checks += 1))
        if ping -n -c 1 -W 2 "$target" >/dev/null 2>&1; then
            new_state="UP"
        else
            new_state="DOWN"
            ((failures += 1))
        fi

        if [[ "$new_state" != "$state" ]]; then
            if [[ "$state" != "unknown" ]]; then
                ((transitions += 1))
            fi
            printf '[EVENT] %s %s %s\n' "$(date '+%F %T %z')" "$target" "$new_state"
            plain_log "[EVENT] $(date '+%F %T %z') $target $new_state"
            state="$new_state"
        fi
        sleep "$INTERVAL"
    done

    trap - INT TERM
    WATCH_FAILURES=$failures
    WATCH_TRANSITIONS=$transitions
    if ((WATCH_STOP > 0)); then
        status_line INFO "$(tr_text '持续监测已由用户停止' 'Continuous monitoring was stopped by the user')"
    fi
    status_line INFO "$(tr_text '持续监测汇总' 'Watch summary'): checks=$checks, failed=$failures, state_changes=$transitions"
}

printf '%sVPS Health Check v%s%s\n' "$C_BOLD" "$VERSION" "$C_RESET"
plain_log "VPS Health Check v$VERSION"
plain_log "Project: $PROJECT_URL"
plain_log "Started: $(date --iso-8601=seconds 2>/dev/null || date)"
plain_log "Command: $0"

kernel_log="$(collect_kernel_log)"
check_system
check_resources
check_pressure_and_limits
check_services_and_reboots
check_kernel_events "$kernel_log"
check_network_interface
check_connectivity
check_network_stack_and_ports
import_probe_log
import_process_monitor_log
watch_network
build_recommendations
print_summary
finalize_evidence_bundle

if ((FAIL_COUNT > 0)); then
    exit 2
elif ((WARN_COUNT > 0)); then
    exit 1
fi
exit 0
