# Security Policy

## Reporting a vulnerability

Please open a private GitHub security advisory for vulnerabilities that could expose sensitive host information or execute unintended commands. Do not include real passwords, private keys, API tokens, or unredacted production evidence in a public issue.

## Data handling

The script runs locally and does not upload telemetry. Evidence bundles can contain hostnames, IP addresses, interface names, service names, and process names. Review the bundle before sharing it publicly.

The optional background monitor writes a local rotating log and records process names, PIDs, users, resource percentages, and process states. It intentionally excludes full command arguments and environment variables. Root defaults to `/var/log/vps-health-monitor/monitor.log`; protect and review this file before sharing it.

Generated reports, evidence directories, archives, monitor logs, and PID files use private default permissions. The scripts reject symbolic-link output paths to reduce overwrite risks during root execution. This does not replace normal host access controls; untrusted users must not be allowed to modify the selected parent directories while a root-run diagnostic is active.

`--redact` applies best-effort replacement to saved text evidence and removes known target names from MTR filenames. It is not a data-loss-prevention guarantee: process names, usernames, service names, and identifiers the tool cannot recognize remain. Always review a bundle before public distribution.
