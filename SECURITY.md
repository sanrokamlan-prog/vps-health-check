# Security Policy

## Reporting a vulnerability

Please open a private GitHub security advisory for vulnerabilities that could expose sensitive host information or execute unintended commands. Do not include real passwords, private keys, API tokens, or unredacted production evidence in a public issue.

## Data handling

The script runs locally and does not upload telemetry. Evidence bundles can contain hostnames, IP addresses, interface names, service names, and process names. Review the bundle before sharing it publicly.

The optional background monitor writes a local rotating log and records process names, PIDs, users, resource percentages, and process states. It intentionally excludes full command arguments and environment variables. Root defaults to `/var/log/vps-health-monitor/monitor.log`; protect and review this file before sharing it.
