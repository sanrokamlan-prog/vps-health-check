#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/vps-health-check.sh"
TEST_DIR="$(mktemp -d -p /tmp vps-health-check.XXXXXX)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

bash -n "$SCRIPT"
bash -n "$ROOT_DIR/vps-health-monitor.sh"
help_output="$(bash "$SCRIPT" --help)"
[[ "$help_output" == *"--probe-log FILE"* ]]
[[ "$help_output" == *"--monitor-log FILE"* ]]
[[ "$help_output" == *"--udp-port N"* ]]
[[ "$help_output" == *"--http URL"* ]]
[[ "$help_output" == *"--dns DOMAIN"* ]]
monitor_help="$(bash "$ROOT_DIR/vps-health-monitor.sh" --help)"
[[ "$monitor_help" == *"start             后台启动监控"* ]]
[[ "$monitor_help" == *"--network-failures N"* ]]
[[ "$monitor_help" == *"--target HOST"* ]]

set +e
bash "$SCRIPT" --hours invalid >/dev/null 2>&1
invalid_rc=$?
set -e
[[ "$invalid_rc" -eq 2 ]]

set +e
bash "$SCRIPT" --port 70000 >/dev/null 2>&1
invalid_port_rc=$?
set -e
[[ "$invalid_port_rc" -eq 2 ]]

set +e
bash "$SCRIPT" --udp-port 70000 >/dev/null 2>&1
invalid_udp_port_rc=$?
set -e
[[ "$invalid_udp_port_rc" -eq 2 ]]

set +e
bash "$SCRIPT" --http ftp://example.com >/dev/null 2>&1
invalid_http_rc=$?
bash "$SCRIPT" --http https://user:password@example.com >/dev/null 2>&1
credential_http_rc=$?
bash "$SCRIPT" --dns 'bad/domain' >/dev/null 2>&1
invalid_dns_rc=$?
set -e
[[ "$invalid_http_rc" -eq 2 ]]
[[ "$credential_http_rc" -eq 2 ]]
[[ "$invalid_dns_rc" -eq 2 ]]

if [[ "$(uname -s)" == Linux* ]]; then
    symlink_target="$TEST_DIR/symlink-target.log"
    symlink_report="$TEST_DIR/symlink-report.log"
    : >"$symlink_target"
    ln -s "$symlink_target" "$symlink_report"
    set +e
    bash "$SCRIPT" --output "$symlink_report" >/dev/null 2>&1
    symlink_rc=$?
    set -e
    [[ "$symlink_rc" -eq 2 ]]
fi

report="$TEST_DIR/smoke.log"
set +e
bash "$SCRIPT" --target 127.0.0.1 --port 22 --udp-port 53 --tcp example.com:443 --dns localhost --http 'http://127.0.0.1:1/health?token=must-not-leak' --hours 1 --probe-log "$ROOT_DIR/examples/probe.log" --output "$report" --no-color >"$TEST_DIR/stdout.txt" 2>"$TEST_DIR/stderr.txt"
run_rc=$?
set -e
[[ "$run_rc" -ge 0 && "$run_rc" -le 2 ]]
if [[ ! -s "$report" ]]; then
    printf 'snapshot report was not created; stderr follows:\n' >&2
    cat "$TEST_DIR/stderr.txt" >&2
    exit 1
fi
[[ ! -s "$TEST_DIR/stderr.txt" ]]

bundle="${report%.*}-evidence"
[[ -s "$bundle/summary.md" ]]
[[ -s "$bundle/summary.json" ]]
[[ -s "$bundle/timeline.md" ]]
[[ -s "$bundle/timeline.tsv" ]]
[[ -s "$bundle/report.txt" ]]
[[ -s "$bundle/provider-ticket-en.txt" ]]
[[ -s "$bundle/review-prompt.txt" ]]
[[ -s "$bundle/raw/external-probe.log" ]]
[[ -s "$bundle/raw/pressure-and-limits.txt" ]]
[[ -s "$bundle/raw/endpoints.txt" ]]
if command -v getent >/dev/null 2>&1; then
    grep -q 'DNS domain=localhost status=ok' "$bundle/raw/endpoints.txt"
fi
grep -q 'HTTP url=http://127.0.0.1:1/health code=000 status=connection-failed' "$bundle/raw/endpoints.txt"
grep -q $'external-probe\tLOST\t' "$bundle/timeline.tsv"
grep -q $'external-probe\tBACK\t' "$bundle/timeline.tsv"
grep -q '"schema_version": "1.0"' "$bundle/summary.json"
grep -q '"probe_lost_events": 2' "$bundle/summary.json"
if python3 --version >/dev/null 2>&1; then
    python3 -m json.tool "$bundle/summary.json" >/dev/null
elif python --version >/dev/null 2>&1; then
    python -m json.tool "$bundle/summary.json" >/dev/null
