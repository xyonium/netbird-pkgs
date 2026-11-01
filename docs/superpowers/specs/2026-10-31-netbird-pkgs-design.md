# NetBird 自建软件包仓库 — 设计文档

- 日期：2026-10-31
- 状态：待审阅（v2）
- 作者：与 AI 助手协作产出

### 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1 | 2026-10-31 | 初稿：背景、约束、包设计、签名分发、流水线、安全模型 |
| v2 | 2026-10-31 | 自检修订：修正发布触发链；补全 ipk 组装与可复现性、密钥轮换、发布原子性、测试策略、脚本接口契约、失败模式与恢复、版本与发布策略、许可合规；补齐 LuCI 二进制来源固定的具体机制；更新事实核查记录 |
| v2.1 | 2026-10-31 | 补充自建管理面（自定义 management URL）与配置/状态存放说明；确认 GitHub 用户名为 `xyonium`；`/etc/netbird.env` 白名单增加 `SSL_CERT_FILE` |
| v2.2 | 2026-11-01 | 澄清范围边界：客户端完整支持自建管理面；服务端组件的分发与部署仍不在本仓库；修正非目标表述 |
| v2.3 | 2026-11-01 | 按 iStoreOS 实际 PR 机制重写上架章节：预编译 ipk + `pending` 分支 + `openwrt-app-meta` 元数据；新增 iStore bundle 产物、脚本契约与测试 |

## 1. 背景与目标

### 问题

OpenWrt 24.10 稳定源的 NetBird 停留在 `0.59.13`，而上游已到 `0.82.0`，落后约 23 个小版本。根因已查明：NetBird 0.82.0 的 `go.mod` 要求 Go 1.26，而 OpenWrt 24.10 SDK 自带 Go 1.23.12，官方维护者无法在不连带升级工具链的前提下跟进。

OPNsense 侧同理：`netbird` 二进制包在 25.7 源里是 `0.60.7`，26.1 源里是 `0.72.2`，而 FreeBSD ports 树已到 `0.81.5`。

此外，使用者的管理面是**自建**（非 NetBird Cloud）：客户端必须能指向任意 management URL，并在重启与固件升级后保持连接。这是本设计的目标之一（§7.7），服务端本身的部署不在本仓库范围。

### 目标

建立一个由使用者完全掌控的软件包仓库，满足：

1. 自动跟踪 NetBird 官方 release，构建适配 `aarch64_generic` 与 `x86_64` 的 OpenWrt ipk
2. 提供带 usign 签名的 opkg 软件源，设备上 `opkg update && opkg install netbird` 即可安装与升级
3. 构建逻辑完全可审查、可在本机复现
4. 修正上游打包中已确认的缺陷（详见 §7.2）
5. 提供 LuCI 图形界面（从源码自建、钉版本）
6. 支持自建管理面（客户端侧）：可配置自定义 management URL（CLI 与 LuCI 两条路径）、支持私有 CA，配置持久化并在重启/升级后保持连接
7. 预留 iStoreOS 上架路径：产出符合 `istore-repo` 目录/命名规范的预编译 ipk 与 `app-meta` 元数据，可按其 PR 流程提交
8. 为 OPNsense 侧保留独立扩展空间

### 非目标

- 不追求覆盖 OpenWrt 全架构矩阵（仅两架构）
- 不发布到 OpenWrt 官方源；iStoreOS 商店上架走人工 PR（§16），不把自建源注册成 iStore 源（机制上不可行）
- 不打包、分发或部署 NetBird 服务端组件（`management/`、`signal/`、`relay/`、`combined/`）：服务端由使用者自行部署（官方 self-hosted 方案或既有实例），本仓库只保证**客户端**能指向并与自建管理面互通
- 不提供服务器侧的镜像、编排、备份与升级工具（如需要可另立项）
- 本期不实现 OPNsense 构建（独立立项，见 §17）

## 2. 目标设备与运行环境

| 设备 | SoC | 架构字段 | 固件 |
|---|---|---|---|
| FriendlyElec NanoPi R4S | RK3399 (2×A72 + 4×A53) | `aarch64_generic` | iStoreOS 24.10.5，内核 6.6.119 |
| Lunzn FastRhino R68S | RK3568 (4×A55) | `aarch64_generic` | iStoreOS 24.10.4，内核 6.6.110 |

两台设备架构相同，共用同一份包。iStoreOS 基于 OpenWrt 24.10，包管理器为 `opkg`（ipk 格式），**不是** 25.x 之后的 `apk`。

`x86_64` 产物面向通用 x86 软路由与虚拟机：本期无固定验收设备，只做 CI 构建、结构与静态链接校验（§12.3），并在需要时用 x86 OpenWrt rootfs 做一次容器安装（§12.1 L4）。

架构命名有两套：本机 opkg feed 用设备实际架构 `aarch64_generic`；iStore 商店要求 aarch64 的 ipk 标注为 `aarch64_cortex-a53`（§16），由同一份二进制重打包得到。两者不混用：设备日常升级走自建 feed，iStore 只用于商店分发。

## 3. 关键约束（实测确认，非推测）

| 事实 | 影响 |
|---|---|
| NetBird v0.82.0 `go.mod`: `go 1.26.0`，注释要求 toolchain ≥ `go1.26.2` | 构建必须使用 Go ≥ 1.26.2 |
| OpenWrt 24.10 的 `lang/golang` 为 1.23.12 | **无法**在 24.10 SDK 内编译 netbird |
| OpenWrt 快照源已改用 `.apk`（实测仅 `netbird-0.81.4-r1.apk`） | 快照源产物对 iStoreOS 24.10 不可用 |
| 官方源 `openwrt-24.10` 分支 netbird = 0.59.13；`master` = 0.81.4 | 官方源不可作为新版来源 |
| 上游 release 不提供 FreeBSD 产物（仅 linux/darwin/windows/wasm） | OPNsense 侧须自行编译 |
| `luci-app-netbird` 依赖 `netbird (>=0)` 且 `PKGARCH:=all` | 与本仓库互补，一个包适配两架构 |
| GitHub Actions 使用 `GITHUB_TOKEN` 推送产生的事件**不会**启动新的 workflow run | 发布链不能依赖「bot 提交后再由 push 触发」，改用 `workflow_run`（§10.1） |
| OpenWrt 上 `/var` 为 tmpfs，重启即失 | 运行时状态（如 DNS 状态文件）放在 `/var/lib/netbird` 并在启动时重建；持久配置放 `/etc` |
| opkg 只在 `/etc/opkg/keys/` 下按**公钥指纹**命名的文件中查找信任公钥 | 设备接入时须把公钥重命名为指纹（§9.4） |
| NetBird 客户端为 BSD-3-Clause；`management/`、`signal/`、`relay/`、`combined/` 为 AGPLv3 | 本仓库只构建 `./client`，不触发 AGPL 源码义务（§22） |
| 上游 24.10 init 仅设 `NB_CONFIG=/etc/netbird/config.json`；master 仅设 `NB_STATE_DIR=/root/.config/netbird` 等 | 需同时固定 `NB_CONFIG` 与 `NB_STATE_DIR` 才能持久化（§7.2、§7.3）；两侧均无 `respawn` |
| netbird 默认状态目录 `/var/lib/netbird`、默认配置 `/var/lib/netbird/default.json` | 不显式设 `NB_CONFIG`/`NB_STATE_DIR` 时配置会落在 tmpfs |
| 上游 24.10 init 不读 `/etc/netbird.env`，`files/` 下仅有 `netbird.init` | 需自行消费白名单变量（§7.2 修正 4） |
| netbird 默认管理面 `https://api.netbird.io:443`；`--management-url` 可覆盖 | 自建管理面无需改二进制，只需正确传参并持久化（§7.7） |
| netbird 的 profile 路径默认 `<NB_STATE_DIR>/default.json`；`--config`/`NB_CONFIG` 可覆盖 | 本包固定 `NB_CONFIG=/etc/netbird/config.json`，与 LuCI 的探测路径一致（§7.7） |
| LuCI 把 `management_url` 存 UCI `/etc/config/netbird`（`netbird.settings.management_url`），并通过 `netbird up --management-url` 传参 | UCI 配置持久、非机密；setup key 不落盘（§8、§11） |

## 4. 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions                                              │
│                                                             │
│  upstream-watch.yml（周一 03:00 UTC）                        │
│    └→ 查 netbirdio/netbird 最新 release                      │
│       └→ 更新 versions/netbird.env（版本 + commit + sha256）  │
│            │                                                │
│            └─(workflow_run)──→ build-release.yml            │
│                                                             │
│  luci-watch.yml（周一）                                      │
│    └→ 查 luci-app-netbird 新 tag → 开 PR（人工合并）          │
│                                                             │
│  build-release.yml（亦可 workflow_dispatch 手动重发）         │
│    job build      : 交叉编译 + 许可收集 + 组装 ipk（无密钥）   │
│    job build-luci : OpenWrt SDK 构建 luci-app-netbird         │
│    job sign-publish: 索引 + usign 签名 + Release              │
│    job deploy-pages: Pages 原子部署（独立 environment）        │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
      GitHub Pages（单次原子部署）：https://xyonium.github.io/netbird-pkgs/
        ├── aarch64_generic/{Packages,Packages.gz,Packages.sig,*.ipk}
        ├── x86_64/{...}
        ├── istore/{aarch64_cortex-a53 命名的 ipk}
        └── keys/netbird-pkgs.pub
                          │
                          ▼
  设备：/etc/opkg/customfeeds.conf + /etc/opkg/keys/<指纹>
