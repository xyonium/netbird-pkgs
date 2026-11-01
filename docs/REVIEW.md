# 上游审计与本地修正

## netbird 包（相对上游 OpenWrt 24.10）

1. 删除 `. /lib/netifd/netifd-proto.sh`（netbird 不实现 netifd 协议）。
2. 状态从 `/root/.config/netbird` 改为 `/etc/netbird`：显式设置 `NB_CONFIG` 与
   `NB_STATE_DIR`，避免默认落到 `/var/lib/netbird`（tmpfs）。`NB_DNS_STATE_FILE`
   保持 `/var/lib/netbird/state.json`（可重建的运行态）。
3. 增加 `procd_set_param respawn 3600 5 5`（上游未设置）。
4. 解析 `/etc/netbird.env` 的白名单变量（`NB_LOG_FILE`、`NB_LOG_LEVEL`、
   `SSL_CERT_FILE`），**不 source**，避免 root 执行任意 shell。
5. 不启用 `service_triggers`：wan 抖动时反复重启反而加剧断连。

## luci-app-netbird（Apache-2.0）

- 补丁 `0001-default-binary-source-opkg.patch` 把 `binary_source` 默认值从
  `release` 改为 `opkg`，阻止首连时从 GitHub 下载并替换 `/usr/bin/netbird`。
  补丁作用于 conffile，仅影响新安装；GUI 仍可由管理员手动切换（已知残余能力）。
- 该应用不自带 init，生命周期由本仓库的 `/etc/init.d/netbird` 负责。
- 其 uci-defaults 会写 `/etc/netbird.env`、创建 `firewall.netbird`、删除
  `network.netbird`、追加 `/etc/sysupgrade.conf`；设备验收覆盖这些副作用。
- NOTICE 缺少 Tailscale BSD-3 免责声明原文（上游缺口）；包内 NOTICE 后追加该文本。

## 许可

- `netbird` 客户端 BSD-3-Clause（`management/`、`signal/`、`relay/`、`combined/`
  才是 AGPLv3；本仓库不构建这四个目录）。
- 内嵌第三方模块的许可由 `scripts/collect-licenses.sh` 汇总，随包安装。
- `luci-app-netbird` Apache-2.0；包内保留 LICENSE/NOTICE。
