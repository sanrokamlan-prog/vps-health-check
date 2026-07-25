# VPS Health Check

> A read-only VPS diagnostic and evidence-packaging tool, not another benchmark script.

[中文](README.md) | [Diagnostic guide](docs/diagnosis-guide.md) | [Changelog](CHANGELOG.md)

It checks guest resources, OOM events, kernel and storage errors, NIC state, routing, packet loss, DNS, HTTPS, systemd units, CPU steal, and I/O wait. It then generates actionable recommendations plus material that can be reviewed by a VPS provider, an experienced administrator, or an AI assistant.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/sanrokamlan-prog/vps-health-check/main/vps-health-check.sh -o /tmp/vps-health-check.sh && sudo bash /tmp/vps-health-check.sh
```

Useful examples:

```bash
# Check selected services and add MTR evidence
sudo bash /tmp/vps-health-check.sh --service xray --service nginx --mtr

# Watch connectivity for one hour
sudo bash /tmp/vps-health-check.sh --watch 3600 --interval 5

# Import lost/back timestamps from external monitoring
sudo bash /tmp/vps-health-check.sh --probe-log /root/probe.log --mtr

# English CLI output
sudo bash /tmp/vps-health-check.sh --lang en
```

## Generated evidence

The script creates a report and a compressed evidence bundle containing:

- `summary.md`: findings and recommendations in Chinese and English;
- `report.txt`: the complete console report without ANSI colors;
- `provider-ticket-en.txt`: an editable English provider ticket;
- `review-prompt.txt`: a structured prompt for administrator or AI review;
- `raw/`: system, resource, network, service, kernel, probe, and optional MTR evidence.

## Interpreting host-contention signals

Elevated CPU steal can indicate host CPU contention or oversubscription. Elevated I/O wait with little guest-side disk activity can indicate host storage contention. Neither signal proves provider fault from a single sample. Repeat the check while the guest is idle, correlate it with external outage timestamps, and ask the provider to inspect host-side logs.

External monitoring outages with no matching guest OOM, reboot, stopped service, kernel lockup, or NIC link-down event are a valid reason to escalate host-node, upstream-routing, or DDoS-mitigation investigation. They still do not prove one specific cause.

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
