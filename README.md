# VPS Health Check

> 不是跑分脚本，而是一套面向故障排查的 VPS 健康检查与证据整理工具。

[English](README_EN.md) | [排查说明](docs/diagnosis-guide.md) | [更新记录](CHANGELOG.md)

[![Shell checks](https://github.com/sanrokamlan-prog/vps-health-check/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/sanrokamlan-prog/vps-health-check/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

当 VPS 随机掉线、服务反复中断、CPU 莫名卡顿或厂商让你“提供证据”时，本工具会完成一次只读检查，把结果分成：

- **已检测到的事实**：资源、OOM、内核、磁盘、网卡、路由、丢包、DNS、HTTPS、服务状态。
- **合理排查方向**：本机问题、宿主机资源争用、疑似超售、上游网络、DDoS 清洗等。
- **可以直接转交的材料**：完整报告、原始证据、英文厂商工单、给管理员或 AI 的审查提示词。

脚本不会自动修复、重启服务、修改防火墙或安装软件。

## 一键检查

```bash
curl -fsSL https://raw.githubusercontent.com/sanrokamlan-prog/vps-health-check/main/vps-health-check.sh -o /tmp/vps-health-check.sh && sudo bash /tmp/vps-health-check.sh
```

完成后会显示报告和证据包路径：

```text
[INFO] 报告文件: /tmp/vps-health-host-20260725-120000.log
[INFO] 可分享证据包: /tmp/vps-health-host-20260725-120000-evidence.tar.gz
```

把 `tar.gz` 提交给 VPS 厂商、熟悉 Linux 的管理员或 AI 审查即可。

## 常用场景

检查 Xray、Nginx 并附加 MTR：

```bash
sudo bash /tmp/vps-health-check.sh --service xray --service nginx --mtr
```

持续监测一小时，每 5 秒记录一次网络状态：

```bash
sudo bash /tmp/vps-health-check.sh --watch 3600 --interval 5
```

导入外部探针的 `lost/back` 记录：

```bash
sudo bash /tmp/vps-health-check.sh --probe-log /root/probe.log --mtr
```

外部探针日志只需保持一行一个事件，例如：

```text
2026.07.24 06:05:20 UTC+8 lost
2026.07.24 06:09:39 UTC+8 back
```

英文输出：

```bash
sudo bash /tmp/vps-health-check.sh --lang en
```

## 证据包内容

```text
vps-health-*-evidence/
├── summary.md               # 中英文结论与建议
├── report.txt               # 完整运行报告
├── provider-ticket-en.txt   # 可直接发给厂商的英文工单
├── review-prompt.txt        # 给管理员或 AI 的审查提示词
└── raw/
    ├── system.txt           # 系统、启动与虚拟化信息
    ├── resources.txt        # 内存、磁盘、vmstat、进程摘要
    ├── network.txt          # 地址、路由、网卡计数、连接摘要
    ├── services.txt         # 失败单元与指定服务状态
    ├── kernel-24h.txt       # 最近 24 小时内核日志
    ├── external-probe.log   # 可选：外部探针原始记录
    └── mtr-*.txt            # 可选：MTR 原始结果
```

## 脚本会怎么建议

| 检测信号 | 可能方向 | 默认建议 |
| --- | --- | --- |
| CPU steal 持续偏高 | 宿主机 CPU 争用、邻居实例、疑似超售 | 空闲时复测 3 次，持续异常则提交厂商 |
| I/O wait 持续偏高 | 本机磁盘负载或宿主机存储拥堵 | 用 `iostat`/`pidstat` 排除本机后提交厂商 |
| OOM / Killed process | 内存不足或程序泄漏 | 查被杀进程、限制内存、增加 Swap/RAM |
| 网卡 link-down/watchdog | 虚拟网卡或宿主机网络 | 保存时间点并提交厂商 |
| 外部探针失联，但客户机日志干净 | 宿主机、上游、DDoS 清洗或路由 | 优先提交厂商，并附探针与 MTR |
| conntrack 接近耗尽 | 连接洪泛、代理/NAT 并发过高 | 查连接来源和防火墙/NAT 配置 |
| 服务 inactive/failed | VPS 内部服务故障 | 查 `systemctl status` 和 `journalctl -u` |

这些是排查方向，不是自动定责。尤其是“疑似超售”：单次 CPU steal 或一次卡顿不能证明厂商超售，必须看多次样本、业务负载、外部时间线以及厂商宿主机日志。

## 参数

```text
--hours N          检查最近 N 小时日志，默认 24
--target HOST      探测目标，可重复使用
--service NAME     检查 systemd 服务，可重复使用
--probe-log FILE   导入外部探针 lost/back 记录
--mtr              系统已安装 mtr 时生成路由报告
--watch [SECONDS]  持续探测；不填秒数则运行到 Ctrl+C
--interval N       持续探测间隔，默认 5 秒
--output FILE      指定主报告路径
--lang zh|en       中文或英文输出
--no-color         禁用终端颜色
```

退出码：`0` 正常、`1` 存在警告、`2` 存在明确异常或参数错误。

## 支持范围

- 推荐：Debian、Ubuntu、AlmaLinux、Rocky Linux 等使用 systemd 的常见 VPS。
- Bash 4+；root 权限不是强制要求，但使用 `sudo` 才能读取更完整的内核和服务日志。
- `mtr`、`curl`、`ping`、`ip`、`ss` 缺失时会跳过对应项目，不会自动装包。
- Alpine、OpenVZ 老模板或精简容器可以运行部分检查，但日志与 systemd 项目可能不可用。

## 隐私提醒

证据包可能包含主机名、IP 地址、接口、服务名和进程名。脚本不会收集环境变量、文件内容、密码、密钥或完整进程参数，也不会上传任何数据。公开分享前仍建议自行检查 `raw/`。

## 一个重要边界

从故障 VPS 内部发起的检查，无法单独证明“别人访问这台 VPS 的入站线路”发生过中断。可靠判断通常需要三类证据互相对齐：

1. 外部探针的 `lost/back` 时间；
2. 本地或另一台稳定 VPS 到故障 IP 的 Ping/MTR；
3. 故障 VPS 内部同一时间的内核、网卡、OOM 和服务日志。

如果外部探针持续失联，而客户机内部没有 OOM、重启、服务停止、网卡 link-down 等对应异常，就有充分理由要求厂商检查宿主机和上游，但仍应让厂商用宿主机日志确认最终原因。

## License

[MIT](LICENSE)