fi
if grep -R -q 'must-not-leak' "$bundle"; then
    printf 'URL query secret leaked into evidence bundle\n' >&2
    exit 1
fi
grep -q 'External monitoring recorded 2 unreachable/lost events' "$bundle/provider-ticket-en.txt"
grep -q '自动定责' "$ROOT_DIR/README.md"

monitor_dir="$TEST_DIR/monitor"
mkdir -p "$monitor_dir"
monitor_log="$monitor_dir/monitor.log"
monitor_pid="$monitor_dir/monitor.pid"
bash "$ROOT_DIR/vps-health-monitor.sh" run --duration 2 --interval 1 --load 0 --cooldown 0 --target 127.0.0.1 --network-failures 1 --log "$monitor_log" --pid-file "$monitor_pid" >"$monitor_dir/stdout.txt" 2>"$monitor_dir/stderr.txt"
[[ -s "$monitor_log" ]]
[[ ! -s "$monitor_dir/stderr.txt" ]]
[[ ! -e "$monitor_pid" ]]
grep -q '\[START\]' "$monitor_log"
grep -q '\[ANOMALY\]' "$monitor_log"
grep -q 'SNAPSHOT BEGIN' "$monitor_log"
grep -q '\[STOP\]' "$monitor_log"
if [[ "$(uname -s)" == Linux* ]] && command -v ping >/dev/null 2>&1; then
    grep -q '\[NETWORK\] target=127.0.0.1 state=UP' "$monitor_log"
fi

if [[ "$(uname -s)" == Linux* ]] && command -v ping >/dev/null 2>&1; then
    network_log="$monitor_dir/network-down.log"
    network_pid="$monitor_dir/network-down.pid"
    bash "$ROOT_DIR/vps-health-monitor.sh" run --duration 2 --interval 1 --load 99999 --target 192.0.2.1 --network-failures 1 --log "$network_log" --pid-file "$network_pid" >"$monitor_dir/network-down.out" 2>"$monitor_dir/network-down.err"
    grep -q 'state=DOWN' "$network_log"
    grep -q '\[NETWORK-ANOMALY\]' "$network_log"
    grep -q 'NETWORK SNAPSHOT BEGIN' "$network_log"
fi

renamed_monitor="$monitor_dir/renamed-monitor.sh"
renamed_log="$monitor_dir/renamed.log"
renamed_pid="$monitor_dir/renamed.pid"
cp "$ROOT_DIR/vps-health-monitor.sh" "$renamed_monitor"
bash "$renamed_monitor" start --duration 30 --interval 1 --load 0 --cooldown 60 --target 127.0.0.1 --network-failures 1 --log "$renamed_log" --pid-file "$renamed_pid" >"$monitor_dir/start.txt"
grep -q 'started: PID' "$monitor_dir/start.txt"
bash "$renamed_monitor" status --log "$renamed_log" --pid-file "$renamed_pid" >"$monitor_dir/status.txt"
grep -q 'running: PID' "$monitor_dir/status.txt"
bash "$renamed_monitor" stop --log "$renamed_log" --pid-file "$renamed_pid" >"$monitor_dir/stop.txt"
grep -q 'stopped' "$monitor_dir/stop.txt"
[[ ! -e "$renamed_pid" ]]

monitor_report="$TEST_DIR/monitor-import.log"
set +e
bash "$SCRIPT" --target 127.0.0.1 --hours 1 --monitor-log "$monitor_log" --output "$monitor_report" --no-color >"$TEST_DIR/monitor-import.out" 2>"$TEST_DIR/monitor-import.err"
monitor_import_rc=$?
set -e
[[ "$monitor_import_rc" -ge 0 && "$monitor_import_rc" -le 2 ]]
[[ ! -s "$TEST_DIR/monitor-import.err" ]]
monitor_bundle="${monitor_report%.*}-evidence"
[[ -s "$monitor_bundle/raw/process-monitor.log" ]]
grep -q $'background-monitor\tANOMALY\t' "$monitor_bundle/timeline.tsv"
grep -q 'background monitor captured' "$monitor_bundle/provider-ticket-en.txt"

watch_report="$TEST_DIR/watch.log"
set +e
bash "$SCRIPT" --target 127.0.0.1 --hours 1 --watch 2 --interval 1 --output "$watch_report" --no-color >"$TEST_DIR/watch-stdout.txt" 2>"$TEST_DIR/watch-stderr.txt"
watch_rc=$?
set -e
[[ "$watch_rc" -ge 0 && "$watch_rc" -le 2 ]]
[[ ! -s "$TEST_DIR/watch-stderr.txt" ]]
grep -q '\[EVENT\]' "$watch_report"
grep -q '持续监测汇总' "$watch_report"
grep -q $'foreground-watch\t' "${watch_report%.*}-evidence/timeline.tsv"

printf 'smoke tests passed\n'
