# VPS Health Check

> A read-only VPS diagnostic and evidence-packaging tool, not another benchmark script.

[中文](README.md) | [Diagnostic guide](docs/diagnosis-guide.md) | [Changelog](CHANGELOG.md)

It checks guest resources, OOM events, PSI pressure, cgroup quotas/throttling, process states, kernel and storage errors, NIC state, TCP/UDP stack health, routing, packet loss, DNS, IPv4/IPv6 HTTPS, systemd units, CPU steal, and I/O wait. It then generates actionable recommendations plus material that can be reviewed by a VPS provider, an experienced administrator, or an AI assistant.

## Quick start

```bash
curl -fsSL https://github.com/sanrokamlan-prog/vps-health-check/releases/download/v1.2.0/vps-health-check.sh -o /tmp/vps-health-check.sh && sudo bash /tmp/vps-health-check.sh
```

Useful examples:

```bash
# Check selected services and add MTR evidence
sudo bash /tmp/vps-health-check.sh --service xray --service nginx --mtr

# Watch connectivity for one hour
sudo bash /tmp/vps-health-check.sh --watch 3600 --interval 5

# Import lost/back timestamps from external monitoring
sudo bash /tmp/vps-health-check.sh --probe-log /root/probe.log --mtr

# Check local TCP/UDP listeners and remote TCP targets
sudo bash /tmp/vps-health-check.sh --port 443 --udp-port 53 --tcp example.com:443

# Check a business hostname and HTTP(S) endpoint timings
sudo bash /tmp/vps-health-check.sh --dns example.com --http https://example.com/health

# English CLI output
sudo bash /tmp/vps-health-check.sh --lang en
```

## Background abnormal-process monitor

One-off checks can miss brief CPU spikes, D-state stalls, pressure events, or runaway processes. The companion monitor writes a snapshot only when thresholds are exceeded and can run unattended in the background:

```bash
curl -fsSL https://github.com/sanrokamlan-prog/vps-health-check/releases/download/v1.2.0/vps-health-monitor.sh -o /tmp/vps-health-monitor.sh

sudo bash /tmp/vps-health-monitor.sh start \
  --interval 3 --cpu 70 --memory 40 --load 120 \
  --cooldown 60 --max-log-mb 20

sudo bash /tmp/vps-health-monitor.sh status
sudo bash /tmp/vps-health-monitor.sh stop
```

When an anomaly occurs, it records Top CPU/memory processes without full command arguments, D/Z state, Load, steal, iowait, PSI, `vmstat`, socket summary, and recent kernel warnings. Root defaults to `/var/log/vps-health-monitor/monitor.log`, rotates the log at the configured size, and does not install a system service or persist across reboot.

Import that log into a later evidence bundle:

```bash
sudo bash /tmp/vps-health-check.sh --monitor-log /var/log/vps-health-monitor/monitor.log
```

## Generated evidence

The script creates a report and a compressed evidence bundle containing:

- `summary.md`: findings and recommendations in Chinese and English;
- `report.txt`: the complete console report without ANSI colors;
- `provider-ticket-en.txt`: an editable English provider ticket;
- `review-prompt.txt`: a structured prompt for administrator or AI review;
- `raw/`: system, pressure/limits, resource, network, service, kernel, probe, monitor, and optional MTR evidence.

## Interpreting host-contention signals

Elevated CPU steal can indicate host CPU contention or oversubscription. Elevated I/O wait with little guest-side disk activity can indicate host storage contention. Neither signal proves provider fault from a single sample. Repeat the check while the guest is idle, correlate it with external outage timestamps, and ask the provider to inspect host-side logs.

External monitoring outages with no matching guest OOM, reboot, stopped service, kernel lockup, or NIC link-down event are a valid reason to escalate host-node, upstream-routing, or DDoS-mitigation investigation. They still do not prove one specific cause.

Lifetime NIC, TCP, listen-queue, and softnet counters are preserved as context, but only growth during the current check raises a health finding. This avoids treating an old, already-resolved event as a current outage. IPv6 egress is tested only when both a global IPv6 address and a default IPv6 route exist.

Repeatable `--http` checks report HTTP status plus DNS, connect, TLS, first-byte, and total timing, and inspect HTTPS certificate expiry. Repeatable `--dns` checks validate the actual business hostnames you care about. URL query strings and fragments are omitted from evidence, and embedded URL credentials are rejected.

## Safety and privacy

The script does not change packages, services, routes, or firewall rules, and it never uploads data. Evidence may contain hostnames, IP addresses, interface names, unit names, and process names. It does not collect environment variables, secrets, file contents, or full process arguments. Review `raw/` before publishing a bundle.

## Requirements

- Bash 4+ on a common Linux VPS distribution;
- root is recommended for complete kernel and service logs;
- missing optional commands are reported and skipped;
- systemd distributions receive the most complete checks.

Exit codes: `0` healthy, `1` warnings found, `2` failures found or invalid arguments.

## License

[MIT](LICENSE)
