# iStoreOS 上架材料（草稿，待审）

> 待提交到两个仓库：先元数据 PR，再 ipk/apk PR。**本文件是内部草稿，不提交上游。**

## 0. 已核实的规则（来自 `istoreos/istore-repo/README.md`）

| # | 规则 | 对 we 的影响 |
|---|---|---|
| 1 | 请勿提交 OpenWRT 官方仓库已经存在的包 | ⚠️ **最大风险**：官方 OpenWrt 已有 `netbird`（0.59.13）。我们提供的是 0.82.0 新版 |
| 2 | 开源需在 PR 中提供仓库地址 | ✅ 有 |
| 5 | **ipk 放 `bin/packages`，apk 放 `bin/apks`** | ⚠️ 我们只做 ipk |
| 6 | **同时支持 opkg 和 apk 的软件，ipk 和 apk 都要上传** | ❌ **我们做不出 apk** |
| 7 | aarch64 的 **ipk 是 `aarch64_cortex-a53`**，**apk 是 `aarch64_generic`** | ✅ ipk 重打包已实现（`make-istore.sh`） |

## 1. 产物对照

我们 `make istore` 产出（与规则 7 一致）：

```
bin/packages/aarch64_cortex-a53/nas/netbird_<v>-r<N>_aarch64_cortex-a53.ipk
bin/packages/x86_64/nas/netbird_<v>-r<N>_x86_64.ipk
bin/packages/all/nas_luci/luci-app-netbird_<lv>-r<lr>_all.ipk
bin/packages/all/nas_luci/luci-i18n-netbird-zh-cn_<lv>-r<lr>_all.ipk
applications/app-meta-netbird/{Makefile,logo.png}
```

**缺**：`bin/apks/<arch>/nas/*.apk` 与 `bin/apks/all/nas_luci/*.apk`。

## 2. 元数据 PR（`istoreos/openwrt-app-meta`）

新增 `applications/app-meta-netbird/{Makefile,logo.png}`：

```make
# This is free software, licensed under the Apache License, Version 2.0.

include $(TOPDIR)/rules.mk

PKG_VERSION:=0.82.0
PKG_RELEASE:=1
META_TITLE:=NetBird
META_TITLE.en:=NetBird
META_DEPENDS:=+netbird +luci-app-netbird
META_DESCRIPTION:=基于 WireGuard 的自托管虚拟局域网客户端，支持自建管理面
META_DESCRIPTION.en:=WireGuard-based mesh VPN client with self-hosted management support
META_AUTHOR:=NetBird GmbH / looong-cat
META_ARCH:=x86_64 aarch64
META_TAGS:=networking service
META_LUCI_ENTRY:=/cgi-bin/luci/admin/vpn/netbird
META_WEBSITE:=https://netbird.io

include ../../meta.mk
```

`logo.png`：官方 logomark，144×144，约 5 KB（≤50 KB 限制）。
`META_LUCI_ENTRY` 用 `admin/vpn` —— 与补丁 `0002-menu-under-vpn.patch` 一致，也与官方
`app-meta-zerotier` 的 `/cgi-bin/luci/admin/vpn/zerotier` 同构。

## 3. ipk PR（`istoreos/istore-repo`，目标分支 `pending`）

上传 4 个 ipk 到对应目录（见 §1）。不改 `repo/`、不改 `.github/workflows`。
文件名含版本，天然满足"每次上传不能重名"。

## 4. PR 描述（草稿）

> 补齐「最新 netbird + LuCI 管理界面」的完整组合。
>
> 官方 OpenWrt 源的 `netbird` 仍为 0.59.13，且没有可用的 LuCI 管理界面；本 PR 提供
> `netbird 0.82.0`（aarch64_cortex-a53 / x86_64）与配套的 `luci-app-netbird 0.1.0-r27`
> 及简体中文翻译。
>
> - 源码与构建：https://github.com/xyonium/netbird-pkgs
> - 上游：https://github.com/netbirdio/netbird （客户端 BSD-3-Clause）
> - LuCI 应用：https://github.com/looong-cat/luci-app-netbird （Apache-2.0）
>
> aarch64 包由 `aarch64_generic` 产物重打包 `Architecture` 字段得到，二进制不变；
> Go 的 arm64 产物是通用 ARMv8-A，非 cortex-a53 指令集优化。

## 5. 待决问题（上 PR 前必须有答案）

1. **规则 1 会不会直接毙掉这个 PR？** `netbird` 在官方源里存在。先例：`tailscale` 官方源也有，
   iStore 仍收录了 `luci-app-tailscale-community`。但既有先例不等于会被接受，需要确认。
2. **规则 6 的 apk 是否强制？** 我们目前产不出 `.apk`。两个选择：
   - a) 只提 ipk，接受可能被打回；
   - b) 先补 apk 构建能力再提（工作量：用 apk-tools / abuild 打包，或让 OpenWrt SDK 产出 apk）。
3. `luci-i18n-netbird-zh-cn` 是否需要单独列依赖？官方 zerotier 元数据里把
   `luci-i18n-zerotier-zh-cn` 写进了 `META_DEPENDS`。我们当前只写 `+netbird +luci-app-netbird`。
