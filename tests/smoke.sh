#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/vps-health-check.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

bash -n "$SCRIPT"
help_output="$(bash "$SCRIPT" --help)"
[[ "$help_output" == *"--probe-log FILE"* ]]

set +e
bash "$SCRIPT" --hours invalid >/dev/null 2>&1
invalid_rc=$?
set -e
[[ "$invalid_rc" -eq 2 ]]

report="$TEST_DIR/smoke.log"
set +e
bash "$SCRIPT" --target 127.0.0.1 --hours 1 --probe-log "$ROOT_DIR/examples/probe.log" --output "$report" --no-color >"$TEST_DIR/stdout.txt" 2>"$TEST_DIR/stderr.txt"
run_rc=$?
set -e
[[ "$run_rc" -ge 0 && "$run_rc" -le 2 ]]
[[ -s "$report" ]]
[[ ! -s "$TEST_DIR/stderr.txt" ]]

bundle="${report%.*}-evidence"
[[ -s "$bundle/summary.md" ]]
[[ -s "$bundle/report.txt" ]]
[[ -s "$bundle/provider-ticket-en.txt" ]]
[[ -s "$bundle/review-prompt.txt" ]]
[[ -s "$bundle/raw/external-probe.log" ]]
grep -q 'External monitoring recorded 2 unreachable/lost events' "$bundle/provider-ticket-en.txt"
grep -q '自动定责' "$ROOT_DIR/README.md"

watch_report="$TEST_DIR/watch.log"
set +e
bash "$SCRIPT" --target 127.0.0.1 --hours 1 --watch 2 --interval 1 --output "$watch_report" --no-color >"$TEST_DIR/watch-stdout.txt" 2>"$TEST_DIR/watch-stderr.txt"
watch_rc=$?
set -e
[[ "$watch_rc" -ge 0 && "$watch_rc" -le 2 ]]
[[ ! -s "$TEST_DIR/watch-stderr.txt" ]]
grep -q '\[EVENT\]' "$watch_report"
grep -q '持续监测汇总' "$watch_report"

printf 'smoke tests passed\n'
