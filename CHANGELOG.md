# Changelog

All notable changes are documented in this file.

## 1.2.0 - 2026-07-26

- Changed lifetime NIC, TCP retransmission, listen/backlog, and softnet counters to informational context; health findings now use deltas captured during the current check.
- Added conditional IPv6 egress checks and repeatable `--udp-port` local UDP binding checks.
- Reduced reboot false positives by treating recent boot time as timeline evidence unless it correlates with an outage.
- Split pressure, cgroup, process, filesystem, network-counter, socket, and port checks into focused internal functions while preserving one-file deployment.
- Hardened root-run output, evidence, monitor log, and PID paths against symbolic-link overwrite risks and applied private default permissions.
- Fixed background monitor control when the script is renamed, retained startup errors in the monitor log, and safely quoted generated stop commands.
- Expanded smoke coverage for UDP validation, symbolic-link rejection, and renamed monitor lifecycle control.

## 1.1.0 - 2026-07-26

- Added `vps-health-monitor.sh` with foreground/background control, PID-safe `start`/`status`/`stop`, threshold cooldown, and size-based log rotation.
- Added automatic anomaly snapshots for runaway CPU/memory processes, system load, CPU steal, I/O wait, PSI, D-state/zombie processes, socket summary, `vmstat`, and kernel warnings.
- Added Linux PSI, cgroup CPU quota/throttling, cgroup memory/PID limits, D/Z process state, file-handle usage, root read-only detection, and recent-reboot diagnostics.
- Added TCP retransmission, SYN-RECV, listen/backlog drop, softnet, NIC counter delta, local listener, and remote TCP target checks.
- Added `--monitor-log`, `--port`, and `--tcp` evidence workflows.
- Expanded raw evidence, provider facts, recommendations, tests, and Chinese/English documentation.

## 1.0.0 - 2026-07-25

- Added read-only system, resource, service, kernel, storage, NIC, routing, DNS, HTTPS, and packet-loss checks.
- Added CPU steal and I/O wait sampling for host-contention investigation.
- Added continuous `UP/DOWN` event monitoring.
- Added external `lost/back` probe-log import.
- Added contextual recommendations in Chinese and English.
- Added evidence bundle, provider ticket, and administrator/AI review prompt generation.
- Added Chinese and English documentation, tests, and CI.
