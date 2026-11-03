# iStoreOS 上架材料（草稿，待审）

> 待提交到两个仓库：先元数据 PR，再 ipk/apk PR。**本文件是内部草稿，不提交上游。**

## 0. 已核实的规则（`istoreos/istore-repo/README.md`）

| # | 规则原文 | 对我们的影响 |
|---|---|---|
| 1 | 请勿提交 OpenWRT 官方仓库已经存在的包 | ⚠️ 官方源有 `netbird` 0.59.13。**但有先例**（见 §0.1） |
| 2 | 开源需提供仓库地址 | ✅ 有 |
| 5 | ipk 放 `bin/packages`，apk 放 `bin/apks` | ✅ 我们的布局已符合 |
| 6 | 同时支持 opkg 和 apk 的软件，ipk 和 apk 都要上传 | ⚠️ 我们造不出 apk（§0.2），**但存在 ipk-only 先例（§0.3）** |
| 7 | aarch64 的 ipk 是 `aarch64_cortex-a53`，apk 是 `aarch64_generic` | ✅ 重打包已实现 |

### 0.1 规则 1 有明确先例（已核实）

官方 `openwrt/packages` 里有 `tailscale`、`zerotier`、`cups`、`netbird`。
而在 `istoreos/istore-repo` 里：

- `tailscale` 出现 **2 次**（`bin/packages/x86_64/nas/tailscale_1.104.1-r1_x86_64.ipk` 等）
- `cups` 出现 **4 次**

即**官方源已有的包，iStore 照样收录新版**。规则 1 的意图是"别重复收录官方已能提供的版本"，
而不是"官方有就不能进"。我们提供 0.82.0（官方是 0.59.13）+ 官方源没有的 LuCI 界面，
属于同一类先例。**这条风险可控。**

### 0.2 规则 6 是硬缺口（已核实，这是真正的阻塞）

先看 iStore 现状（`git trees` 实测）：

| 目录 | 文件数 |
|---|---|
| `bin/packages/x86_64/nas/` | 67 |
| `bin/apks/x86_64/nas/` | 66 |
| `bin/packages/all/nas_luci/` | 251 |
| `bin/apks/all/nas_luci/` | 251 |

**两边是同一批包**（逐项比对，差异只是我脚本的版本号切分）。所以规则 6 在实践中是**强制执行**的。

再看我们能不能造 apk：

```
# openwrt v24.10.0: config/Config-build.in:71-74
config USE_APK
	imply PACKAGE_apk-mbedtls
	bool "Use APK instead of OPKG to build distribution (BROKEN)"
	depends on BROKEN
```

**24.10 的 apk 支持是 `BROKEN`，`depends on BROKEN` → 无法启用。**
我们钉的就是 24.10.4 SDK（`versions/luci-app-netbird.env: LUCI_SDK_VERSION=24.10.4`），
所以**当前工具链造不出 apk**。

补充事实：我们实测的那台 iStoreOS 24.10.4（rockchip/armv8）**只有 opkg，没有 apk**：
```
$ command -v apk || echo 只有opkg
只有opkg
$ opkg --version
opkg version 38eccbb1…
```

结论：iStore 同时在为 **25.x（apk）** 和 **24.10（opkg）** 两个世代备货。我们只覆盖了后者。

要补 apk，需要额外一条 25.x/main SDK 的构建路径（不同 toolchain、`aarch64_generic` 命名、
apk 签名）。这是一个**独立的新能力**，不是改几行脚本的事。

### 0.3 但「apk 强制」这个结论是**错的** —— 有 ipk-only 先例

逐包比对 `bin/packages/x86_64/nas/`（67 个）与 `bin/apks/x86_64/nas/`（66 个）后，
绝大多数差异只是命名归一化（`quectel-CM-5G` → `quectel-CM` 等）。**真正的反例是 `tailscale`**：

```
bin/packages/x86_64/nas/tailscale_1.104.1-r1_x86_64.ipk
bin/packages/aarch64_cortex-a53/nas/tailscale_1.104.1-r1_aarch64_cortex-a53.ipk
bin/apks/all/nas_luci/luci-app-tailscaler-0.0.6.apk   ← 只有 LuCI 界面，没有 tailscale 二进制
```

**`tailscale` 二进制只有 ipk，没有 apk，而且已经在 iStore 里。** 全仓库 apk 树里
不含任何 tailscale 二进制包。

这条同时说明两件事：

1. 规则 6 在实践中**不是硬性拦截** —— 只交 ipk 是可以被接受的；
2. `tailscale` 也同时存在于官方 OpenWrt 源（规则 1 的对象），仍然被收录 ——
   与 §0.1 的结论一致。

所以原先的判断「被 apk 卡死」需要修正为：**apk 是加分项，不是准入门槛**。

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
META_DEPENDS:=+netbird +luci-app-netbird +luci-i18n-netbird-zh-cn
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

## 5. 待决问题（已核实，按风险排序）

1. **规则 6（apk）—— 唯一真正的阻塞。** 24.10 的 `USE_APK` 是 BROKEN，我们造不出 apk。
   选项：
   - **a) 只提 ipk**，在 PR 里说明"24.10 世代仍是 opkg，apk 待 25.x 工具链就绪后补"。
     风险：可能被打回；但规则 7 明确两种架构命名并存，说明维护者理解两个世代。
   - **b) 先补 25.x apk 构建**，再一次提全。工作量大，且要新增一条 SDK 路径。
   - **c) 先只提元数据 PR**（`openwrt-app-meta` 不涉及 ipk/apk），用它探维护者口风。
2. **规则 1 —— 风险可控。** 有 tailscale/cups 先例，且我们提供官方源没有的新版本 + LuCI。
3. `luci-i18n-netbird-zh-cn` 是否列进 `META_DEPENDS`：官方 `app-meta-zerotier` 把
   `+luci-i18n-zerotier-zh-cn` 写进去了。我们当前只写 `+netbird +luci-app-netbird`，
   建议**照抄 zerotier 的写法**补上中文包依赖。

## 6. 建议的提交顺序

原先写的「不要在没有 apk 的情况下提 ipk PR」在 §0.3 之后**不成立了**：`tailscale`
就是 ipk-only 且已收录。改为：

1. **在 PR 描述里主动说明**「24.10 工具链的 `USE_APK` 为 BROKEN，故本次只提供 ipk；
   apk 待 25.x 基座就绪后补上」。把限制讲在前面，比被 reviewer 问出来好。
2. **先提 `istore-repo` 的 ipk PR**（目标分支 `pending`），这是真正决定能否上架的一步；
   元数据 PR 可以并行，但它只是商店展示信息。
3. 如果被要求补 apk，再评估是否引入 25.x SDK 构建线（那是独立能力，需要新开计划）。
