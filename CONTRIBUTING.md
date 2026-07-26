# Contributing

Bug reports and focused pull requests are welcome.

Before submitting a change:

```bash
bash -n vps-health-check.sh
shellcheck vps-health-check.sh vps-health-monitor.sh tests/smoke.sh
bash tests/smoke.sh
```

Diagnostic rules must distinguish observed facts from inference. Do not label a provider as oversold or at fault from a single CPU steal, I/O wait, Ping, or MTR sample. New evidence collection must remain read-only and must not collect secrets, environment variables, file contents, or full process arguments.

Chinese is the default CLI language. User-visible behavior should also have an English translation.
