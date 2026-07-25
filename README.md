<div align="center">

# VPS Health Check

### 把「VPS 好像有问题」变成一份可复核、可转交、可追责的诊断证据

一次只读检查，完成系统健康分析、异常方向判断、原始证据归档、厂商工单生成与 AI 辅助审查准备。

[![Release](https://img.shields.io/github/v/release/sanrokamlan-prog/vps-health-check?style=flat-square&label=Release&color=0ea5e9)](https://github.com/sanrokamlan-prog/vps-health-check/releases/latest)
[![Shell checks](https://img.shields.io/github/actions/workflow/status/sanrokamlan-prog/vps-health-check/shellcheck.yml?branch=main&style=flat-square&label=Shell%20Checks)](https://github.com/sanrokamlan-prog/vps-health-check/actions/workflows/shellcheck.yml)
[![Bash](https://img.shields.io/badge/Bash-4%2B-293137?style=flat-square&logo=gnu-bash&logoColor=white)](vps-health-check.sh)
[![License](https://img.shields.io/github/license/sanrokamlan-prog/vps-health-check?style=flat-square&color=22c55e)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/sanrokamlan-prog/vps-health-check/total?style=flat-square&color=f59e0b)](https://github.com/sanrokamlan-prog/vps-health-check/releases)

[立即检查](#一分钟开始) · [终端预览](#终端预览) · [核心能力](#核心能力) · [证据包](#证据包) · [排查指南](docs/diagnosis-guide.md) · [English](README_EN.md)

</div>

---

## 项目定位

VPS 出现随机掉线、服务中断、CPU 卡顿或网络「仰卧起坐」时，最难的通常不是发现异常，而是回答下面几个问题：

- 是 VPS 内部程序出了问题，还是宿主机资源争用？
- 是内存、磁盘、虚拟网卡、上游路由，还是 DDoS 清洗？
- 哪些是已经确认的事实，哪些只是合理推断？
- 应该自己处理、提交 VPS 厂商，还是交给管理员或 AI 继续审查？

VPS Health Check 将这些问题整理成一条完整的诊断链路：

```text
系统快照 ─────────┐
内核与服务日志 ───┤
网络与网卡证据 ───┼──> 异常分级 ──> 排查建议 ──> 可分享证据包
外部探针时间线 ───┤                         ├─> 英文厂商工单
MTR / 持续监测 ───┘                         └─> 管理员 / AI 审查提示词
```

> 这不是跑分脚本，也不会自动修复系统或自动定责。它的目标是把模糊现象整理成有时间、有原始数据、有判断边界的排查材料。

| 项目 | 当前能力 |
| --- | --- |
| 当前版本 | `v1.0.0` |
| 运行方式 | 单文件 Bash 脚本，下载即用 |
| 默认语言 | 中文，支持 `--lang en` |
| 操作边界 | 只读，不改防火墙、不重启服务、不安装软件 |
| 输出产物 | 主报告、双语摘要、原始证据、英文工单、审查提示词、`tar.gz` 证据包 |
| 适用对象 | VPS 用户、运维人员、服务商支持团队、Linux 管理员、AI Agent |

---

## 一分钟开始

下载稳定版并立即检查：

```bash
curl -fsSL https://github.com/sanrokamlan-prog/vps-health-check/releases/download/v1.0.0/vps-health-check.sh -o /tmp/vps-health-check.sh && sudo bash /tmp/vps-health-check.sh
```

检查结束后，终端会给出报告与证据包路径：

```text
[INFO] 报告文件: /tmp/vps-health-host-20260726-120000.log
[INFO] 证据目录: /tmp/vps-health-host-20260726-120000-evidence
[INFO] 可分享证据包: /tmp/vps-health-host-20260726-120000-evidence.tar.gz
```

将最后生成的 `tar.gz` 提交给 VPS 厂商、熟悉 Linux 的管理员或 AI Agent 即可继续审查。

<details>
<summary><strong>运行 main 分支最新版本</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/sanrokamlan-prog/vps-health-check/main/vps-health-check.sh -o /tmp/vps-health-check.sh && sudo bash /tmp/vps-health-check.sh
```

稳定使用建议优先选择 Release；`main` 适合测试最新改动。

</details>

---

## 终端预览

下面是脚本发现宿主机争用线索与外部中断记录时的典型输出结构：

```text
VPS Health Check v1.0.0

== 资源状态 ==
[PASS] 内存使用率: 41%
[PASS] 磁盘使用率: / 36%
[WARN] CPU steal 偏高，可能存在宿主机 CPU 争用: 8%
[PASS] CPU I/O wait: 1%

== 外部探针证据 ==
[WARN] 外部探针记录到不可达事件: 6

== 建议与下一步 ==
1. CPU steal=8%，这是宿主机 CPU 争用/超售的线索。
2. 外部探针记录了失联，但客户机侧没有对应 OOM、内核卡死、
   服务停止或网卡 link-down 证据，建议提交 VPS 厂商核查。
3. 如果结论仍不明确，将完整证据包交给管理员或 AI 辅助审查。

== 检查结论 ==
PASS=18  WARN=2  FAIL=0
[INFO] 总体状态: WARN
[INFO] 可分享证据包: /tmp/vps-health-node-evidence.tar.gz
```

输出只会把高 `CPU steal`、高 I/O wait、外部失联但客户机日志干净等现象标记为**宿主机争用或疑似超售线索**，不会根据单次采样自动认定厂商责任。

---

## 核心能力

### 系统健康快照

| 检查域 | 检查内容 |
| --- | --- |
| CPU | Load、CPU 数量、CPU steal、I/O wait |
| 内存 | RAM、Swap、OOM、Killed process |
| 存储 | 磁盘空间、inode、I/O 与文件系统错误 |
| 系统 | OS、内核、虚拟化、运行时间、时间同步、启动/关机记录 |
| 服务 | systemd 失败单元、指定服务状态、累计重启次数 |

### 网络异常取证

| 检查域 | 检查内容 |
| --- | --- |
| 网卡 | 默认出口接口、operstate、RX/TX error、drop、link-down、watchdog |
| 路由 | 默认路由、完整路由表、出口接口定位 |
| 连通性 | 多目标 Ping、丢包率、平均延迟、DNS、HTTPS |
| 连接状态 | Socket 摘要、conntrack 使用率 |
| 链路质量 | 可选 MTR 原始报告 |
| 间歇故障 | `--watch` 持续记录带时区的 `UP/DOWN` 事件 |

### 面向小白的判断输出

脚本不会只告诉你「有问题」，还会根据检测信号输出下一步：

| 检测信号 | 更可能的方向 | 默认下一步 |
| --- | --- | --- |
| CPU steal 持续偏高 | 宿主机 CPU 争用、邻居实例、疑似超售 | 空闲状态复测 3 次，持续异常则提交厂商 |
| I/O wait 持续偏高 | 本机磁盘负载或宿主机存储拥堵 | 用 `iostat` / `pidstat` 排除本机负载 |
| OOM / Killed process | 内存不足或程序泄漏 | 定位被杀进程，限制内存或增加 Swap/RAM |
| 网卡 link-down / watchdog | 虚拟网卡或宿主机网络事件 | 保留时间点和内核日志并提交厂商 |
| 外部探针失联、客户机日志干净 | 宿主机、上游、DDoS 清洗或路由 | 附探针时间线与 MTR，优先要求厂商核查 |
| conntrack 接近耗尽 | 连接洪泛、代理或 NAT 并发过高 | 检查连接来源、防火墙和 NAT 配置 |
| 服务 inactive / failed | VPS 内部服务故障 | 检查 `systemctl status` 与 `journalctl -u` |

### 可直接转交的材料

- **给 VPS 厂商**：自动生成 `provider-ticket-en.txt`，包含已发现事实和宿主机检查请求。
- **给管理员或大佬**：原始资源、网络、服务、内核和探针证据完整保留。
- **给 AI Agent**：自动生成 `review-prompt.txt`，要求区分事实、推断和缺失证据。
- **给自己留档**：主报告没有 ANSI 颜色字符，便于搜索、对比和长期归档。

---

## 常用工作流

### 检查常见代理和 Web 服务

```bash
sudo bash /tmp/vps-health-check.sh \
  --service xray \
  --service nginx \
  --mtr
```

### 记录一小时网络状态

```bash
sudo bash /tmp/vps-health-check.sh --watch 3600 --interval 5
```

脚本会在状态变化时写入带时区事件：

```text
[EVENT] 2026-07-26 00:23:14 +0800 1.1.1.1 DOWN
[EVENT] 2026-07-26 00:27:29 +0800 1.1.1.1 UP
```

### 导入外部探针记录

```bash
sudo bash /tmp/vps-health-check.sh \
  --probe-log /root/probe.log \
  --mtr
```

支持最简单的一行一个事件格式：

```text
2026.07.24 06:05:20 UTC+8 lost
2026.07.24 06:09:39 UTC+8 back
2026.07.24 06:17:44 UTC+8 lost
2026.07.24 06:22:02 UTC+8 back
```

### 切换英文输出

```bash
sudo bash /tmp/vps-health-check.sh --lang en
```

---

## 证据包

每次检查都会把结论与原始数据分开保存，方便其他人复核脚本判断：

```text
vps-health-*-evidence/
├── summary.md               # 中英文结论与建议
├── report.txt               # 完整检查报告
├── provider-ticket-en.txt   # 可直接修改并提交的英文工单
├── review-prompt.txt        # 管理员 / AI 结构化审查提示词
└── raw/
    ├── system.txt           # 系统、启动与虚拟化信息
    ├── resources.txt        # 内存、磁盘、vmstat、进程摘要
    ├── network.txt          # 地址、路由、网卡计数、连接摘要
    ├── services.txt         # 失败单元与指定服务状态
    ├── kernel-24h.txt       # 最近 24 小时内核日志
    ├── external-probe.log   # 可选：外部探针原始记录
    └── mtr-*.txt            # 可选：MTR 原始结果
```

证据包默认还会压缩为：

```text
/tmp/vps-health-<host>-<time>-evidence.tar.gz
```

### 自动生成的厂商工单

`provider-ticket-en.txt` 会要求厂商围绕实际证据检查：

- 宿主机 CPU、存储争用或可能的资源超售；
- 虚拟网卡、虚拟交换与节点网络事件；
- 上游路由、终点丢包与回程异常；
- DDoS 攻击、黑洞或清洗切换；
- 外部探针记录时间附近的宿主机日志。

它不会把推测伪装成结论，降低工单被厂商用「客户机问题」直接驳回的概率。

### 管理员与 AI 审查边界

`review-prompt.txt` 会明确要求审查者按三层输出：

1. **已确认事实**：原始日志和指标直接支持的内容；
2. **合理推断**：证据组合指向但尚未证实的方向；
3. **仍缺证据**：需要补采的时间线、命令或厂商侧日志。

同时要求不得索取密码、私钥、API Key 等秘密。

---

## 准确性边界

### 关于宿主机超售

`CPU steal` 表示虚拟机希望使用 CPU，但 hypervisor 没有及时分配 CPU 时间。持续偏高可能来自宿主机过载、邻居实例争用或超售，但一次采样不足以定责。

建议在 VPS 业务空闲时重复运行 3 次。如果 `steal` 多次高于 5%，尤其持续超过 15%，再将多个证据包一起提交厂商。

### 关于入站网络中断

从故障 VPS 内部向外测试，无法单独证明「其他用户访问这台 VPS」的入站线路发生过中断。可靠判断需要对齐三类证据：

```text
外部探针 lost/back 时间
        +
本地 / 第三方 VPS 到故障 IP 的终点 Ping 与 MTR
        +
故障 VPS 同一时间的 OOM、内核、服务与网卡日志
```

如果外部探针持续失联，而客户机内部没有 OOM、重启、服务停止、内核卡死或网卡 link-down，就有充分理由要求厂商检查宿主机和上游；最终原因仍应由厂商结合宿主机日志确认。

### 关于 MTR 中间跳丢包

部分路由器会限制或忽略 ICMP 响应。只有中间某一跳丢包、后续与终点正常时，不能据此判断线路故障。应重点看终点是否丢包，以及业务中断时间是否一致。

更完整的判断原则见 [VPS 异常排查说明](docs/diagnosis-guide.md)。

---

## 参数参考

```text
--hours N          检查最近 N 小时日志，默认 24
--target HOST      网络探测目标，可重复使用
--service NAME     检查 systemd 服务，可重复使用
--probe-log FILE   导入外部探针 lost/back 记录
--mtr              系统已安装 mtr 时生成路由报告
--watch [SECONDS]  持续探测；不填秒数则运行到 Ctrl+C
--interval N       持续探测间隔，默认 5 秒
--output FILE      指定主报告路径
--lang zh|en       中文或英文输出
--no-color         禁用终端颜色
-h, --help         显示帮助
```

| 退出码 | 含义 |
| --- | --- |
| `0` | 没有发现警告或失败 |
| `1` | 发现需要关注的警告 |
| `2` | 发现明确异常，或参数无效 |

---

## 支持范围

| 环境 | 支持情况 |
| --- | --- |
| Debian / Ubuntu | 推荐，完整支持 |
| AlmaLinux / Rocky Linux / RHEL 系 | 推荐，完整支持 |
| 其他 systemd Linux | 大部分检查可用 |
| Alpine / 精简容器 | 可运行部分检查，systemd 与日志项可能不可用 |
| OpenVZ 老模板 | 受宿主机权限限制，部分内核证据可能不可见 |

运行要求：

- Bash 4+；
- root 不是强制要求，但建议使用 `sudo` 获取完整内核和服务日志；
- `mtr`、`curl`、`ping`、`ip`、`ss` 缺失时会跳过对应项目；
- 脚本不会自行安装依赖或修改系统配置。

---

## 安全与隐私

脚本坚持只读取证据，不执行自动修复：

- 不修改防火墙、路由、sysctl 或服务配置；
- 不安装软件、不重启服务、不重启 VPS；
- 不读取环境变量、业务文件、密码、密钥或 Token；
- 不收集完整进程参数，避免命令行中的秘密进入报告；
- 不上传遥测、报告或证据包。

证据包仍可能包含主机名、公网 IP、接口名、服务名和进程名。公开分享前请自行检查 `raw/` 目录。

安全问题请参阅 [SECURITY.md](SECURITY.md)。

---

## 项目质量

每次提交都会在 GitHub Actions 中执行：

```text
Bash syntax
    ↓
ShellCheck
    ↓
参数与错误码测试
    ↓
探针导入与证据包测试
    ↓
持续监测 smoke test
```

本地验证：

```bash
bash -n vps-health-check.sh
shellcheck vps-health-check.sh tests/smoke.sh
bash tests/smoke.sh
```

---

## 文档与参与

- [English README](README_EN.md)
- [VPS 异常排查说明](docs/diagnosis-guide.md)
- [更新记录](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [下载最新 Release](https://github.com/sanrokamlan-prog/vps-health-check/releases/latest)

发现误报、漏报或发行版兼容问题时，可以通过 [Issue](https://github.com/sanrokamlan-prog/vps-health-check/issues/new/choose) 提交经过脱敏的输出。请勿公开密码、私钥、API Token 或未经检查的生产环境证据包。

---

## License

本项目基于 [MIT License](LICENSE) 开源。

<div align="center">

如果它帮助你把一次模糊故障整理成了有效证据，可以为项目点一个 Star，让更多不会排查 VPS 的用户找到它。

</div>
