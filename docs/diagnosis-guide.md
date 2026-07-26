# VPS 异常排查说明

本说明用于理解脚本给出的方向，不用于自动判定厂商责任。

## 证据优先级

排查间歇性故障时，优先收集能够对齐到同一时间点的证据：

1. 外部探针何时 `lost`、何时 `back`；
2. 本地和第三方 VPS 到故障 IP 的终点丢包与 MTR；
3. 故障 VPS 当时是否 OOM、重启、卡死、服务停止或网卡 link-down；
4. CPU steal、I/O wait、磁盘延迟是否在空闲时仍反复异常；
5. VPS 厂商宿主机和上游网络日志。

## 疑似宿主机超售或资源争用

`CPU steal` 表示虚拟机想使用 CPU，但 hypervisor 没有及时给它 CPU 时间。持续偏高可能来自宿主机过载、邻居实例争用或超售。

建议：

```bash
sudo bash vps-health-check.sh
sleep 60
sudo bash vps-health-check.sh
sleep 60
sudo bash vps-health-check.sh
```

如果 VPS 内部业务基本空闲，但多次样本的 steal 仍高于 5%，特别是超过 15%，将三个证据包一起提交厂商。单次样本不能直接证明超售。

## 疑似宿主机存储拥堵

I/O wait 高可能是本机进程大量读写，也可能是宿主机共享存储拥堵。先排除本机：

```bash
iostat -xz 1 10
pidstat -d 1 10
```

如果没有明显本机读写进程，但 `await`、`iowait` 仍持续很高，再要求厂商检查宿主机存储延迟。

## 外部失联但 VPS 内部没有异常

这种组合常见于：

- 宿主机虚拟交换或节点网络事件；
- 上游路由抖动或拥堵；
- DDoS 攻击、黑洞或清洗切换；
- 部分地区/运营商到该 IP 的路由异常；
- 厂商侧宿主机资源严重争用。

客户机内部日志干净不等于厂商一定有问题，但足以要求厂商核查。把 `provider-ticket-en.txt`、外部探针记录和 MTR 一并提交。

## 快照正常但实际仍有卡顿

一次性检查只能看到运行当时的状态，无法靠人工蹲守捕获几秒钟的进程暴涨、D 状态、steal、iowait 或 PSI 压力。建议启动后台监控：

```bash
sudo bash vps-health-monitor.sh start \
  --interval 3 --cpu 70 --memory 40 --load 120 \
  --cooldown 60 --max-log-mb 20
```

它只在超过阈值时写入完整快照，同类异常 60 秒内不会重复刷屏。发生问题后将日志并入检查：

```bash
sudo bash vps-health-check.sh \
  --monitor-log /var/log/vps-health-monitor/monitor.log \
  --probe-log /root/probe.log
```

重点对齐 `ANOMALY`、外部 `lost/back` 和业务异常时间。某个进程持续高 CPU/内存通常先处理客户机；业务空闲但 steal、I/O PSI 或 D 状态反复升高，则更值得要求厂商检查宿主机资源。

后台监控同时记录网络目标和整网状态。单个目标 `DOWN` 可能只是该目标限速 ICMP 或特定路由异常；只有所有配置目标都连续失败后才生成 `scope=network state=DOWN` 和 `NETWORK-ANOMALY` 快照。排查时优先对齐这种整网事件、恢复快照和外部探针时间，而不是把单目标失败直接当成 VPS 掉线。

证据包中的 `timeline.md` 已将外部 `lost/back`、后台 `DOWN/UP`、异常快照、当前启动和前台 watch 事件转换到 VPS 本地时区并排序。时间接近只能说明事件值得共同复核；是否同一根因仍需核对 `report.txt`、`raw/` 和厂商宿主机日志。

## 如何看 MTR

- 只看最后一跳和之后是否延续丢包，不要因单个中间路由器不回 ICMP 就判断线路故障。
- 最后一跳丢包并且业务也在同一时间不可达，才是更有价值的证据。
- 从两个不同网络方向测试，比只在故障 VPS 内部向外测试更可靠。
- MTR 是方向性证据，厂商仍需核对回程、宿主机和上游日志。

## 如何看累计网络计数

`ip -s link`、`/proc/net/snmp`、`/proc/net/netstat` 和 `/proc/net/softnet_stat` 中不少值从开机后一直累加。一次旧故障留下的非零值，不能说明当前仍在丢包或拥堵。

脚本会先记录基线，再进行 Ping、DNS、HTTPS 等检查，最后比较检查期间的增量：

- 累计值只作为上下文保留；
- 检查期间继续增长，才形成 WARN/FAIL 证据；
- 计数器变小通常意味着接口重建、网络命名空间变化或计数器重置，需要结合网卡与启动日志判断；
- IPv6 只有同时存在全局地址和默认路由时才测试，未配置 IPv6 不算异常。

## 什么材料适合交给 AI 或管理员

直接提供整个 `*-evidence.tar.gz`，并提醒审查者：

- 分开列出已确认事实、合理推断和缺失证据；
- 不根据一次 steal、一次 Ping 或 MTR 中间跳丢包直接定责；
- 给出需要补采的命令和可复制的厂商问题；
- 不索要密码、私钥或 API Key。

证据包已经包含 `review-prompt.txt`，可以直接作为审查说明。
