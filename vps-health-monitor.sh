#!/usr/bin/env bash

# Lightweight background process and pressure monitor for VPS troubleshooting.
# It records process names and resource counters, never full command arguments.

set -uo pipefail

VERSION="1.3.0"
COMMAND="${1:-help}"
[[ $# -gt 0 ]] && shift
if [[ "$COMMAND" == "-h" || "$COMMAND" == "--help" ]]; then
    COMMAND="help"
fi

INTERVAL=5
DURATION=0
CPU_THRESHOLD=80
MEMORY_THRESHOLD=50
LOAD_THRESHOLD=150
COOLDOWN=60
MAX_LOG_MB=10
NETWORK_FAILURE_THRESHOLD=2
STOP_REQUESTED=0
TARGETS=("1.1.1.1" "8.8.8.8")
TARGETS_OVERRIDDEN=0
NETWORK_DOWN_COUNT=0
NETWORK_STATE="UNKNOWN"

if ((EUID == 0)); then
    STATE_DIR="/var/log/vps-health-monitor"
    PID_FILE="/run/vps-health-monitor.pid"
else
    STATE_DIR="${HOME:-/tmp}/.local/state/vps-health-monitor"
    PID_FILE="$STATE_DIR/monitor.pid"
fi
LOG_FILE="$STATE_DIR/monitor.log"
SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
SCRIPT_BASENAME="$(basename -- "$SCRIPT_PATH")"

declare -A LAST_ALERT=()
declare -A TARGET_STATE=()
declare -A TARGET_FAILURE_STREAK=()

usage() {
    cat <<'EOF'
VPS Health Monitor - 后台异常进程与资源压力记录器

用法：
  sudo bash vps-health-monitor.sh start [选项]
  sudo bash vps-health-monitor.sh status [选项]
  sudo bash vps-health-monitor.sh stop [选项]
  sudo bash vps-health-monitor.sh run [选项]

命令：
  start             后台启动监控
  status            查看后台监控状态
  stop              停止后台监控
  run               前台运行，适合调试或由其他服务管理

选项：
  --interval N      采样间隔秒数（默认：5）
  --duration N      运行秒数，0 表示持续运行（默认：0）
  --cpu N           单进程 CPU 告警阈值百分比（默认：80）
  --memory N        单进程内存告警阈值百分比（默认：50）
  --load N          系统 Load/CPU 告警阈值百分比（默认：150）
  --cooldown N      同类异常抓取冷却秒数（默认：60）
  --max-log-mb N    日志轮转大小 MiB（默认：10，仅保留 .1）
  --target HOST      后台网络探测目标，可重复使用（默认：1.1.1.1、8.8.8.8）
  --network-failures N 连续失败 N 次后记录 DOWN（默认：2）
  --log FILE        自定义日志文件
  --pid-file FILE   自定义 PID 文件
  -h, --help        显示帮助

示例：
  sudo bash vps-health-monitor.sh start
  sudo bash vps-health-monitor.sh start --interval 3 --cpu 70 --max-log-mb 20
  sudo bash vps-health-monitor.sh start --target 1.1.1.1 --target 8.8.8.8 --network-failures 2
  sudo bash vps-health-monitor.sh status
  sudo bash vps-health-monitor.sh stop
EOF
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

while (($# > 0)); do
    case "$1" in
        --interval)
            [[ $# -ge 2 ]] || { echo "--interval requires a value" >&2; exit 2; }
            INTERVAL="$2"
            shift 2
            ;;
        --duration)
            [[ $# -ge 2 ]] || { echo "--duration requires a value" >&2; exit 2; }
            DURATION="$2"
            shift 2
            ;;
        --cpu)
            [[ $# -ge 2 ]] || { echo "--cpu requires a value" >&2; exit 2; }
            CPU_THRESHOLD="$2"
            shift 2
            ;;
        --memory)
            [[ $# -ge 2 ]] || { echo "--memory requires a value" >&2; exit 2; }
            MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        --load)
            [[ $# -ge 2 ]] || { echo "--load requires a value" >&2; exit 2; }
            LOAD_THRESHOLD="$2"
            shift 2
            ;;
        --cooldown)
            [[ $# -ge 2 ]] || { echo "--cooldown requires a value" >&2; exit 2; }
            COOLDOWN="$2"
            shift 2
            ;;
        --max-log-mb)
            [[ $# -ge 2 ]] || { echo "--max-log-mb requires a value" >&2; exit 2; }
            MAX_LOG_MB="$2"
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
        --network-failures)
            [[ $# -ge 2 ]] || { echo "--network-failures requires a value" >&2; exit 2; }
            NETWORK_FAILURE_THRESHOLD="$2"
            shift 2
            ;;
        --log)
            [[ $# -ge 2 ]] || { echo "--log requires a value" >&2; exit 2; }
            LOG_FILE="$2"
            shift 2
            ;;
        --pid-file)
            [[ $# -ge 2 ]] || { echo "--pid-file requires a value" >&2; exit 2; }
            PID_FILE="$2"
            shift 2
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

for numeric in "$INTERVAL" "$DURATION" "$CPU_THRESHOLD" "$MEMORY_THRESHOLD" "$LOAD_THRESHOLD" "$COOLDOWN" "$MAX_LOG_MB" "$NETWORK_FAILURE_THRESHOLD"; do
    is_uint "$numeric" || { echo "Monitor options must be non-negative integers" >&2; exit 2; }
done
((INTERVAL >= 1)) || { echo "--interval must be at least 1" >&2; exit 2; }
((MAX_LOG_MB >= 1)) || { echo "--max-log-mb must be at least 1" >&2; exit 2; }
((NETWORK_FAILURE_THRESHOLD >= 1)) || { echo "--network-failures must be at least 1" >&2; exit 2; }
for target in "${TARGETS[@]}"; do
    if [[ ! "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
        echo "--target must use a valid IP address or hostname: $target" >&2
        exit 2
    fi
done

if [[ "$COMMAND" != "help" ]]; then
    mkdir -p -- "$(dirname -- "$LOG_FILE")" "$(dirname -- "$PID_FILE")" || {
        echo "Cannot create monitor state directory" >&2
        exit 2
    }
    umask 077
    if [[ -L "$LOG_FILE" || -L "$PID_FILE" ]]; then
        echo "Refusing symbolic-link log or PID path" >&2
        exit 2
    fi
fi

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

pid_is_monitor() {
    local pid="$1" cmdline=""
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    if [[ -r "/proc/$pid/cmdline" ]]; then
        cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
        [[ "$cmdline" == *"$SCRIPT_BASENAME"* ]]
    else
        return 0
    fi
}

running_pid() {
    local pid=""
    [[ -r "$PID_FILE" ]] || return 1
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    pid_is_monitor "$pid" || return 1
    printf '%s' "$pid"
}

log_size_bytes() {
    if command_exists stat; then
        stat -c '%s' "$LOG_FILE" 2>/dev/null || printf '0'
    else
        wc -c <"$LOG_FILE" 2>/dev/null | tr -d ' ' || printf '0'
    fi
}

rotate_log_if_needed() {
    [[ -f "$LOG_FILE" ]] || return 0
    local bytes
    bytes="$(log_size_bytes)"
    bytes="${bytes:-0}"
    if ((bytes >= MAX_LOG_MB * 1024 * 1024)); then
        mv -f -- "$LOG_FILE" "$LOG_FILE.1"
    fi
}

log_line() {
    local level="$1"
    shift
    rotate_log_if_needed
    printf '[%s] [%s] %s\n' "$(date '+%F %T %z')" "$level" "$*" >>"$LOG_FILE"
}

psi_avg10() {
    local file="$1" mode="$2"
    awk -v wanted="$mode" '$1 == wanted {for (i = 2; i <= NF; i++) if ($i ~ /^avg10=/) {split($i, pair, "="); print pair[2]; exit}}' "$file" 2>/dev/null
}

decimal_ge() {
    awk -v value="${1:-0}" -v threshold="$2" 'BEGIN {exit !(value + 0 >= threshold + 0)}'
}

should_alert() {
    local key="$1" now="$2" last
    last="${LAST_ALERT[$key]:-0}"
    if ((now - last >= COOLDOWN)); then
        LAST_ALERT["$key"]="$now"
        return 0
    fi
    return 1
}

capture_snapshot() {
    local reason="$1"
    rotate_log_if_needed
    {
        printf '[%s] [ANOMALY] %s\n' "$(date '+%F %T %z')" "$reason"
        printf '%s\n' '----- SNAPSHOT BEGIN -----'
        printf '%s\n' '-- uptime --'
        uptime 2>/dev/null || true
        printf '%s\n' '-- memory --'
        free -h 2>/dev/null || true
        printf '%s\n' '-- top CPU processes (arguments excluded) --'
        ps -eo pid,ppid,user,stat,etimes,%cpu,%mem,rss,comm --sort=-%cpu 2>/dev/null | head -n 16 || true
        printf '%s\n' '-- top memory processes (arguments excluded) --'
        ps -eo pid,ppid,user,stat,etimes,%cpu,%mem,rss,comm --sort=-%mem 2>/dev/null | head -n 16 || true
        if command_exists vmstat; then
            printf '%s\n' '-- vmstat --'
            vmstat 1 3 2>/dev/null || true
        fi
        if command_exists ss; then
            printf '%s\n' '-- socket summary --'
            ss -s 2>/dev/null || true
        fi
        if [[ -d /proc/pressure ]]; then
            printf '%s\n' '-- pressure stall information --'
            for pressure_file in /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io; do
                [[ -r "$pressure_file" ]] || continue
                printf '[%s]\n' "$(basename -- "$pressure_file")"
                cat "$pressure_file"
            done
        fi
        if command_exists journalctl; then
            printf '%s\n' '-- recent kernel warnings --'
            journalctl -k -p warning..alert -n 25 --no-pager 2>/dev/null || true
        fi
        printf '%s\n' '----- SNAPSHOT END -----'
    } >>"$LOG_FILE"
}

default_interface() {
    command_exists ip || return 0
    ip route show default 2>/dev/null | awk 'NR == 1 {for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}'
}

interface_bytes() {
    local iface="$1" rx=0 tx=0
    [[ -n "$iface" && -r "/sys/class/net/$iface/statistics/rx_bytes" ]] || {
        printf '0 0'
        return
    }
    rx="$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || printf '0')"
    tx="$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || printf '0')"
    printf '%s %s' "$rx" "$tx"
}

capture_network_snapshot() {
    local level="$1" reason="$2" iface route_target
    local -a route_command
    iface="$(default_interface)"
    rotate_log_if_needed
    {
        printf '[%s] [%s] %s\n' "$(date '+%F %T %z')" "$level" "$reason"
        printf '%s\n' '----- NETWORK SNAPSHOT BEGIN -----'
        if command_exists ip; then
            printf '%s\n' '-- addresses --'
            ip -brief address show 2>/dev/null || true
            printf '%s\n' '-- IPv4 routes --'
            ip route show table all 2>/dev/null || true
            printf '%s\n' '-- IPv6 routes --'
            ip -6 route show table all 2>/dev/null || true
            printf '%s\n' '-- target routes --'
            for route_target in "${TARGETS[@]}"; do
                route_command=(-4)
                [[ "$route_target" == *:* ]] && route_command=(-6)
                printf '[%s]\n' "$route_target"
                ip "${route_command[@]}" route get "$route_target" 2>/dev/null || true
            done
            printf '%s\n' '-- link counters --'
            ip -s link show 2>/dev/null || true
        fi
        if command_exists ss; then
            printf '%s\n' '-- socket summary --'
            ss -s 2>/dev/null || true
            printf '%s\n' '-- TCP states --'
            ss -Hant 2>/dev/null | awk '{count[$1]++} END {for (state in count) print state, count[state]}' || true
        fi
        printf '%s\n' '-- conntrack --'
        [[ -r /proc/sys/net/netfilter/nf_conntrack_count ]] && cat /proc/sys/net/netfilter/nf_conntrack_count
        [[ -r /proc/sys/net/netfilter/nf_conntrack_max ]] && cat /proc/sys/net/netfilter/nf_conntrack_max
        if command_exists tc && [[ -n "$iface" ]]; then
            printf '%s\n' '-- qdisc --'
            tc -s qdisc show dev "$iface" 2>/dev/null || true
        fi
        if command_exists resolvectl; then
            printf '%s\n' '-- resolver status --'
            resolvectl status 2>/dev/null || true
        else
            printf '%s\n' '-- resolv.conf --'
            [[ -r /etc/resolv.conf ]] && cat /etc/resolv.conf
        fi
        if command_exists journalctl; then
            printf '%s\n' '-- recent kernel warnings --'
            journalctl -k -p warning..alert -n 40 --no-pager 2>/dev/null || true
        fi
        printf '%s\n' '----- NETWORK SNAPSHOT END -----'
    } >>"$LOG_FILE"
}

ping_probe() {
    local target="$1" output rtt
    output="$(ping -n -c 1 -W 1 "$target" 2>&1)" || return 1
    rtt="$(printf '%s\n' "$output" | sed -nE 's/.*time[=<]([0-9]+([.][0-9]+)?).*/\1/p' | tail -n 1)"
    printf '%s' "${rtt:-unknown}"
}

monitor_network_targets() {
    command_exists ping || return 0
    local target state failures rtt new_network_state total_targets
    NETWORK_DOWN_COUNT=0
    total_targets=${#TARGETS[@]}
    for target in "${TARGETS[@]}"; do
        state="${TARGET_STATE[$target]:-UNKNOWN}"
        failures="${TARGET_FAILURE_STREAK[$target]:-0}"
        if rtt="$(ping_probe "$target")"; then
            TARGET_FAILURE_STREAK["$target"]=0
            if [[ "$state" == "DOWN" ]]; then
                TARGET_STATE["$target"]="UP"
                log_line EVENT "scope=target target=$target state=UP previous=DOWN rtt_ms=$rtt"
            elif [[ "$state" == "UNKNOWN" ]]; then
                TARGET_STATE["$target"]="UP"
                log_line NETWORK "target=$target state=UP initial=1 rtt_ms=$rtt"
            fi
        else
            failures=$((failures + 1))
            TARGET_FAILURE_STREAK["$target"]="$failures"
            if ((failures >= NETWORK_FAILURE_THRESHOLD)); then
                ((NETWORK_DOWN_COUNT += 1))
                if [[ "$state" != "DOWN" ]]; then
                    TARGET_STATE["$target"]="DOWN"
                    log_line EVENT "scope=target target=$target state=DOWN consecutive_failures=$failures"
                fi
            elif [[ "$state" == "UP" ]]; then
                log_line NETWORK "target=$target state=SUSPECT consecutive_failures=$failures"
            fi
        fi
    done

    if ((NETWORK_DOWN_COUNT == total_targets)); then
        new_network_state="DOWN"
    elif ((NETWORK_DOWN_COUNT > 0)); then
        new_network_state="DEGRADED"
    else
        new_network_state="UP"
    fi
    if [[ "$new_network_state" != "$NETWORK_STATE" ]]; then
        log_line EVENT "scope=network state=$new_network_state previous=$NETWORK_STATE down_targets=$NETWORK_DOWN_COUNT total_targets=$total_targets"
        if [[ "$new_network_state" == "DOWN" ]]; then
            capture_network_snapshot NETWORK-ANOMALY "all configured targets are unreachable"
        elif [[ "$NETWORK_STATE" == "DOWN" ]]; then
            capture_network_snapshot NETWORK-RECOVERY "network recovered to $new_network_state"
        fi
        NETWORK_STATE="$new_network_state"
    fi
}

read_cpu_sample() {
    local _cpu user nice system idle iowait irq softirq steal _guest _guest_nice
    read -r _cpu user nice system idle iowait irq softirq steal _guest _guest_nice < /proc/stat
    printf '%s %s %s %s\n' "$((user + nice + system + idle + iowait + irq + softirq + steal))" "$idle" "$iowait" "$steal"
}

monitor_loop() {
    local start now last_heartbeat=0 cpu_before cpu_after
    local total_1 idle_1 iowait_1 steal_1 total_2 idle_2 iowait_2 steal_2 delta_total
    local busy_pct=0 steal_pct=0 iowait_pct=0 load1 cpus load_pct mem_total mem_available mem_pct
    local psi_cpu=0 psi_mem=0 psi_io=0 d_count=0 z_count=0 reasons="" process_reasons=""
    local pid _ppid user stat etimes cpu mem rss comm cpu_integer mem_integer
    local iface rx_before tx_before rx_after tx_after rx_rate=0 tx_rate=0 targets_csv

    printf '%s\n' "$$" >"$PID_FILE"
    start="$(date +%s)"
    targets_csv="$(IFS=,; printf '%s' "${TARGETS[*]}")"
    log_line START "VPS Health Monitor v$VERSION pid=$$ interval=${INTERVAL}s duration=${DURATION}s cpu=${CPU_THRESHOLD}% memory=${MEMORY_THRESHOLD}% load=${LOAD_THRESHOLD}% targets=$targets_csv network_failures=$NETWORK_FAILURE_THRESHOLD"
    if ! command_exists ping; then
        log_line WARN "ping is unavailable; background network monitoring is disabled"
    fi

    while ((STOP_REQUESTED == 0)); do
        now="$(date +%s)"
        if ((DURATION > 0 && now - start >= DURATION)); then
            break
        fi

        cpu_before="$(read_cpu_sample)"
        read -r total_1 idle_1 iowait_1 steal_1 <<<"$cpu_before"
        iface="$(default_interface)"
        read -r rx_before tx_before <<<"$(interface_bytes "$iface")"
        sleep "$INTERVAL"
        cpu_after="$(read_cpu_sample)"
        read -r total_2 idle_2 iowait_2 steal_2 <<<"$cpu_after"
        read -r rx_after tx_after <<<"$(interface_bytes "$iface")"
        if ((rx_after >= rx_before && tx_after >= tx_before)); then
            rx_rate=$(((rx_after - rx_before) / INTERVAL))
            tx_rate=$(((tx_after - tx_before) / INTERVAL))
        else
            rx_rate=0
            tx_rate=0
        fi
        delta_total=$((total_2 - total_1))
        if ((delta_total > 0)); then
            busy_pct=$(((delta_total - (idle_2 - idle_1) - (iowait_2 - iowait_1)) * 100 / delta_total))
            steal_pct=$(((steal_2 - steal_1) * 100 / delta_total))
            iowait_pct=$(((iowait_2 - iowait_1) * 100 / delta_total))
        fi

        cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
        [[ "$cpus" =~ ^[0-9]+$ ]] && ((cpus > 0)) || cpus=1
        load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || printf '0')"
        load_pct="$(awk -v load_value="$load1" -v cpu_count="$cpus" 'BEGIN {printf "%d", load_value * 100 / cpu_count}')"
        mem_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        mem_available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
        mem_pct=0
        ((mem_total > 0)) && mem_pct=$(((mem_total - mem_available) * 100 / mem_total))
        psi_cpu="$(psi_avg10 /proc/pressure/cpu some)"
        psi_mem="$(psi_avg10 /proc/pressure/memory full)"
        psi_io="$(psi_avg10 /proc/pressure/io full)"
        psi_cpu="${psi_cpu:-0}"
        psi_mem="${psi_mem:-0}"
        psi_io="${psi_io:-0}"
        d_count="$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^D/ {count++} END {print count + 0}')"
        z_count="$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^Z/ {count++} END {print count + 0}')"

        reasons=""
        ((load_pct >= LOAD_THRESHOLD)) && reasons+=" load=${load_pct}%"
        ((mem_pct >= 90)) && reasons+=" memory=${mem_pct}%"
        ((steal_pct >= 10)) && reasons+=" steal=${steal_pct}%"
        ((iowait_pct >= 15)) && reasons+=" iowait=${iowait_pct}%"
        ((d_count > 0)) && reasons+=" D-state=$d_count"
        ((z_count >= 5)) && reasons+=" zombies=$z_count"
        decimal_ge "$psi_cpu" 40 && reasons+=" cpu-psi=${psi_cpu}%"
        decimal_ge "$psi_mem" 5 && reasons+=" memory-psi-full=${psi_mem}%"
        decimal_ge "$psi_io" 5 && reasons+=" io-psi-full=${psi_io}%"

        now="$(date +%s)"
        if [[ -n "$reasons" ]] && should_alert system "$now"; then
            capture_snapshot "system pressure:$reasons busy=${busy_pct}%"
        fi

        process_reasons=""
        while read -r pid _ppid user stat etimes cpu mem rss comm; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            cpu_integer="${cpu%.*}"
            mem_integer="${mem%.*}"
            cpu_integer="${cpu_integer:-0}"
            mem_integer="${mem_integer:-0}"
            if ((cpu_integer >= CPU_THRESHOLD || mem_integer >= MEMORY_THRESHOLD)); then
                process_reasons+=" pid=$pid user=$user stat=$stat age=${etimes}s cpu=${cpu}% mem=${mem}% rss=${rss}KiB comm=$comm;"
            fi
        done < <(ps -eo pid=,ppid=,user=,stat=,etimes=,%cpu=,%mem=,rss=,comm= --sort=-%cpu 2>/dev/null | head -n 30)

        if [[ -n "$process_reasons" ]] && should_alert process "$now"; then
            capture_snapshot "process threshold exceeded:$process_reasons"
        fi

        monitor_network_targets

        if ((now - last_heartbeat >= 300)); then
            log_line HEARTBEAT "load=${load_pct}% busy=${busy_pct}% memory=${mem_pct}% steal=${steal_pct}% iowait=${iowait_pct}% psi_cpu=${psi_cpu}% psi_mem_full=${psi_mem}% psi_io_full=${psi_io}% iface=${iface:-none} rx_Bps=$rx_rate tx_Bps=$tx_rate network_down=$NETWORK_DOWN_COUNT"
            last_heartbeat=$now
        fi
    done
}

# Called indirectly by traps while run mode owns the PID file.
# shellcheck disable=SC2317
finish_run() {
    log_line STOP "VPS Health Monitor stopped pid=$$"
    if [[ -r "$PID_FILE" ]] && [[ "$(cat "$PID_FILE" 2>/dev/null || true)" == "$$" ]]; then
        rm -f -- "$PID_FILE"
    fi
}

case "$COMMAND" in
    start)
        if pid="$(running_pid)"; then
            echo "Monitor is already running: PID $pid"
            echo "Log: $LOG_FILE"
            exit 1
        fi
        target_args=()
        for target in "${TARGETS[@]}"; do
            target_args+=(--target "$target")
        done
        # The child and nohup diagnostics intentionally append to one log; neither reads it.
        # shellcheck disable=SC2094
        nohup bash "$SCRIPT_PATH" run \
            --interval "$INTERVAL" \
            --duration "$DURATION" \
            --cpu "$CPU_THRESHOLD" \
            --memory "$MEMORY_THRESHOLD" \
            --load "$LOAD_THRESHOLD" \
            --network-failures "$NETWORK_FAILURE_THRESHOLD" \
            --cooldown "$COOLDOWN" \
            --max-log-mb "$MAX_LOG_MB" \
            --log "$LOG_FILE" \
            --pid-file "$PID_FILE" \
            "${target_args[@]}" \
            >>"$LOG_FILE" 2>&1 &
        child_pid=$!
        sleep 1
        if pid_is_monitor "$child_pid"; then
            echo "VPS Health Monitor started: PID $child_pid"
            echo "Log: $LOG_FILE"
            printf 'Stop: sudo bash %q stop --log %q --pid-file %q\n' "$SCRIPT_PATH" "$LOG_FILE" "$PID_FILE"
        else
            echo "Monitor failed to start; check: $LOG_FILE" >&2
            exit 1
        fi
        ;;
    status)
        if pid="$(running_pid)"; then
            echo "VPS Health Monitor is running: PID $pid"
            echo "Log: $LOG_FILE"
        else
            echo "VPS Health Monitor is not running"
            [[ -e "$PID_FILE" ]] && echo "Stale PID file: $PID_FILE"
            exit 1
        fi
        ;;
    stop)
        if pid="$(running_pid)"; then
            kill -TERM "$pid"
            for _attempt in 1 2 3 4 5 6 7 8 9 10; do
                pid_is_monitor "$pid" || break
                sleep 1
            done
            if pid_is_monitor "$pid"; then
                echo "Monitor did not stop after 10 seconds: PID $pid" >&2
                exit 1
            fi
            echo "VPS Health Monitor stopped"
        else
            echo "VPS Health Monitor is not running"
            [[ -e "$PID_FILE" ]] && rm -f -- "$PID_FILE"
        fi
        ;;
    run)
        if pid="$(running_pid)" && [[ "$pid" != "$$" ]]; then
            echo "Monitor is already running: PID $pid" >&2
            exit 1
        fi
        trap 'STOP_REQUESTED=1' INT TERM
        trap finish_run EXIT
        monitor_loop
        ;;
    help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        usage >&2
        exit 2
        ;;
esac