```

### 数据流

1. **版本真相源**：`versions/netbird.env` 是唯一版本来源，由 `upstream-watch` 写入，bot 提交可审计、可 revert。
2. **构建**：下载并校验源码 → 交叉编译 → 收集许可 → 组装 ipk。构建阶段无网络访问（除源码下载），不执行上游任何脚本或测试。
3. **签名发布**：生成 `Packages` → `usign` 签名 → 创建不可变 Release → 原子部署到 Pages。任何一步失败即停（§14）。
4. **设备**：`opkg update` 验签索引 → 安装/升级 → procd 拉起 → 配置落 `/etc/netbird` 并在升级后保留。

## 5. 关键决策与取舍

| 决策点 | 选择 | 放弃的备选 | 理由 |
|---|---|---|---|
| 构建路线 | Go 交叉编译 + 标准 `tar` 手工组装 ipk | OpenWrt SDK/buildroot；向官方源 backport | 24.10 SDK 的 Go 1.23 无法编译 0.82.0；backport 受上游节奏制约；手写 ipk 不依赖 SDK，结构可逐字节审查 |
| Go 工具链 | 钉死具体补丁版本（1.26.2） | 跟随 `latest` | 上游注释要求 toolchain ≥ go1.26.2；钉死才能保证可复现与失败可解释 |
| CGO | `CGO_ENABLED=0` | 开启 CGO 并交叉编译 musl 工具链 | 静态链接，规避 glibc/musl 与跨架构 sysroot 问题（阶段 1 验证，§19） |
| 配置与状态目录 | `/etc/netbird`（同时设 `NB_CONFIG` 与 `NB_STATE_DIR`） | 上游 master 的 `/root/.config/netbird`；netbird 默认的 `/var/lib/netbird` | netbird 默认把状态放 `/var/lib/netbird`、配置放 `/var/lib/netbird/default.json`，而 `/var` 在 OpenWrt 上是 tmpfs；`/etc` 参与 sysupgrade 保留，且与 `luci-app-netbird` 首选探测路径 `/etc/netbird/config.json` 一致 |
| 签名信任锚 | `usign` 签名 `Packages` + 公钥预置设备 | 仅依赖 HTTPS；给每个 ipk 单独签名 | opkg 原生校验索引签名，索引内含每个 ipk 的 sha256；离线也可验 |
| Feed 托管 | GitHub Pages + GitHub Releases 双轨 | 自建对象存储/Web 服务器 | 零运维、HTTPS 默认、与 CI 同源；Releases 保存不可变归档 |
| 发布触发 | `workflow_run` + `workflow_dispatch` | `GITHUB_TOKEN` 提交后靠 `push` 触发；`workflow_call` 可复用流程 | `GITHUB_TOKEN` 产生的事件不会启动新 workflow run；`workflow_call` 会使 `environment` 密钥传递受限 |
| LuCI 二进制来源 | 补丁把 `binary_source` 默认值改为 `opkg` | uci-defaults 强制覆盖；完全不使用该应用 | 补丁落在 conffile 上，仅影响新安装，不覆盖用户已有选择；默认即阻断首连时的 GitHub 自动下载 |
| 版本真相源 | `versions/netbird.env`（版本、commit、sha256、pkg release） | 只用 git tag；只用 Release 描述 | 单一位置、可 diff、可 revert；bot 提交即审计链 |
| 回滚粒度 | feed 保留最近 2 个版本 + revert env 提交 | 只保留最新一版 | 设备侧 `opkg install netbird=<旧版>` 可直接降级 |
| 自动化闸门 | 仅 LuCI 包升级需人工合并 PR | 全自动；或全部人工 | netbird 二进制来源单一且可复现；LuCI 以 root 运行且上游审查强度弱（§11），保留唯一人工闸门 |
| 管理面 URL | 运行时由 CLI/LuCI 传入，持久化到 netbird profile 与 UCI | 编译期写死默认 URL | 自建用户必须能换服务端；默认 `api.netbird.io` 仅作兜底 |
| iStoreOS 上架 | 预编译 ipk PR（`istore-repo`）+ `openwrt-app-meta` 元数据 PR | 把自建 feed 注册为 iStore 源；给 iStore 提 Makefile | `istore-repo` 只收编译产物，索引由其 CI 生成；自建源无法注册 |

## 6. 仓库结构

```
netbird-pkgs/
├── .github/
│   ├── workflows/
│   │   ├── upstream-watch.yml
│   │   ├── luci-watch.yml
│   │   └── build-release.yml
│   └── dependabot.yml
├── packaging/
│   ├── netbird/
│   │   ├── control.in
│   │   └── netbird.init
│   ├── luci-app-netbird/
│   │   └── patches/0001-default-binary-source-opkg.patch
│   └── istore/app-meta-netbird/
│       ├── Makefile
│       └── logo.png
├── scripts/
│   ├── resolve-upstream.sh
│   ├── build-netbird-ipk.sh
│   ├── build-luci-ipk.sh
│   ├── make-istore.sh
│   ├── make-feed.sh
│   ├── sign-feed.sh
│   ├── verify-ipk.sh
│   ├── collect-licenses.sh
│   └── install-feed.sh
├── tests/
│   ├── build-netbird-ipk.bats
│   ├── make-feed.bats
│   ├── sign-feed.bats
│   ├── verify-ipk.bats
│   ├── resolve-upstream.bats
│   ├── make-istore.bats
│   └── netbird-init.bats
├── versions/
│   ├── netbird.env
│   └── luci-app-netbird.env
├── keys/netbird-pkgs.pub
├── docs/
│   ├── THREAT-MODEL.md
│   ├── REVIEW.md
│   ├── INSTALL.md
│   ├── ISTORE-PR.md
│   └── superpowers/specs/2026-10-31-netbird-pkgs-design.md
├── LICENSE
├── Makefile
└── README.md
```

说明：

- `Makefile` 提供 `lint`、`test`、`build`、`feed` 本地入口，CI 调用同一组目标，避免本地与 CI 行为分叉。
- 本地构建前置：Go `1.26.2`、GNU tar、gzip、git；`make test` 另需 bats-core；签名需要 `usign`（可选，未安装时跳过签名步骤）。
- `dist/` 为构建产物目录，加入 `.gitignore`。
- 设备端不安装本仓库任何脚本；`scripts/install-feed.sh` 由使用者显式下载执行（README 给出带 sha256 校验的命令）。

文档职责：

| 文件 | 内容 |
|---|---|
| `README.md` | 项目定位、feed 地址、安装命令、公钥指纹、构建方式、许可证 |
| `docs/INSTALL.md` | 设备接入、验收清单、故障排查、`service_triggers` 可选启用方法 |
| `docs/REVIEW.md` | 上游包审计结论、本地修正清单、LuCI 副作用与 NOTICE 缺口 |
| `docs/ISTORE-PR.md` | iStoreOS 上架：bundle 内容、PR 模板、元数据字段、被拒后的退路 |
| `docs/THREAT-MODEL.md` | 信任边界、攻击面、密钥轮换与残余风险 |

### `versions/netbird.env` — 唯一版本真相源

```
NETBIRD_VERSION=0.82.0
NETBIRD_COMMIT=<上游 tag 对应的 commit SHA>
NETBIRD_SHA256=<codeload tarball 的 sha256>
NETBIRD_PKG_RELEASE=1
```

任何构建开始前必须校验实际下载的 tarball 哈希与此值一致，不一致立即失败。`NETBIRD_COMMIT` 用于把发布版本钉到具体提交并写入发布说明。该文件每次版本变更由 bot 提交，形成可追溯的审计链；回滚即 revert 对应 commit。

`versions/luci-app-netbird.env` 结构相同（版本、commit、pkg release），由 `luci-watch.yml` 开 PR 更新，人工合并后生效。

## 7. 包设计：`netbird`

### 7.1 包内容

| 路径 | 说明 | 权限 |
|---|---|---|
| `/usr/bin/netbird` | 静态链接二进制（`-s -w` 裁剪） | 0755 |
| `/etc/init.d/netbird` | procd 开机脚本（修正版，§7.3） | 0755 |
| `/usr/share/licenses/netbird/LICENSE` | 上游 BSD-3-Clause 原文 | 0644 |
| `/usr/share/licenses/netbird/THIRD-PARTY-NOTICES.txt` | 构建时生成的第三方许可汇总（§22） | 0644 |
| `/etc/netbird/config.json` | 运行时由 netbird 生成，**不由包提供** | 0600（进程 `umask 077`） |

`control` 关键字段：

```
Package: netbird
Version: <upstream>-r<pkg_release>
Depends: kmod-wireguard, ca-bundle
Section: net
Category: Network
Architecture: aarch64_generic | x86_64
Installed-Size: <构建时计算，单位 KB>
Maintainer: xyonium
License: BSD-3-Clause
SourceDateEpoch: <SOURCE_DATE_EPOCH>
Description: NetBird client for OpenWrt
  ...（多行说明：来源、构建方式、仓库地址）
