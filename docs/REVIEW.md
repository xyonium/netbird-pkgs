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
- 补丁 `0002-menu-under-vpn.patch` 把菜单从「服务」移到「VPN」
  （`admin/services/netbird*` → `admin/vpn/netbird*`）。LuCI 本身已定义
  `admin/vpn` 分类，改动只涉及 `menu.d` 的路径键；ACL 与视图路径不受影响。
- 上游 `Makefile` 的 `PKG_RELEASE` 会被 `scripts/build-luci-ipk.sh` 覆写为
  `versions/luci-app-netbird.env` 里的 `LUCI_PKG_RELEASE`。**本仓库只要改动了
  这个包的内容（补丁、许可、菜单），就必须把该值 +1**，否则设备
  `opkg upgrade` 会认为版本相同而跳过。
- 该文件里 `LUCI_UPSTREAM_RELEASE` 记录上次同步时上游的 `PKG_RELEASE`。
  `luci-watch` 调用的 `scripts/update-luci-env.sh` 据此判断上游是否真的动了：
  没动就原样不动（幂等），动了才把 `LUCI_PKG_RELEASE` 推到
  `max(本地, 上游) + 1`，**只会前进，不会退回上游的值**；且它按行改写、
  保留 `LUCI_SDK_*` 等其它字段。
- 该应用不自带 init，生命周期由本仓库的 `/etc/init.d/netbird` 负责。
- 其 uci-defaults 会写 `/etc/netbird.env`、创建 `firewall.netbird`、删除
  `network.netbird`、追加 `/etc/sysupgrade.conf`；设备验收覆盖这些副作用。
- NOTICE 缺少 Tailscale BSD-3 免责声明原文（上游缺口）；包内 NOTICE 后追加该文本。

## 许可

- `netbird` 客户端 BSD-3-Clause（`management/`、`signal/`、`relay/`、`combined/`
  才是 AGPLv3；本仓库不构建这四个目录）。
- 内嵌第三方模块的许可由 `scripts/collect-licenses.sh` 汇总，随包安装。
- `luci-app-netbird` Apache-2.0；包内保留 LICENSE/NOTICE。