```

`ca-bundle` 为新增依赖：上游 OpenWrt 包未声明，但客户端与 `api.netbird.io` 的 TLS 握手需要 CA 根证书。

**conffiles**：本期不随包提供需要保留的用户可编辑配置，因此不生成 `conffiles`。`/etc/init.d/netbird` 必须随包升级被替换（修正要能落地），不能登记为 conffile。`/etc/netbird/config.json` 由运行时生成、不属包文件，升级与 sysupgrade 均保留（`/etc` 默认保留），卸载也不删除。

### 7.2 对上游的四处修正

均记录于 `docs/REVIEW.md`：

1. **删除 `. /lib/netifd/netifd-proto.sh`**
   该文件是 netifd 协议处理器库，仅被 `/lib/netifd/proto/*` 使用。netbird 不实现 netifd 协议，脚本中唯一相关的 `procd_add_interface_trigger` 实际定义在 `/lib/functions/procd.sh`（由 `rc.common` 自动加载）。该引用完全冗余（master 分支已移除，24.10 仍存在）。

2. **状态目录 `/root/.config/netbird` → `/etc/netbird`**
   netbird 默认把状态目录放在 `/var/lib/netbird`（OpenWrt 上是 tmpfs，重启即失），上游 master 的 init 改用 `/root/.config/netbird`（家目录在不同固件中的处理不一致）。`/etc` 是 OpenWrt 系统配置惯例位置，参与 sysupgrade 保留；`luci-app-netbird` 的 `_mgmt_url_from_config` 也按 `/etc/netbird/config.json` → `/var/lib/netbird/config.json` 的顺序探测。修正后凭据在重启与固件升级后都保留。

3. **增加 `procd_set_param respawn 3600 5 5`**
   上游未设置，进程崩溃后不会自动拉起。

4. **消费 `/etc/netbird.env` 的白名单变量**
   `luci-app-netbird` 的 uci-defaults 会创建 `/etc/netbird.env` 并写入 `NB_LOG_FILE=syslog`（`chmod 0644`），但上游 init 不读取该文件（上游注释亦承认），导致 LuCI 日志页拿不到 syslog 输出。本包在 init 内以**纯解析**方式读取白名单键（`NB_LOG_FILE`、`NB_LOG_LEVEL`），不 `source` 该文件，避免以 root 执行任意 shell。`NB_STATE_DIR` 不在白名单内，保持由本包固定为 `/etc/netbird`。

**不采用的改动**：上游社区包的 `service_triggers` 会在每次 wan 接口事件时重启 netbird。NetBird 客户端自带重连逻辑，wan 抖动时反复重启反而加剧断连。默认关闭，`docs/INSTALL.md` 保留启用方法。

### 7.3 init 脚本

```sh
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
	mkdir -p /var/lib/netbird
	umask 077

	procd_open_instance
	procd_set_param command /usr/bin/netbird service run
	procd_set_param env NB_CONFIG=/etc/netbird/config.json
	procd_append_param env NB_STATE_DIR=/etc/netbird
	procd_append_param env NB_DISABLE_SSH_CONFIG=1
	procd_append_param env NB_DNS_STATE_FILE=/var/lib/netbird/state.json
	append_env_from_file /etc/netbird.env
	procd_set_param pidfile /var/run/netbird.pid
	procd_set_param respawn 3600 5 5
	procd_close_instance
}

# 只读解析 KEY=VALUE，仅放行白名单变量；不 source 文件。
append_env_from_file() {
	local file="$1" line key val

	[ -f "$file" ] || return 0
	while IFS= read -r line; do
		case "$line" in
			''|'#'*) continue ;;
			*=*) ;;
			*) continue ;;
		esac
		key=${line%%=*}
		val=${line#*=}
		case "$key" in
			NB_LOG_FILE|NB_LOG_LEVEL|SSL_CERT_FILE) ;;
			*) continue ;;
		esac
		val=${val%\"}; val=${val#\"}
		procd_append_param env "$key=$val"
	done < "$file"
}
```

设计要点：

- `mkdir -p /var/lib/netbird` 每次启动执行（`/var` 是 tmpfs）。
- 不 `source` `/etc/netbird.env`：该文件由 LuCI 创建、权限 0644，按 shell 执行会让任何可写者获得 root 代码执行。解析器只接受 `KEY=VALUE` 行，并做变量名白名单（日志两项 + `SSL_CERT_FILE`，便于自建面使用私有 CA）。
- `NB_CONFIG` 显式指向 `/etc/netbird/config.json`：netbird 的配置默认路径是 `/var/lib/netbird/default.json`（tmpfs），不设该变量则配置不持久。这与上游 24.10 init 的设置一致，也是 LuCI 的探测路径。
- `umask 077` 保证 netbird 生成的 `config.json` 为 0600。
- `respawn 3600 5 5`：1 小时内失败超过 5 次则停止拉起，避免崩溃循环刷日志。

### 7.4 构建方式

```
CGO_ENABLED=0 GOOS=linux GOARCH=arm64|amd64 \
GOTOOLCHAIN=local GOFLAGS=-mod=readonly \
go build -trimpath -buildvcs=false -buildmode=exe \
  -tags load_wgnt_from_rsrc \
  -ldflags "-s -w \
    -X github.com/netbirdio/netbird/version.version=<ver> \
    -X main.commit=<commit> -X main.date=<SOURCE_DATE_EPOCH> \
    -X main.builtBy=netbird-pkgs" \
  -o dist/netbird ./client
```

- 参数对齐上游 release 的 goreleaser 配置：入口 `./client`、`CGO_ENABLED=0`、`-tags load_wgnt_from_rsrc`、注入 `version.version` 与 `main.commit/main.date/main.builtBy`。`main.builtBy` 标记为本仓库构建，便于在 `netbird version` 中区分官方产物。
- 上游根 Makefile 在 v0.82.0 中没有 build 目标（只有 lint/test），因此构建参数以 goreleaser 配置为准，不调用上游构建脚本。
- `main.date` 使用固定的 `SOURCE_DATE_EPOCH` 而非构建时刻，保证可复现。
- CGO 关闭保证静态链接，规避 glibc/musl 不兼容风险（阶段 1 验证，§19）。
- Go 工具链由 `actions/setup-go` 安装并锁定 `1.26.2`；`GOTOOLCHAIN=local` 阻止 `go.mod` 的 toolchain 指令触发自动下载，保证工具链唯一。
- `GOFLAGS=-mod=readonly` 启用，配合默认启用的 Go sumdb 校验依赖。
- 构建不执行上游测试套件或任何上游脚本，只编译（避免运行不受信代码）。
- 构建后立即执行 `netbird version`，输出必须等于 `<ver>`，否则失败；arm64 产物在 CI 中经 qemu-user 执行（§12.1 L3）。
- `SOURCE_DATE_EPOCH` 固定为 `versions/netbird.env` 对应提交的时间，供可复现构建使用（§7.5）。

ipk 组装不依赖 OpenWrt SDK：ipk 是包含 `debian-binary`、`control.tar.gz` 与 `data.tar.gz` 的 gzip 压缩 tar 归档，由 `scripts/build-netbird-ipk.sh` 用标准 `tar`/`gzip` 生成。

**为什么不是 OpenWrt Makefile**：OpenWrt 源码 feed 的 Go 包依赖 SDK 内的 `lang/golang`；24.10 只有 Go 1.23.12，无法编译 0.82.0，因此在官方源可用之前不存在可用的 Makefile 构建路径。iStore 商店只收预编译 ipk（§16），所以本仓库以标准 ipk 为交付物，`control`、init、文件布局与命名仍遵循 OpenWrt 包规范。

### 7.5 ipk 组装与可复现性

组装目录：

```
dist/pkg/
├── control/control                  # 无 conffiles（§7.1）
└── data/
    ├── usr/bin/netbird              # 0755
    ├── etc/init.d/netbird           # 0755
    └── usr/share/licenses/netbird/{LICENSE,THIRD-PARTY-NOTICES.txt}
```

归档要求：

- `control.tar.gz` 内含 `./control`；`data.tar.gz` 内含以 `./` 开头的相对路径。
- 外层归档按 `./debian-binary` → `./data.tar.gz` → `./control.tar.gz` 顺序打包，整体 gzip 压缩；与 OpenWrt 24.10 `ipkg-build` 的产物格式一致（gzip tar，非 ar）。
- 依赖 GNU tar（`--sort`、`--mtime`）；CI 的 `ubuntu-latest` 自带，macOS 本机构建需 `gtar` 或容器。
- 确定性：`tar --sort=name --mtime=@$SOURCE_DATE_EPOCH --owner=0 --group=0 --numeric-owner`，`gzip -9n`；`SOURCE_DATE_EPOCH` 取版本提交时间。
- 同一输入（版本、Go 工具链、`SOURCE_DATE_EPOCH`）两次构建的 ipk sha256 必须一致；该检查在阶段 3 起进入 CI（§12.1 L6）。
- 产物命名：`netbird_<upstream>-r<pkg_release>_<arch>.ipk`，同时输出同名 `.sha256`。文件名含版本且不可变，满足 iStore「每次上传不能重名」的要求。
- 架构命名：feed 产物用 `aarch64_generic` / `x86_64`；iStore 变体另行重打包为 `aarch64_cortex-a53`（§16），不覆盖原产物。

### 7.6 运行时依赖与系统集成

| 依赖 | 作用 | 说明 |
|---|---|---|
| `kmod-wireguard` | 内核 WireGuard 模块 | 与上游 OpenWrt 包保持一致；netbird 亦可使用内置 userspace wireguard-go。阶段 1 验证两种路径（§19） |
| `ca-bundle` | TLS 根证书 | 与官方或自建管理面握手所必需；自建面使用私有 CA 时见 §7.7 |

系统集成风险（验收清单见 §12.4）：

- **DNS**：netbird 会接管 DNS 解析；需确认与 dnsmasq 共存、不破坏现有内网解析。
- **防火墙**：iStoreOS 使用 fw4/nftables；netbird 自建规则需与既有规则共存。
- **SSH**：`NB_DISABLE_SSH_CONFIG=1` 阻止 netbird 修改 `sshd_config`。
- **开机顺序**：`START=99` 在 network 之后启动；wan 未就绪时 netbird 自行重连，不依赖 `service_triggers`。

### 7.7 配置、状态与自建管理面

#### 存放位置

| 路径 | 写入者 | 内容 | 重启后 | sysupgrade 后 |
|---|---|---|---|---|
| `/etc/config/netbird` | `luci-app-netbird`（UCI） | `management_url`、服务/防火墙/DNS/SSH 选项、`preshared_key`（应用负责 0600） | 保留 | 保留 |
| `/etc/config/netbird_bin` | `luci-app-netbird`（UCI） | `binary_source`、`release_url` | 保留 | 保留 |
| `/etc/netbird/config.json` | netbird（`NB_CONFIG`） | `ManagementURL`（对象）、WireGuard 私钥、预共享密钥、profile 选项；0600 | 保留 | 保留 |
| `/etc/netbird/` | netbird（`NB_STATE_DIR`） | profile 状态（`active_profile.json` 等） | 保留 | 保留 |
| `/var/lib/netbird/state.json` | netbird（`NB_DNS_STATE_FILE`） | DNS 运行状态 | 重建 | 不保留（tmpfs） |
| `/var/run/netbird.pid` | procd | 进程号 | 重建 | — |
| `/etc/netbird.env` | `luci-app-netbird` | 白名单环境变量（`NB_LOG_FILE`、`NB_LOG_LEVEL`、可选 `SSL_CERT_FILE`） | 保留 | 保留 |
| `/etc/opkg/{customfeeds.conf,keys/}` | `install-feed.sh` | feed 地址与信任公钥 | 保留 | 保留 |

要点：

- 为什么 LuCI 的设置看起来「永久存在 `/etc/config`」：这是 OpenWrt 的 UCI 约定，`/etc/config` 在 sysupgrade 时默认保留，因此表现为持久存储。netbird 自己的 JSON 配置不在那里。
- OpenWrt 的 `/etc/config/*` 是 UCI 配置目录，`luci-app-netbird` 沿用它保存自己的设置；本设计**不改动**该约定，也不会把 netbird 的 JSON 配置塞进 `/etc/config`。
- netbird 自身的配置是 JSON，放 `/etc/netbird/config.json`；这与上游 24.10 init 的设置一致，也是 LuCI 的探测路径。
- `/var` 是 tmpfs，只放可重建的运行状态；设备身份与连接配置必须放 `/etc` 才能在重启和升级后保留。
- 备份/迁移设备身份 = 备份 `/etc/netbird/`（含私钥）与 `/etc/config/netbird`（含管理 URL 与选项）。
- 写放大权衡：把 netbird 状态目录放 `/etc` 会带来少量 overlay 写入；高频的 DNS 状态已移到 `/var/lib/netbird`（tmpfs），避免频繁写闪存。

#### 自建管理面（self-hosted）

本节只描述**客户端侧**如何指向自建管理面；服务端（management/signal/relay）的部署、证书签发与备份不在本仓库范围（见 §1 非目标），由使用者按官方 self-hosted 方案运维。

netbird 支持任意 management URL；`https://api.netbird.io:443` 只是未指定时的默认值。两条设置路径：

```sh
# CLI：一次性设置，成功后写入 /etc/netbird/config.json 的 ManagementURL
netbird up --management-url https://netbird.example.com --setup-key <KEY>
# 或从文件读取 setup key
netbird up --management-url https://netbird.example.com --setup-key-file /tmp/setup-key
```

```
LuCI：Services → NetBird → 认证页
  填入 Management URL 与 Setup Key → 前端调用 do_up
  URL 写入 UCI /etc/config/netbird 的 netbird.settings.management_url（非机密，用于展示与预填）
  ucode 后端拼 `netbird up --management-url … --setup-key …`（参数经 shell_quote）
```

- 只需配置 management URL：signal / relay 端点由管理面在注册响应中下发，无需本地逐项配置。
- `--management-url` 接受 `http(s)://host[:port]`；LuCI 后端校验 scheme 与 host。
- setup key 不落盘：LuCI 只保留打码 hint（前 6 字符 + `*`），CLI 参数随进程结束消失。
- 私有 CA：把 CA 追加进 `/etc/ssl/certs/ca-certificates.crt`（`/etc` 下持久，但 `ca-bundle` 升级后需重新追加），或在 `/etc/netbird.env` 设 `SSL_CERT_FILE=/etc/ssl/certs/<ca>.pem`（Go 在 CGO 关闭时读取该变量）。公共 CA（如 Let's Encrypt）无需额外操作。
- 验证：

```sh
netbird status                 # Management: Connected
netbird status --json | grep -o '"management"[^}]*'
reboot && netbird status       # 配置持久，重启后仍连接
```

## 8. 包设计：`luci-app-netbird`

### 8.1 来源与构建

- 来源：[looong-cat/luci-app-netbird](https://github.com/looong-cat/luci-app-netbird)，Apache-2.0。版本固定在具体 commit（当前 `cd812d9`，对应 `PKG_VERSION:=0.1.0`、`PKG_RELEASE:=26`）；若上游发布 tag，则优先按 tag 固定。
- 以 OpenWrt 24.10 SDK 构建；SDK 版本与 `openwrt/gh-action-sdk` 的 commit 均钉死（§10.5）。
- 该包为 ucode + JS + shell，不涉及 Go，不受 §3 的 Go 版本约束；`PKGARCH:=all`，一个产物适配两架构。
- 依赖（来自上游 `LUCI_EXTRA_DEPENDS`）：`netbird (>=0)`、`rpcd`、`rpcd-mod-ucode`、`ucode`、`ucode-mod-fs`、`ucode-mod-uci`、`luci-base`、`conntrack`。
- 该包**不自带** `/etc/init.d/netbird`，守护进程生命周期由本仓库 `netbird` 包提供的 init 负责（§7.3）——这保证两包组合后只有一份真实实现。
- 许可文件：SDK 构建默认不安装上游 `LICENSE`/`NOTICE`，由 `build-luci-ipk.sh` 显式放入 `/usr/share/doc/luci-app-netbird/`，并追加 Tailscale BSD-3 免责声明（§22）。

### 8.2 二进制来源固定为 `opkg`

上游默认 `netbird_bin.binary.binary_source=release`，首次连接时会从 GitHub 下载二进制并替换 `/usr/bin/netbird`（以符号链接方式），这是本设计要消除的额外攻击面与来源分叉。

采用**补丁**方式固定（`packaging/luci-app-netbird/patches/0001-default-binary-source-opkg.patch`）：

- 将 `root/etc/config/netbird_bin` 中 `binary_source` 默认值由 `release` 改为 `opkg`。
- 该文件是 conffile：补丁只影响**新安装**，已有配置不被覆盖。
- 上游 `_ensure_configured_binary` 仅在 `source=release` 时执行 GitHub 下载；默认改为 `opkg` 后，首次连接不会触发下载。
- 激活来源由 `/usr/bin/netbird` 是否为符号链接推导；默认安装下它是包提供的真实文件，故实际来源即 `opkg`。

**不采用** uci-defaults 强制覆盖：`uci set` 会无条件改写用户选择，且每次升级/首启都重跑；上游 `99-luci-app-netbird` 已按「二进制版本 == feed 记录」把默认设为 `opkg`，与补丁互补。

残余能力：GUI 仍允许管理员手动切换来源并下载二进制（root 主动操作），列入 §11 已知风险。

### 8.3 与 `netbird` 包的关系

- 管理 URL：应用把 `management_url` 存 UCI `/etc/config/netbird`（非机密，供展示/预填），并在 `do_up` 时通过 `netbird up --management-url` 传给客户端；实际生效值最终写入 `/etc/netbird/config.json`。
- 文件不冲突：`netbird` 包提供 `/usr/bin/netbird` 与 `/etc/init.d/netbird`；`luci-app-netbird` 只提供 `/etc/config/netbird*`、`netbird-settings`、监控脚本与 rpcd 后端。
- 上游 `luci-app-netbird` 会包装而非替换 daemon：其 `netbird-settings` 仅转发 `enable/start/stop` 到 `/etc/init.d/netbird`。
- 若用户手动切换为 `release` 来源，`/usr/bin/netbird` 会变成符号链接，破坏包对该路径的所有权；这是已知残余风险，默认配置不会触发。

### 8.4 已知副作用（验收覆盖）

其 uci-defaults 会：写入 `/etc/netbird.env`（0644，`NB_LOG_FILE=syslog`）、创建/改写 `firewall.netbird` zone、删除 `network.netbird`、向 `/etc/sysupgrade.conf` 追加条目。这些行为在 `docs/REVIEW.md` 记录，并由 §12.4 的设备验收覆盖（DNS、防火墙、SSH、重启）。

## 9. 签名与分发

### 9.1 Feed 布局

```
https://xyonium.github.io/netbird-pkgs/
├── aarch64_generic/{Packages,Packages.gz,Packages.sig,*.ipk}
├── x86_64/{...}
├── istore/{netbird_*_aarch64_cortex-a53.ipk, luci-app-netbird_*_all.ipk}
└── keys/netbird-pkgs.pub
```

`luci-app-netbird` 为 `Architecture: all`，同一 ipk 复制进两个架构目录并各自列入索引（设备只添加自己架构的 feed，因此不能放在共享目录）。

`istore/` 目录只用于手动安装与上架 artifact 备份，不是 opkg feed：其中的 aarch64 包是 `aarch64_cortex-a53` 变体（§16），混入主 feed 会导致架构不匹配。

### 9.2 签名机制

使用 OpenWrt 标准的 `usign`（从 [openwrt/usign](https://github.com/openwrt/usign) 源码在 CI 内编译，源码 commit 钉死）。

```
usign -G -s netbird-pkgs.sec -p netbird-pkgs.pub -c "netbird-pkgs feed signing key"
usign -S -m Packages -s netbird-pkgs.sec          # 默认输出 Packages.sig，与 OpenWrt 构建一致
usign -V -m Packages -p netbird-pkgs.pub          # 发布前自检（默认读取 Packages.sig）
usign -F -p netbird-pkgs.pub                      # 指纹，16 位小写十六进制
```

- 私钥以 base64 存入 GitHub Actions Secret `USIGN_SECRET_KEY_B64`，只在 `sign-publish` job 中解码注入。
- 公钥提交到 `keys/netbird-pkgs.pub`，并在 README 与 Release 说明中公示指纹。
- 只签 `Packages`，不单独签 ipk：索引内含每个 ipk 的 sha256，签名索引即覆盖全部产物。
- 设备端公钥文件名必须是 `usign -F -p` 输出的 16 位十六进制指纹（不是 sha256 前缀）；OpenWrt 的 `opkg-key` 正是这样做的。

### 9.3 密钥管理与轮换

| 场景 | 操作 | 设备侧 |
|---|---|---|
| 计划内轮换 | 生成新密钥对 → 先发布新公钥并通告（导入窗口约一周，与 `upstream-watch` 周期一致）→ 再切换到新钥签名 | 在窗口内导入新公钥；旧钥在 2 个发布周期后移除 |
| 应急轮换（私钥泄漏） | 立即撤销 Secret、生成新密钥、重签 feed、发布安全通告 | 导入新公钥并 `opkg update`；旧签名失效即拒绝安装 |
| 公钥丢失 | 从仓库或 Release 重新分发 | 重新下载并导入 |

- 私钥不加口令（CI 无人值守）；保护面是 GitHub Secret + `release` environment 的分支限制 + 仓库权限。
- 切换签名后 feed 只由新钥签名；未导入新公钥的设备会验签失败并拒绝更新（这是预期行为，不是静默降级）。因此计划内轮换必须先留出导入窗口并发布通告，应急轮换则立即切换并在通告中说明截止时间。

### 9.4 设备接入（一次性）

```sh
# 1. 导入公钥（文件名必须是 16 位指纹；opkg-key 自动处理）
wget -O /tmp/netbird-pkgs.pub https://xyonium.github.io/netbird-pkgs/keys/netbird-pkgs.pub
opkg-key add /tmp/netbird-pkgs.pub
# 若无 opkg-key：FP=$(usign -F -p /tmp/netbird-pkgs.pub); cp /tmp/netbird-pkgs.pub "/etc/opkg/keys/$FP"
ls /etc/opkg/keys/                 # 确认 16 位指纹文件已入库

# 2. 添加 feed（按设备架构；取最高优先级的非 all/noarch 架构）
ARCH=$(opkg print-architecture | awk '$1=="arch"{print $3, $2}' | sort -rn | awk 'NR==1{print $2}')
grep -q '^src/gz netbird-pkgs ' /etc/opkg/customfeeds.conf 2>/dev/null || \
  echo "src/gz netbird-pkgs https://xyonium.github.io/netbird-pkgs/$ARCH" >> /etc/opkg/customfeeds.conf

# 3. 安装
opkg update && opkg install netbird luci-app-netbird
```

以上步骤封装为 `scripts/install-feed.sh`（接口见 §13），支持一条命令完成，写入前展示变更并要求确认。`/etc/opkg/` 与 `/etc/netbird/` 均在 `/etc` 下，sysupgrade 后保留，无需重复接入。

opkg 会强制校验 `Packages.sig`，签名不匹配则拒绝安装。这是本方案唯一的信任锚点。

### 9.5 发布原子性与缓存

- 发布前在 workspace 内生成**完整** feed 树（两个架构 + istore + keys），校验通过后一次性部署到 Pages（`actions/upload-pages-artifact` + `actions/deploy-pages`，钉 SHA），不做逐文件追加。
- 部署前校验：`Packages.gz` 可解压、`usign -V` 通过、索引中每个 `Filename` 存在且 sha256 匹配。
- 上一版 ipk 从 GitHub Release 资产（而非 Actions artifact）重新取回加入索引；Actions artifact 有保留期，不能作为跨版本来源。
- Pages 对单个对象下发 `cache-control: max-age=600`，部署切换并非逐对象原子：客户端可能拿到新索引与旧缓存（或反之）。由于 ipk 文件名含版本且**不可变**，旧索引只会引用仍被保留的旧 ipk，因此一致性依赖「保留 2 个版本」；签名不匹配时客户端重试即可（缓存 10 分钟内过期）。发布说明提示 `opkg update` 失败可稍后重试。
- Release 资产不可变；发布失败时上一次 Pages 部署继续生效，修复后重跑（幂等，§14）。

## 10. 流水线设计

### 10.1 触发关系（修正 v1 的设计缺陷）

v1 假设 `upstream-watch` 更新 `versions/netbird.env` 后由 `push` 触发 `build-release`。该链路不成立：GitHub 明确，使用仓库 `GITHUB_TOKEN` 推送产生的事件不会启动新的 workflow run。因此定义为：

| 工作流 | 触发 | 职责 | 密钥 |
|---|---|---|---|
| `upstream-watch.yml` | `schedule`（周一 03:00 UTC）+ `workflow_dispatch` | 解析上游最新 release，提交 `versions/netbird.env` | 无 |
| `build-release.yml` | `workflow_run`（监听 upstream-watch 成功）+ `workflow_dispatch`（可指定版本重发） | 构建、签名、发布 | 签名私钥（`release` environment） |
| `luci-watch.yml` | `schedule` + `workflow_dispatch` | 发现 LuCI 新 tag，开 PR（含构建结论） | 无 |

选择 `workflow_run` 而非 `workflow_call`：`environment` 密钥在可复用工作流中的传递语义受限；独立工作流可正常工作。`build-release` 启动后先做幂等检查：若目标 tag/Release 已存在则跳过。

### 10.2 `upstream-watch.yml`

- 权限：`contents: write`（仅用于提交 env 文件）
- 流程：`scripts/resolve-upstream.sh` 查询 `api.github.com/repos/netbirdio/netbird/releases/latest` → 与 `versions/netbird.env` 比较 → 无变化则退出 → 下载 tarball、计算 sha256、解析 commit → 更新 env（新上游版本时 `PKG_RELEASE` 归 1）→ bot 提交
- 提交信息包含版本、commit 与触发 run id，形成审计链
- **不持有签名私钥**

### 10.3 `luci-watch.yml`

- 流程：查上游新版本（tag 优先，无 tag 时按 commit）→ 与 `versions/luci-app-netbird.env` 比较 → 有新版则更新 env、在分支上运行一次 SDK 构建验证（构建结论写入 PR 描述）→ 创建 PR → 不自动合并
- 原因：`GITHUB_TOKEN` 创建的 PR 不会触发 `pull_request` 工作流，因此验证必须在同一工作流内完成，PR 只承载人工评审与合并决定
- 理由：该应用以 root 运行、单一维护者、关注度有限（详见 §11），保留唯一的人工闸门

### 10.4 `build-release.yml`

**job `build`**（matrix：`aarch64_generic→arm64`、`x86_64→amd64`）

1. checkout 默认分支
2. 下载源码 tarball，校验 sha256 与 `versions/netbird.env` 一致
3. `actions/setup-go`（钉 SHA，版本 `1.26.2`）
4. `go build`（参数见 §7.4）
5. `scripts/collect-licenses.sh` 生成第三方许可汇总
6. `scripts/build-netbird-ipk.sh` 组装 ipk
7. `scripts/verify-ipk.sh` 自检（§12.3）
8. 上传 artifact，并生成 `SHA256SUMS` 清单

**job `build-luci`**

1. checkout 上游固定版本，应用 §8.2 补丁
2. OpenWrt SDK 构建 `luci-app-netbird`（SDK 版本与 action commit 钉死）
3. `scripts/verify-ipk.sh` 的对应子集
4. 上传 artifact + `SHA256SUMS`

**job `sign-publish`**（`needs: [build, build-luci]`，`environment: release`）

1. 下载全部 artifact，核对 `SHA256SUMS`（防止 artifact 被替换）
2. 从 GitHub Release 取回上一版 ipk（保留 2 个版本）
3. `scripts/make-feed.sh` 重建三个 feed 目录的索引；`Architecture: all` 的 LuCI ipk 复制进两个架构目录并各自列入索引
4. `scripts/make-istore.sh` 生成 iStore 上架 bundle（aarch64_cortex-a53 重打包 + x86_64/LuCI/i18n 复制 + 元数据渲染），随 Release 发布
5. `scripts/sign-feed.sh` 签名并自验签
6. 创建 GitHub Release（tag `v<upstream>-r<pkg_release>`，资产含 ipk、`SHA256SUMS`、许可汇总）
7. `actions/attest-build-provenance` 生成 SLSA provenance
8. `actions/upload-pages-artifact` 打包整棵 feed 树

**job `deploy-pages`**（`needs: sign-publish`，`environment: github-pages`）

1. `actions/deploy-pages` 原子部署
2. 部署后对公开 URL 做一次抽样校验（索引可下载、`Packages.sig` 可验签）

说明：一个 job 只能关联一个 environment，而签名密钥需要 `release` environment、Pages 部署需要 `github-pages` environment，因此拆成两个 job；`deploy-pages` 不接触签名私钥。

### 10.5 并发、缓存与权限

- 并发：`concurrency: {group: release, cancel-in-progress: false}`，避免两次发布交错。
- 超时：`build` 30 分钟、`build-luci` 30 分钟、`sign-publish` 15 分钟、`deploy-pages` 10 分钟。
- 缓存：Go module 缓存按 `版本 + Go 版本` 建 key；SDK 与 ccache 不缓存（保持构建可解释）。
- 权限：全局默认 `contents: read`；`sign-publish` 提权为 `contents: write`、`attestations: write`、`id-token: write`；`deploy-pages` 提权为 `pages: write`、`id-token: write`。
- 所有 `uses:` 钉到完整 commit SHA，行尾注释版本；由 Dependabot 周更 PR（`.github/dependabot.yml`，覆盖 `github-actions` 生态）。
- 不将 `${{ }}` 直接插入 `run:` 脚本，统一经 `env:` 中转。
- 构建 job 不注入任何 Secret；发布 job 不执行上游代码。

## 11. 安全模型

### 信任边界

| 组件 | 权限 | 风险 |
|---|---|---|
| `netbird` 二进制 | root | WireGuard 私钥必然落盘 |
| `luci-app-netbird` | root（LuCI/ubus） | 可读任意文件，含 `config.json` |
| 本仓库 CI | 写 Release + 持签名私钥 | 上游投毒可致污染产物 |
| `release` environment 密钥 | 仅签名 job 可见 | 工作流配置错误会扩大暴露面 |
| iStore 上架后的分发 | 由 iStoreOS 的 feed 信任 | 脱离本仓库 `usign` 校验，版本可能滞后 |

**任何** LuCI 应用以 root 运行，理论上都能读取私钥。因此控制目标不是「阻止单点访问」，而是「限制可信集合 + 可检测 + 可撤销」。

### 对 `luci-app-netbird` 的静态审计结论（2026-10-31，commit `cd812d9`）

已核查的正面证据：

| 检查项 | 结果 |
|---|---|
| 代码混淆 | 无 `eval` / `base64 -d` / `String.fromCharCode` / `/dev/tcp` |
| 外发域名 | 仅 `api.github.com` 与 `github.com/netbirdio/*`（版本查询/下载官方二进制） |
| `setup_key` 持久化 | 不落盘；仅存打码 hint（前 6 字符 + `*`）；传参经 `shell_quote`；stdout 回显前替换为 `***` |
| `config.json` 访问 | 只读，仅用于展示预填管理 URL |
| 管理 URL 存储 | UCI `netbird.settings.management_url`，非机密；setup key 不落盘 |
| ACL 范围 | 仅 `uci: netbird, netbird_bin` + 自身 ubus 对象；**无 file 权限、无任意 shell** |
| 配置文件权限 | `chmod 0600`，纳入 `sysupgrade.conf` |
| 重连守护脚本 | 无网络请求，不读取配置文件 |
| daemon 生命周期 | 不替换 init，仅转发 `enable/start/stop` 到 `/etc/init.d/netbird` |

负面/风险项：

1. 上游 README 自述「几乎所有代码是 vibe coding 写的」，逐行人工审查保证较弱
2. 57 stars、单一维护者，缺乏多人监督冗余
3. 其发布流水线使用 `openwrt/gh-action-sdk@main`（浮动引用）
4. 内置二进制版本管理可从 GitHub 下载并替换 `/usr/bin/netbird`（额外攻击面）；本设计默认固定为 `opkg`，但 GUI 仍保留该能力
5. 提供 `curl | sh` 一键安装脚本 —— **本项目禁用此路径**
6. 必然瞬时可见 `setup_key`（GUI 封装固有属性）
7. 其 NOTICE 缺少 Tailscale BSD-3 免责声明原文（上游已知缺口，§22）
8. uci-defaults 会改写 `firewall.netbird` 并删除 `network.netbird`，属预期外副作用

### 控制措施

1. 构建 job 与签名 job 分离，私钥不进构建环境
2. 全部 `uses:` 钉到完整 commit SHA，Dependabot 周更
3. `permissions:` 全局默认 `contents: read`，仅 publish job 提权
4. 不使用 `pull_request_target`；不将 `${{ }}` 直接插入 `run:` 脚本
5. 源码 tarball sha256 强校验；artifact 之间用 `SHA256SUMS` 互相校验
6. `GOFLAGS=-mod=readonly`，启用 Go sumdb；`GOTOOLCHAIN=local` 固定工具链
7. 构建不执行上游测试套件（避免运行不受信代码）
8. `-trimpath -buildvcs=false`，固定 `SOURCE_DATE_EPOCH`，追求可复现
9. `luci-app-netbird` 版本变更必须人工合并 PR
10. `setup_key` 在 NetBird 后台设为一次性/限时，异常时可在后台撤销设备
11. 签名私钥仅存于 `release` environment secret，environment 限制为默认分支
12. 发布产物附带 SLSA provenance 与 `SHA256SUMS`，可用 `gh attestation verify` 复核
13. 密钥轮换流程见 §9.3

### 残余风险（明确接受）

全自动发布意味着 CI 持有签名私钥。若上游仓库被投毒，产物会携带本仓库签名落到设备。补偿手段为 §10 的 provenance、§9.3 的轮换、§14 的恢复流程与 §12.5 的回滚，而非事前阻断。此风险已由使用者知情选择。

此外，`sha256` 校验只能防止首次获取之后的篡改，不能证明首次获取的 tarball 就是上游真实产物（bot 信任 GitHub API 的返回值）。若要更强保证，需要上游签名 release 或使用可验证构建，超出本期范围。

## 12. 测试与验证

### 12.1 分层策略

| 层 | 位置 | 内容 | 触发时机 |
|---|---|---|---|
| L1 静态检查 | `make lint` / CI | `shellcheck` 全部脚本（procd init 以 `--shell=ash` 运行并允许 `SC1128`/`SC2034`/`SC3043`，文件头写明指令）、`sh -n` init 脚本、`actionlint` 工作流、YAML 可解析 | 每次 push / PR |
| L2 脚本单元测试 | `tests/*.bats`（bats-core） | 版本解析、control 生成、索引生成、签名往返、失败路径 | 每次 push / PR |
| L3 构建集成 | CI（矩阵两架构） | 解包 ipk 校验结构；x86_64 直接执行 `netbird version`；arm64 经 qemu-user 执行 | push / 发布 |
| L4 Feed 集成 | CI（x86_64） | 本地生成索引 → 签名 → `usign -V` 验签 → 在 OpenWrt rootfs 中 `opkg install` 本 feed | 发布前（阶段 3 起） |
| L5 设备验收 | 真机（§12.4） | 安装、升级、降级、重启、sysupgrade、DNS/防火墙共存 | 每个发布版本 |
| L6 可复现性 | CI 夜间 | 两次独立构建产物 sha256 对比 | 夜间 + 发布前 |

原则：任何一层失败都不得发布。L1/L2 必须快（< 2 分钟），L3 允许 10 分钟，L4 允许 20 分钟。

### 12.2 脚本单元测试（bats-core）

`tests/` 下按脚本一文件，全部使用临时目录，不触碰仓库源树：

| 测试文件 | 用例要点 |
|---|---|
| `build-netbird-ipk.bats` | `control` 字段完整且版本/架构正确；不生成 `conffiles`；`/usr/bin/netbird` 权限 0755；缺失二进制时非零退出；重复执行产物 sha256 一致 |
| `make-feed.bats` | 索引按 `Package`+`Version` 稳定排序；`Filename` 为相对路径；`Size`/`SHA256` 与实际文件一致；只保留指定版本数；空目录行为 |
| `sign-feed.bats` | 签名后可验签；篡改 `Packages` 后验签失败；缺私钥时非零退出 |
| `verify-ipk.bats` | 架构不符、缺依赖、init 语法错误、非静态链接各自返回非零 |
| `resolve-upstream.bats` | 版本号比较；无新版本时输出 `CHANGED=0` |
| `make-istore.bats` | 重打包后 `Architecture` 变为 `aarch64_cortex-a53`，其余字段不变；bundle 目录/文件名符合 iStore 规范；元数据 Makefile 字段随版本渲染；不覆盖输入 ipk |
| `netbird-init.bats` | `append_env_from_file` 只放行 `NB_LOG_FILE`/`NB_LOG_LEVEL`/`SSL_CERT_FILE`；忽略注释、空行与非法格式；带引号的值被还原；init 全文中不出现对 `/etc/netbird.env` 的 `source`/`.` 调用 |

### 12.3 CI 校验清单

`scripts/verify-ipk.sh` 在 CI 与本地均可运行，检查项：

- 归档结构：外层可解，且恰好包含 `debian-binary`、`control.tar.gz`、`data.tar.gz`
- `control`：`Package`、`Version`（`<upstream>-r<pkg_release>`）、`Architecture`、`Depends` 含 `kmod-wireguard` 与 `ca-bundle`
- 文件清单白名单：仅允许 `/usr/bin/netbird`、`/etc/init.d/netbird`、许可文件
- `/usr/bin/netbird` 为静态链接（`file` 输出含 `statically linked`，且无 `PT_INTERP`）
- init 脚本 `sh -n` 通过
- 二进制自检：`netbird version` 输出与 `versions/netbird.env` 的版本一致（x86_64 原生；arm64 经 qemu）
- feed：`Packages.gz` 可解压、`usign -V` 验签通过、每个 `Filename` 对应文件存在且 sha256 一致
- iStore bundle：目录与文件名匹配 `bin/packages/<arch>/<category>/`；`Architecture` 与目录一致；`control` 可被 iStore CI 的 `tar -xOf … ./control.tar.gz | tar -xOz ./control` 提取出 `Package`；元数据 Makefile 的 `PKG_VERSION` 与主包一致

### 12.4 设备验收清单

```
# 安装与版本
opkg update && opkg install netbird luci-app-netbird
netbird version                    # 与发布版本一致
netbird status

# 服务生命周期
/etc/init.d/netbird enable && reboot
pgrep -f 'netbird service run'     # 重启后自动拉起
logread -e netbird | tail

# 自建管理面（self-hosted）
netbird up --management-url https://netbird.example.com --setup-key <KEY>
netbird status                     # Management: Connected
reboot
netbird status                     # 重启后仍连接；配置在 /etc/netbird/config.json
# LuCI 认证页应显示已保存的 Management URL；setup key 仅显示打码 hint

# 升级与降级
opkg update && opkg upgrade netbird
opkg install netbird=<上一版本>    # 降级路径必须可用

# 数据持久化
ls -l /etc/netbird/config.json     # 0600，升级后仍在
# sysupgrade 后再次检查该文件

# 与系统共存
nslookup <内网域名>                # DNS 正常（dnsmasq 与 netbird DNS 不冲突）
nft list ruleset | grep -i netbird # fw4/nftables 规则存在且不与其他规则冲突
grep -i netbird /etc/ssh/sshd_config || true   # 应无改动（NB_DISABLE_SSH_CONFIG=1）

# 卸载
opkg remove netbird                # 进程停止，/etc/netbird 保留
```

### 12.5 回滚

- 版本级：`opkg install netbird=<旧版本>`（feed 保留最近 2 版）
- 源级：revert `versions/netbird.env` 对应提交并重新发布
- 应急停用：`/etc/init.d/netbird stop && /etc/init.d/netbird disable`
- 坏版本下架：从索引移除并重新签名发布，Release 资产保留（已安装设备不受影响）

## 13. 脚本接口契约

所有脚本遵循同一约定：

- `#!/bin/sh` + `set -eu`；`LC_ALL=C`、`TZ=UTC`；禁止交互式提示
- 退出码：`0` 成功；`1` 运行失败（校验/构建/签名失败）；`2` 参数错误
- 产物写入 `dist/` 或指定 `--outdir`；日志与进度写 stderr；不在仓库源树内改动文件
- 临时目录用 `mktemp -d` 并在 `trap` 中清理；网络访问仅存在于 `resolve-upstream.sh` 与设备端 `install-feed.sh`
- 幂等：同一输入重复执行产生相同产物（配合 §7.5 的确定性归档）

| 脚本 | 参数 | 产物 / 输出 | 说明 |
|---|---|---|---|
| `resolve-upstream.sh` | `--repo <owner/name>` `[--env-file versions/netbird.env]` | stdout：`VERSION=… COMMIT=… SHA256=… CHANGED=0\|1` | 只查询 GitHub API；无变化时 `CHANGED=0` 且不下载 |
| `build-netbird-ipk.sh` | `--arch <aarch64_generic\|x86_64>` `--version` `--binary` `--outdir` `[--pkg-release N]` | `<outdir>/netbird_<ver>-r<N>_<arch>.ipk` + `.sha256` | 读取 `packaging/netbird/`；校验二进制可执行；固定 `SOURCE_DATE_EPOCH` |
| `collect-licenses.sh` | `--mod-cache <dir>` `--out <file>` | `THIRD-PARTY-NOTICES.txt` | 遍历模块缓存收集 LICENSE，按模块名排序；缺失许可的模块记入报告但不中断（人工复核） |
| `build-luci-ipk.sh` | `--version` `--sdk <dir>` `--outdir` | `luci-app-netbird_<ver>_all.ipk` + `.sha256` | 调用 OpenWrt SDK，应用 §8.2 补丁，补装 LICENSE/NOTICE（§22） |
| `make-feed.sh` | `--dir <feed>` `--arch <arch>` `[--retain N=2]` `[--ipk <path>]…` | 更新 `<feed>/Packages`、`Packages.gz` | 索引字段：`Package`、`Version`、`Depends`、`Architecture`、`Installed-Size`、`Filename`、`Size`、`SHA256sum`、`Section`、`Category`、`License`、`Description`；按 `Package`+`Version` 排序，`gzip -9n`；保留 N 个版本；拒绝索引中列出的文件缺失 |
| `sign-feed.sh` | `--dir <feed>` `--key <secret-key>` 或 `--verify <pub-key>` | `Packages.sig`；`--verify` 时仅校验 | 签名后立刻自验签，失败即非零退出 |
| `verify-ipk.sh` | `--ipk <path>` `--arch <arch>` | stdout 检查清单 | 对应 §12.3；失败项逐条列出 |
| `make-istore.sh` | `--ipk-dir <dir>` `--outdir <dist/istore>` `[--version]` `[--pkg-release]` | iStore bundle（`bin/packages/...` + `applications/app-meta-netbird/`） | 重打包 aarch64 → `aarch64_cortex-a53`；复制 x86_64 / `all` 包；渲染元数据；校验目录与命名（§16） |
| `install-feed.sh` | `--feed-url` `[--key-url]` `[--arch auto]` `[--yes]` | 设备端配置变更 | root 运行；优先用 `opkg-key add` 导入公钥（回退 `usign -F` + 复制到 `/etc/opkg/keys/<16 位指纹>`）；幂等写入 `/etc/opkg/customfeeds.conf`；`--arch auto` 由 `opkg print-architecture` 取最高优先级架构推断 |

补充约束：

- 所有脚本由 `tests/` 覆盖（§12.2）；新增脚本必须同时提交测试
- 构建脚本不得执行上游仓库中的任何脚本或测试（只编译），避免运行不受信代码
- `install-feed.sh` 在写入前展示将要执行的变更，并要求显式确认（`--yes` 可跳过）

## 14. 失败模式与恢复

| 场景 | 检测方式 | 自动行为 | 人工恢复 |
|---|---|---|---|
| GitHub API 限流/5xx | HTTP 状态码 | 指数退避重试 3 次后失败；不写 env | 手动重跑 `upstream-watch` |
| 源码哈希不匹配 | 下载后 sha256 比对 | 构建前硬失败，不产出 artifact | 确认上游是否重打包；核对后手工更新 env 并走 PR |
| Go 工具链不可用/版本漂移 | `go version` 校验 | 构建失败 | 修正 `setup-go` 版本，走 Dependabot PR |
| 编译失败（上游改动） | `go build` 退出码 | 失败，无产物 | 人工评估补丁或暂缓升级 |
| 签名密钥缺失/签名失败 | 步骤失败 | 不更新 feed，不创建 Release | 检查 Secret 与 environment；重跑发布 |
| 发布中途失败 | 部署步骤失败或部署后校验不一致 | 上一次部署保持生效 | 修复后重跑 `build-release`（幂等） |
| 索引已更新但 ipk 缺失 | `verify-ipk` / feed 校验 | 发布前拦截 | 重跑；feed 保留上一版保证可用 |
| 设备安装依赖缺失 | `opkg install` 报错 | 设备侧不安装 | 按 `docs/INSTALL.md` 排查依赖源 |
| 升级后服务不启动 | 验收清单 / `logread` | procd 依 `respawn` 重试 | `opkg install netbird=<旧版>` 回滚 |
| 上游投毒/密钥泄露 | 安全通告或审计 | 无自动检测 | 走 §9.3 密钥轮换与 §12.5 回滚，发布安全通告 |

原则：构建与发布全流程「失败即停」，不自动改写 `versions/netbird.env` 中的哈希，也不在失败后自动重试发布（避免掩盖问题）。

## 15. 版本与发布策略

- **版本号**：`<upstream>-r<pkg_release>`。仅打包脚本、init 脚本或依赖变化时递增 `PKG_RELEASE`，上游版本不变。
- **真相源字段**：`NETBIRD_VERSION`、`NETBIRD_COMMIT`、`NETBIRD_SHA256`、`NETBIRD_PKG_RELEASE`。
- **Release 标签**：`v<upstream>-r<pkg_release>`，与 feed 索引中的版本一一对应。
- **Feed 保留**：每架构保留最近 2 个上游版本；同一上游版本只保留最高 `PKG_RELEASE`。更早版本从索引移除，但 Release 资产永久保留。
- **发布说明**：上游变更链接、本项目打包变更、源码 commit 与 sha256、签名公钥指纹、安装/升级命令、对应源码获取方式（§22）。
- **发布不可变**：已存在的 tag 与 Release 不覆盖；需要重发时递增 `PKG_RELEASE`。
- **审计链**：`versions/netbird.env` 的提交历史即版本台账；bot 提交信息包含版本、commit 与触发工作流 run id。

## 16. iStoreOS 上架（PR 路径）

### 机制事实（2026-11-01 核实）

- [`istoreos/istore-repo`](https://github.com/istoreos/istore-repo) 存放**已编译**的 ipk/apk，不是源码 Makefile 仓库；索引在合并后由上游 CI 用 `openwrt-sdk-mini-25.12.2` 生成。
- PR 目标分支必须是 `pending`；只允许在 `bin/` 下新增包文件，不能改 `.github/workflows`；合并时自动清理同包旧版本。
- 目录：`bin/packages/<arch>/<category>/<pkg>_<version>-r<release>_<arch>.ipk`；架构目录为 `aarch64_cortex-a53`、`x86_64`、`all`；类别常用 `nas`（二进制）与 `nas_luci`（LuCI）。
- 文件名必须带版本且不可重复；aarch64 的 ipk 必须标为 `aarch64_cortex-a53`。
- 新软件还需向 [`linkease/openwrt-app-meta`](https://github.com/linkease/openwrt-app-meta) 提交 `applications/app-meta-<name>/{Makefile,logo.png}`；`istore-repo` 的 PR 模板要求附上该 PR 链接。
- README 规定「不要提交 OpenWrt 官方仓库已有的包」，但存在反例：`tailscale` 在官方源，`istore-repo` 仍收录 `tailscale_1.104.1-r1_*`。因此 netbird 可以按「官方版本过旧」提交并说明，但不能保证被接受。

### 本仓库产出：PR-ready bundle

`scripts/make-istore.sh` 生成一个可直接复制进 PR 的目录：

```
dist/istore/
├── bin/packages/
│   ├── aarch64_cortex-a53/nas/netbird_<ver>-r<N>_aarch64_cortex-a53.ipk
│   ├── x86_64/nas/netbird_<ver>-r<N>_x86_64.ipk
│   └── all/nas_luci/
│       ├── luci-app-netbird_<luci-ver>-r<rel>_all.ipk
│       └── luci-i18n-netbird-zh-cn_<luci-ver>-r<rel>_all.ipk（若 luci.mk 产出）
└── applications/app-meta-netbird/
    ├── Makefile
    └── logo.png
```

- aarch64 变体由 `aarch64_generic` 产物重打包 `Architecture` 得到，二进制不变；x86_64 直接复制。
- 元数据 `Makefile` 由 `packaging/istore/app-meta-netbird/Makefile` 渲染（含标准头与 `include ../../meta.mk`），关键字段：

```
PKG_VERSION:=<netbird 版本>
PKG_RELEASE:=<pkg release>
META_TITLE:=NetBird
META_TITLE.en:=NetBird
META_DEPENDS:=+netbird +luci-app-netbird
META_DESCRIPTION:=基于 WireGuard 的自托管虚拟局域网客户端，支持自建管理面
META_DESCRIPTION.en:=WireGuard-based mesh VPN client with self-hosted management support
META_AUTHOR:=NetBird GmbH / looong-cat
META_ARCH:=x86_64 aarch64
META_TAGS:=networking service
META_LUCI_ENTRY:=/cgi-bin/luci/admin/services/netbird
META_WEBSITE:=https://netbird.io
```

- `logo.png` ≤ 256×256、≤ 50KB；使用 NetBird 官方标志并注明来源，遵循其商标/品牌使用政策。
- 若 `luci-app-netbird` 产出 `luci-i18n-netbird-zh-cn`，一并放入 `all/nas_luci/`（与 `tailscale` 的做法一致）。

### PR 步骤（人工执行，不进 CI 自动化）

1. **元数据 PR**：fork `openwrt-app-meta` → 从 `main` 拉临时分支 → 把 `dist/istore/applications/app-meta-netbird/` 原样复制进 fork 的 `applications/` → 提交 PR。
2. **ipk PR**：fork `istore-repo` → 从 `main` 拉临时分支 → 把 `dist/istore/bin/packages/**` 原样复制到 fork 的 `bin/packages/**` → 目标分支选 `pending`。
3. 填写 PR 模板：文件已上传、目标分支 `pending`、源码仓库 `https://github.com/xyonium/netbird-pkgs`、元数据 PR 链接。
4. PR 描述说明：官方源 `netbird` 仍为 0.59.13，本包为 0.82.0；`luci-app-netbird` 为第三方包（官方源没有），两者配合使用。
5. 合并由上游维护者决定；索引由上游 CI 生成，本仓库**不写** iStore 索引、不改其 workflows。

### 风险与边界

- **规则冲突**：netbird 属于官方源已有包；`tailscale` 先例说明可尝试，但不保证接受。若被拒：保留自建签名 feed（功能不受影响），只上架官方没有的 `luci-app-netbird`。
- **信任链转移**：上架后由 iStore 分发，不再经过本仓库的 `usign` 校验；iStoreOS 的 feed 信任由系统负责。自建签名 feed 仍是权威来源，设备可同时添加，opkg 按版本取新。
- **架构差异**：iStore 要求 aarch64 用 `aarch64_cortex-a53`；设备实际 opkg 架构是 `aarch64_generic`。手动安装请走自建 feed，不要混用两套架构的包（§19 待验证 iStore 安装器的架构处理）。
- **仅 ipk**：本期只交 opkg 产物（24.10）；25.x 的 apk 另立工作项。
- **元数据维护**：`PKG_VERSION` 跟随 netbird 主包；`PKG_RELEASE` 在版本不变、只改元数据时递增。

## 17. OPNsense 扩展（独立立项）

### 机制事实

| 包 | 来源 | 25.7 版本 | 26.1 版本 |
|---|---|---|---|
| `os-netbird` | `opnsense/plugins` `security/netbird`（纯 GUI/MVC） | 1.1 | 1.3_3 |
| `netbird` | FreeBSD ports `security/netbird`（二进制） | 0.60.7 | 0.72.2 |

插件 Makefile 仅声明 `PLUGIN_DEPENDS= netbird`。即：GUI 层基本无需更新，滞后的是二进制包。

### 可行性

Go 可原生交叉编译到 `freebsd/amd64`（ports 使用 `-tags freebsd`）。因此只需重建 `netbird` 二进制包，`os-netbird` 插件保持官方版本。主要难点是在 Linux runner 上产出合法 FreeBSD `.pkg`，两条候选路径：

1. 通过 `vmactions/freebsd-vm` 在真 FreeBSD 中执行 `pkg create`（可靠性高）
2. 在 Linux 上手工组装 pkg 归档（`+MANIFEST` / `+DESC` + payload，技术可行但需验证）

该部分**不在本期实施范围**，需单独设计并验证。

## 18. 分阶段实施

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| 0 | 仓库初始化：远程仓库、默认分支、Pages、`release` environment、usign 密钥对、公钥入库、分支保护、Dependabot | Pages 可访问；签名密钥就位；§21 输入项确认 |
| 1 | 仓库骨架 + 构建脚本 + 单元测试，本机跑通 | `make lint test` 全绿；产出 ipk；`opkg install` 成功；`netbird version` 正确 |
| 2 | 索引 + 签名 + 设备接入 | 两台设备 `opkg update` 验签通过，可安装、升级、降级 |
| 3 | 全自动流水线 + 可复现性 | 新版自动落地并可在设备上升级；两次构建 sha256 一致；provenance 可验证 |
| 4 | LuCI 集成与自建面 | Services → NetBird 可访问；填入自建 management URL + setup key 能连接；重启后仍保持；`binary_source` 默认为 `opkg`；日志页有输出 |
| 5 | iStoreOS 上架 | `make-istore.sh` 产出合规 bundle；元数据 PR + ipk PR 提交到 `pending`；按维护者反馈处理；被拒则记录原因，自建 feed 不受影响 |
| 6 | OPNsense | 独立设计文档与实施 |

每个阶段结束都必须通过对应的测试层（§12.1）与设备验收（§12.4），未通过不进下一阶段。

## 19. 待验证事项

以下在实施阶段 1 必须实测确认，若结论不符将调整设计：

1. `netbird` 客户端在 `CGO_ENABLED=0` 下能完整构建且运行正常
2. 静态二进制在 iStoreOS（musl + 6.6 内核）上可执行
3. `luci-app-netbird` 的依赖 `rpcd-mod-ucode`、`ucode`、`ucode-mod-fs`、`ucode-mod-uci`、`conntrack` 在 iStoreOS 24.10 上可获取
4. GitHub Pages 作为 feed 托管的可用性与中国网络环境下的可达性
5. `usign` 在 CI 中可从源码构建，签名产物能被设备上的 opkg 正确校验
6. Go `1.26.2` 在 `ubuntu-latest` runner 上由 `setup-go` 可安装，且 `GOTOOLCHAIN=local` 下构建正常
7. arm64 二进制可在 CI 中经 qemu-user 执行 `netbird version`
8. `kmod-wireguard` 与目标内核版本匹配；或通过 `NB_WG_KERNEL_DISABLED` 等运行时开关确认 userspace WireGuard 路径可用，从而评估是否保留该依赖
9. netbird 的 DNS 接管与 dnsmasq 共存、以及 fw4/nftables 规则不冲突
10. `workflow_run` 触发的发布 job 能正确读取 `release` environment 的密钥
11. opkg 在升级时对 `/etc/init.d/netbird`（非 conffile）的替换行为符合预期
12. Pages 的 `cache-control: max-age=600` 在真实设备上不造成可感知的升级失败（必要时调整发布顺序或提示重试）
13. `-X main.commit`、`-X main.date`、`-X main.builtBy` 注入后 `netbird version` 输出格式符合预期，且两次构建一致
14. 自建管理面的 signal/relay 端点在目标网络可达；私有 CA 通过系统信任库或 `SSL_CERT_FILE` 生效
15. iStore 维护者是否接受 netbird（官方源已有包）；不接受时退化为只上架 `luci-app-netbird`
16. iStore 安装器在 `aarch64_generic` 设备上安装 `aarch64_cortex-a53` ipk 的架构处理（是否 force-arch）
17. `openwrt-app-meta` 的 CI 对 logo、字段、版本的具体校验（提交前按其 CI 规则预检）

## 20. 附录：事实核查记录

| 项目 | 数值 | 来源 |
|---|---|---|
| NetBird 最新版 | v0.82.0（2026-10-29） | GitHub API `releases/latest` |
| NetBird go 要求 | go 1.26.0，toolchain ≥ 1.26.2 | v0.82.0 `go.mod` |
| NetBird 客户端许可 | BSD-3-Clause（根 LICENSE 明示排除 `management/`、`signal/`、`relay/`、`combined/` 的 AGPLv3） | v0.82.0 `LICENSE` |
| 客户端二进制嵌入模块数 | 121，含 `netbirdio/wireguard-go`(MIT)、`quic-go`(MIT)、`pion/turn`(MIT)、`gvisor`(Apache-2.0) | `go version -m`（上游 release 二进制） |
| OpenWrt 24.10 netbird | 0.59.13 | `openwrt/packages` `openwrt-24.10` 分支 Makefile |
| OpenWrt master netbird | 0.81.4 | `openwrt/packages` master Makefile |
| OpenWrt 24.10 golang | 1.23.12 | `lang/golang/golang/Makefile` |
| 快照源包格式 | `.apk` | `downloads.openwrt.org` 实测 |
| `luci-app-netbird` | 0.1.0-r26，`PKGARCH:=all`，Apache-2.0 | 上游 Makefile（commit `cd812d9`） |
| `luci-app-netbird` 依赖 | netbird, rpcd, rpcd-mod-ucode, ucode, ucode-mod-fs, ucode-mod-uci, luci-base, conntrack | 上游 Makefile `LUCI_EXTRA_DEPENDS` |
| `luci-app-netbird` 二进制默认来源 | `netbird_bin.binary.binary_source=release` | 上游 `root/etc/config/netbird_bin` |
| `luci-app-netbird` 写 `/etc/netbird.env` | 仅追加 `NB_LOG_FILE=syslog`，`chmod 0644` | 上游 `root/etc/uci-defaults/99-luci-app-netbird` |
| 上游 init 是否消费 `/etc/netbird.env` | 否；`files/` 下仅有 `netbird.init` | `openwrt/packages` `net/netbird/files/` |
| 上游 24.10 init | 引用 `netifd-proto.sh`；设 `NB_CONFIG=/etc/netbird/config.json`；wan 接口 trigger；无 respawn | 同上（`openwrt-24.10` 分支） |
| 上游 master init | 不引用 netifd；设 `NB_STATE_DIR=/root/.config/netbird`、`NB_DISABLE_SSH_CONFIG=1`、`NB_DNS_STATE_FILE=/var/lib/netbird/state.json`；无 respawn | 同上（`master` 分支） |
| netbird 默认路径 | 状态目录 `/var/lib/netbird`；配置 `/var/lib/netbird/default.json` | v0.82.0 `client/configs/configs.go`、`client/internal/profilemanager/service.go` |
| 被 netbird 认可的 NB_* 变量 | `NB_CONFIG`、`NB_STATE_DIR`、`NB_DNS_STATE_FILE`、`NB_DISABLE_SSH_CONFIG`、`NB_LOG_FILE`、`NB_LOG_LEVEL` | v0.82.0 `client/cmd/root.go` 等（`SetFlagsFromEnvVars` 映射全部 flag） |
| 上游构建参数 | goreleaser：`./client`、`CGO_ENABLED=0`、`-tags load_wgnt_from_rsrc`、注入 `version.version` 与 `main.commit/main.date/main.builtBy` | v0.82.0 `.goreleaser.yaml` |
| usign 签名 | `usign -S -m Packages -s key` 默认产出 `Packages.sig` | `openwrt/package/Makefile` |
| usign 指纹与 key 目录 | 16 位小写十六进制；`/etc/opkg/keys/<指纹>`；`opkg-key` 按此命名 | `usign` 源码、`openwrt/files/opkg-key`、24.10 `openwrt-keyring` |
| ipk 外层格式 | gzip tar，顺序 `./debian-binary`、`./data.tar.gz`、`./control.tar.gz`（非 ar） | `openwrt/scripts/ipkg-build`，24.10 实际 ipk 验证 |
| Pages 缓存 | 单对象 `cache-control: max-age=600` | GitHub Pages 实际响应头 |
| netbird 默认管理面 | `https://api.netbird.io:443`，`--management-url` 覆盖 | v0.82.0 `client/internal/profilemanager/config.go`、`client/cmd/root.go` |
| profile 路径 | 默认 `<NB_STATE_DIR>/default.json`；`--config`（`NB_CONFIG`）覆盖；旧路径 `/etc/netbird/config.json` 自动迁移 | v0.82.0 `profilemanager/service.go`、`root.go`、`profilemanager.NewServiceManager` |
| LuCI 管理 URL 存储 | UCI `netbird.settings.management_url`；`do_up` 拼 `netbird up --management-url … --setup-key …` | 上游 `netbird.uc`（commit `cd812d9`） |
| LuCI 探测 config.json | 依次探测 `/etc/netbird/config.json`、`/var/lib/netbird/config.json` | 同上 `_mgmt_url_from_config` |
| FreeBSD port netbird | 0.81.5 | `cgit.freebsd.org` |
| OPNsense 25.7 源 | `os-netbird-1.1`、`netbird-0.60.7` | `pkg.opnsense.org` 目录列表 |
| OPNsense 26.1 源 | `os-netbird-1.3_3`、`netbird-0.72.2` | 同上 |
| `GITHUB_TOKEN` 推送与工作流触发 | 推送产生的事件不会启动新的 workflow run | GitHub Actions 文档 |
| istore-repo 内容 | 已编译的 ipk/apk，不是源码 | `istoreos/istore-repo` README |
| iStore PR 目标分支 | `pending`；只允许新增 `bin/` 文件；禁止改 workflows | 其 README、`pr.yml` |
| iStore ipk 目录 | `bin/packages/<arch>/<category>/`；arch = `aarch64_cortex-a53` / `x86_64` / `all` | 仓库树、README |
| iStore aarch64 要求 | ipk 必须是 `aarch64_cortex-a53` | README |
| iStore 官方源去重规则 | README 要求不提交官方源已有包；但 `tailscale` 为反例 | README、仓库树 |
| iStore 元数据仓库 | `linkease/openwrt-app-meta`，`applications/app-meta-<name>/{Makefile,logo.png}` | 其 README |
| iStore 元数据字段 | `PKG_VERSION`/`PKG_RELEASE`/`META_TITLE`/`META_DEPENDS`/`META_ARCH`/`META_LUCI_ENTRY`/`META_WEBSITE` 等 | 其 README 与样例 Makefile |
| iStore PR 模板要求 | 勾选目标分支、文件已上传、元数据 PR 链接、源码仓库 | `.github/pull_request_template.md` |
| iStore CI 校验 | 仅从 ipk 的 `control.tar.gz` 提取 `Package` 字段（其余靠索引生成） | 其 `pr.yml` |

## 21. 需要使用者提供的信息

本文档中的 `xyonium` 指 GitHub 用户名占位符；`<ver>`、`<commit>`、`<arch>`、`<pkg_release>` 等为脚本参数或构建变量占位符，取值规则见 §6、§7.4、§15。实施阶段 0 开始前需确认以下输入，确认后一次替换到所有文件中：

| 输入项 | 用途 | 当前状态 | 建议 |
|---|---|---|---|
| GitHub 用户名 / 组织 | Pages 域名 `https://xyonium.github.io/netbird-pkgs/`、仓库地址 | **已确认：`xyonium`**（`gh` 已登录）；仓库尚未创建，属阶段 0 | — |
| 仓库可见性 | Pages 需公开仓库或付费计划；SLSA provenance 在公开仓库可用 | 待确认 | 公开 |
| 默认分支名 | 工作流触发与分支保护 | 待确认 | `main` |
| usign 密钥口令策略 | 私钥是否加口令 | 待确认 | 不加口令（CI 无人值守），靠 Secret 与 environment 保护 |
| 是否启用 GitHub Pages 自定义域名 | 影响 feed URL 稳定性 | 待确认 | 默认用 `github.io` 域名 |
| 分支保护强度 | 是否允许 bot 直接提交 `versions/*.env` | 待确认 | 禁止强推与删除，允许 bot 直接提交（否则需改用 PR 自动合并） |
| iStoreOS 上架 PR | 人工提交到 `istore-repo` 与 `openwrt-app-meta` | 阶段 5，使用 `xyonium` 账号 | 先元数据 PR，再 ipk PR（目标 `pending`） |

用户名已确认（`gh auth status` 显示 xyonium）；`xyonium/netbird-pkgs` 仓库尚未创建，阶段 0 创建并启用 Pages。

## 22. 许可合规

| 组件 | 许可 | 再分发义务 | 本仓库落实方式 |
|---|---|---|---|
| `netbird` 客户端二进制 | **BSD-3-Clause**（仓库根 LICENSE；`management/`、`signal/`、`relay/`、`combined/` 为 AGPLv3，本仓库不构建这些目录） | 随二进制复现版权声明、许可全文与免责声明；不得暗示背书 | 包内 `/usr/share/licenses/netbird/LICENSE`（上游原文）；Release 说明给出上游 tag、commit 与 sha256 |
| `netbird` 内嵌第三方模块 | 以 MIT / Apache-2.0 / BSD 为主（v0.82.0 二进制嵌入 121 个模块） | 保留各模块许可与版权 | 构建时生成 `THIRD-PARTY-NOTICES.txt`（`scripts/collect-licenses.sh` 从模块缓存收集），随包安装到 `/usr/share/licenses/netbird/` |
| `luci-app-netbird` | Apache-2.0 | 保留 LICENSE 与 NOTICE；标注修改文件 | 包内 `/usr/share/doc/luci-app-netbird/{LICENSE,NOTICE}`；发布说明注明来源与本地改动 |
| 本仓库脚本与文档 | MIT | 保留版权与许可声明 | 根目录 `LICENSE` |

要点：

- 本仓库只构建 `./client`，不构建 AGPLv3 的四个目录，因此不触发 AGPL 的源码提供义务；若将来构建服务端组件，必须单独评估。
- 上游 release tarball 自带 `LICENSE`、`LICENSES/` 与 `README.md`，但**不含**第三方模块 NOTICE；因此由本仓库在构建阶段生成并随包分发。
- `luci-app-netbird` 的 NOTICE 引用了 Tailscale 代码（Apache-2.0 衍生），需一并保留；其 NOTICE 缺少 Tailscale BSD-3 免责声明原文，属上游已知缺口，本仓库在包内附带的 NOTICE 后追加该文本并在 `REVIEW.md` 记录。
- 所有许可文件随 ipk 安装；卸载时不删除用户配置（`/etc/netbird`），确保许可声明在安装期内始终可见。
