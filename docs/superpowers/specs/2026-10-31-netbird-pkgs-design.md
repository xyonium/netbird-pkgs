# NetBird 自建软件包仓库 — 设计文档

- 日期：2026-10-31
- 状态：待审阅
- 作者：与 AI 助手协作产出

## 1. 背景与目标

### 问题

OpenWrt 24.10 稳定源的 NetBird 停留在 `0.59.13`，而上游已到 `0.82.0`，落后约 23 个小版本。根因已查明：NetBird 0.82.0 的 `go.mod` 要求 Go 1.26，而 OpenWrt 24.10 SDK 自带 Go 1.23.12，官方维护者无法在不连带升级工具链的前提下跟进。

OPNsense 侧同理：`netbird` 二进制包在 25.7 源里是 `0.60.7`，26.1 源里是 `0.72.2`，而 FreeBSD ports 树已到 `0.81.5`。

### 目标

建立一个由使用者完全掌控的软件包仓库，满足：

1. 自动跟踪 NetBird 官方 release，构建适配 `aarch64_generic` 与 `x86_64` 的 OpenWrt ipk
2. 提供带 usign 签名的 opkg 软件源，设备上 `opkg update && opkg install netbird` 即可安装与升级
3. 构建逻辑完全可审查、可在本机复现
4. 修正上游打包中已确认的缺陷（详见 §6.2）
5. 提供 LuCI 图形界面（从源码自建、钉版本）
6. 为 OPNsense 侧保留独立扩展空间

### 非目标

- 不追求覆盖 OpenWrt 全架构矩阵（仅两架构）
- 不发布到 OpenWrt 官方源或 iStore 官方源（后者仅在将来可选提 PR）
- 不替代 NetBird 服务端（self-hosted 管理面不在本仓库范围）
- 本期不实现 OPNsense 构建（独立立项，见 §13）

## 2. 目标设备与运行环境

| 设备 | SoC | 架构字段 | 固件 |
|---|---|---|---|
| FriendlyElec NanoPi R4S | RK3399 (2×A72 + 4×A53) | `aarch64_generic` | iStoreOS 24.10.5，内核 6.6.119 |
| Lunzn FastRhino R68S | RK3568 (4×A55) | `aarch64_generic` | iStoreOS 24.10.4，内核 6.6.110 |

两台设备架构相同，共用同一份包。iStoreOS 基于 OpenWrt 24.10，包管理器为 `opkg`（ipk 格式），**不是** 25.x 之后的 `apk`。

## 3. 关键约束（实测确认，非推测）

| 事实 | 影响 |
|---|---|
| NetBird v0.82.0 `go.mod`: `go 1.26.0`，注释要求 toolchain ≥ `go1.26.2` | 构建必须使用 Go ≥ 1.26.2 |
| OpenWrt 24.10 的 `lang/golang` 为 1.23.12 | **无法**在 24.10 SDK 内编译 netbird |
| OpenWrt 快照源已改用 `.apk`（实测仅 `netbird-0.81.4-r1.apk`） | 快照源产物对 iStoreOS 24.10 不可用 |
| 官方源 `openwrt-24.10` 分支 netbird = 0.59.13；`master` = 0.81.4 | 官方源不可作为新版来源 |
| 上游 release 不提供 FreeBSD 产物（仅 linux/darwin/windows/wasm） | OPNsense 侧须自行编译 |
| `luci-app-netbird` 依赖 `netbird (>=0)` 且 `PKGARCH:=all` | 与本仓库互补，一个包适配两架构 |

## 4. 架构总览

```
┌─────────────────────────────────────────────────────────┐
│  GitHub Actions                                          │
│                                                          │
│  upstream-watch.yml (周更)                               │
│    └→ 查 netbirdio/netbird 最新 release                  │
│       └→ 更新 versions/netbird.env (版本 + sha256)       │
│          └→ 触发 build-release.yml                       │
│                                                          │
│  luci-watch.yml (周更)                                   │
│    └→ 查 luci-app-netbird 新 tag → 开 PR（不自动合并）    │
│                                                          │
│  build-release.yml                                       │
│    job build      : 交叉编译 + 组装 ipk（无签名权限）      │
│    job sign-publish: 索引 + usign 签名 + Release + Pages  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
        GitHub Pages: https://<user>.github.io/netbird-pkgs/
          ├── aarch64_generic/{Packages,Packages.gz,Packages.sig,*.ipk}
          ├── x86_64/{...}
          ├── istore/{a53 命名的 ipk}
          └── keys/netbird-pkgs.pub
                          │
                          ▼
        设备: /etc/opkg/customfeeds.conf + /etc/opkg/keys/<指纹>
```

## 5. 仓库结构

```
netbird-pkgs/
├── .github/workflows/
│   ├── upstream-watch.yml
│   ├── luci-watch.yml
│   └── build-release.yml
├── packaging/
│   ├── netbird/
│   │   ├── control.in
│   │   ├── netbird.init
│   │   └── conffiles
│   └── luci-app-netbird/
│       └── (来自上游源码，不改动)
├── scripts/
│   ├── resolve-upstream.sh
│   ├── build-netbird-ipk.sh
│   ├── build-luci-ipk.sh
│   ├── make-feed.sh
│   ├── sign-feed.sh
│   └── verify-ipk.sh
├── versions/
│   ├── netbird.env
│   └── luci-app-netbird.env
├── keys/netbird-pkgs.pub
├── docs/
│   ├── THREAT-MODEL.md
│   ├── REVIEW.md
│   ├── INSTALL.md
│   └── superpowers/specs/2026-10-31-netbird-pkgs-design.md
└── README.md
```

### `versions/netbird.env` — 唯一版本真相源

```
NETBIRD_VERSION=0.82.0
NETBIRD_SHA256=<codeload tarball 的 sha256>
NETBIRD_PKG_RELEASE=1
```

任何构建开始前必须校验实际下载的 tarball 哈希与此值一致，不一致立即失败。该文件每次版本变更由 bot 提交，形成可追溯的审计链；回滚即 revert 对应 commit。

## 6. 包设计：`netbird`

### 6.1 包内容

| 路径 | 说明 |
|---|---|
| `/usr/bin/netbird` | 静态链接二进制，约 15 MB |
| `/etc/init.d/netbird` | procd 开机脚本（修正版） |
| `/etc/netbird/config.json` | 运行时生成，conffile，权限 0600 |

`control` 关键字段：

```
Package: netbird
Version: <upstream>-r<pkg_release>
Depends: kmod-wireguard, ca-bundle
Section: net
Category: Network
Architecture: aarch64_generic | x86_64
```

`ca-bundle` 为新增依赖：上游 OpenWrt 包未声明，但客户端与 `api.netbird.io` 的 TLS 握手需要 CA 根证书。

### 6.2 对上游的三处修正

均记录于 `docs/REVIEW.md`：

1. **删除 `. /lib/netifd/netifd-proto.sh`**
   该文件是 netifd 协议处理器库，仅被 `/lib/netifd/proto/*` 使用。netbird 不实现 netifd 协议，脚本中唯一相关的 `procd_add_interface_trigger` 实际定义在 `/lib/functions/procd.sh`（由 `rc.common` 自动加载）。该引用完全冗余。

2. **状态目录 `/root/.config/netbird` → `/etc/netbird`**
   `/root` 属用户数据区；`/etc` 是 OpenWrt 系统配置惯例位置，能正确进入 conffiles 与 `sysupgrade.conf`，使凭据在固件升级后保留。此选择与 `luci-app-netbird` 的首选探测路径 `/etc/netbird/config.json` 一致。

3. **增加 `procd_set_param respawn 3600 5 5`**
   上游未设置，进程崩溃后不会自动拉起。

**不采用的改动**：上游社区包的 `service_triggers` 会在每次 wan 接口事件时重启 netbird。NetBird 客户端自带重连逻辑，wan 抖动时反复重启反而加剧断连。默认关闭，`docs/INSTALL.md` 保留启用方法。

### 6.3 init 脚本

```sh
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

# luci-app-netbird 会写入 /etc/netbird.env（如 NB_LOG_FILE=syslog）。
# 只透传白名单变量，避免本文件被注入任意环境。
ENV_WHITELIST="NB_LOG_FILE NB_LOG_LEVEL"

start_service() {
	local envargs=""

	if [ -f /etc/netbird.env ]; then
		. /etc/netbird.env
		for v in $ENV_WHITELIST; do
			eval "val=\$$v"
			[ -n "$val" ] && envargs="$envargs $v=$val"
		done
	fi

	procd_open_instance
	procd_set_param command /usr/bin/netbird
	procd_append_param command service run
	procd_set_param env NB_STATE_DIR=/etc/netbird
	procd_append_param env NB_DISABLE_SSH_CONFIG=1
	procd_append_param env NB_DNS_STATE_FILE=/var/lib/netbird/state.json
	[ -n "$envargs" ] && procd_append_param env $envargs
	procd_set_param pidfile /var/run/netbird.pid
	procd_set_param respawn 3600 5 5
	procd_close_instance
}
```

附加项说明：若 `/etc/netbird.env` 存在（`luci-app-netbird` 会创建并写入 `NB_LOG_FILE=syslog`），按白名单 `NB_LOG_FILE`、`NB_LOG_LEVEL` 透传。这填补了上游 init 不消费该文件的缺口，使 LuCI 的日志页能拿到 syslog 输出。`NB_STATE_DIR` 不在白名单内，保持由本包固定为 `/etc/netbird`。

### 6.4 构建方式

```
GOOS=linux GOARCH=arm64|amd64 CGO_ENABLED=0 \
  go build -trimpath -buildvcs=false \
  -ldflags "-s -w -X github.com/netbirdio/netbird/version.version=<ver>" \
  -o netbird ./client
```

CGO 关闭保证静态链接，规避 glibc/musl 不兼容风险。Go 工具链由 `actions/setup-go` 安装并锁定具体补丁版本。

ipk 组装不依赖 OpenWrt SDK：ipk 是包含 `control.tar.gz` 与 `data.tar.gz` 的 tar 归档，由 `scripts/build-netbird-ipk.sh` 用标准 `tar`/`gzip` 生成。

## 7. 包设计：`luci-app-netbird`

来源：[looong-cat/luci-app-netbird](https://github.com/looong-cat/luci-app-netbird)，Apache-2.0。

- 以 git tag 固定版本，从源码用 OpenWrt SDK（`openwrt/gh-action-sdk`，钉 commit）构建
- 该包为纯 lua/js/ucode，不涉及 Go，故不受 §3 的 Go 版本约束
- `PKGARCH:=all`，一个产物适配两架构
- 关闭其内置的"二进制版本管理"能力，将 `netbird_bin.binary.binary_source` 默认固定为 `opkg`，使二进制来源唯一化为本仓库的 feed

## 8. 签名与分发

### Feed 布局

```
https://<user>.github.io/netbird-pkgs/
├── aarch64_generic/{Packages, Packages.gz, Packages.sig, netbird_*.ipk}
├── x86_64/{...}
├── istore/netbird_*_aarch64_cortex-a53.ipk
└── keys/netbird-pkgs.pub
```

### 签名机制

使用 OpenWrt 标准的 `usign`（从 [openwrt/usign](https://github.com/openwrt/usign) 源码在 CI 内编译）。

- 私钥存放于 GitHub Actions Secret `USIGN_SECRET_KEY`（base64 编码）
- 公钥提交到 `keys/netbird-pkgs.pub`，并在 README 公示指纹
- 设备端公钥文件名必须是 `usign -F -p` 输出的密钥指纹

### 设备接入（一次性）

```sh
# 1. 导入公钥
wget -O /tmp/nb.pub https://<user>.github.io/netbird-pkgs/keys/netbird-pkgs.pub
usign -F -p /tmp/nb.pub            # 取得指纹
cp /tmp/nb.pub /etc/opkg/keys/<指纹>

# 2. 添加 feed
echo "src/gz netbird-pkgs https://<user>.github.io/netbird-pkgs/aarch64_generic" \
  >> /etc/opkg/customfeeds.conf

# 3. 安装
opkg update && opkg install netbird luci-app-netbird
```

以上步骤封装为 `scripts/install-feed.sh`，支持一条命令完成。

opkg 会强制校验 `Packages.sig`，签名不匹配则拒绝安装。这是本方案唯一的信任锚点。

## 9. 流水线设计

### `upstream-watch.yml`

- 触发：`schedule` 每周一 03:00 UTC；支持 `workflow_dispatch`
- 权限：`contents: write`（仅用于提交 `versions/netbird.env`）
- 流程：查 `api.github.com/repos/netbirdio/netbird/releases/latest` → 与 `versions/netbird.env` 比较 → 无变化则退出 → 下载 tarball、计算 sha256 → 更新 env → bot commit → 触发 `build-release.yml`
- **不持有签名私钥**

### `luci-watch.yml`

- 触发：同周更
- 流程：查上游新 tag → 与 `versions/luci-app-netbird.env` 比较 → 有新版则**创建 PR**（含构建验证结论），不自动合并
- 理由：该应用以 root 运行、单一维护者、关注度有限（详见 §10），保留唯一的人工闸门

### `build-release.yml`

**job `build`**（matrix：`aarch64_generic→arm64`、`x86_64→amd64`）

1. checkout
2. 下载源码 tarball，校验 sha256 与 `versions/netbird.env` 一致
3. `actions/setup-go`（钉 SHA）
4. `go build`（参数见 §6.4）
5. `scripts/build-netbird-ipk.sh` 组装 ipk
6. `scripts/verify-ipk.sh` 自检
7. 上传 artifact

**job `build-luci`**

1. checkout 上游 tag
2. OpenWrt SDK 构建 `luci-app-netbird`
3. 上传 artifact

**job `sign-publish`**（`needs: [build, build-luci]`）

1. 下载全部 artifact + 现有 Release 中的上一版 ipk
2. `scripts/make-feed.sh` 重建索引（保留最近 2 个版本用于回滚）
3. `scripts/sign-feed.sh` 签名
4. 创建 GitHub Release
5. 更新 `gh-pages` 分支
6. `actions/attest-build-provenance` 生成 SLSA provenance

## 10. 安全模型

### 信任边界

| 组件 | 权限 | 风险 |
|---|---|---|
| `netbird` 二进制 | root | WireGuard 私钥必然落盘 |
| `luci-app-netbird` | root（LuCI/ubus） | 可读任意文件，含 `config.json` |
| 本仓库 CI | 写 Release + 持签名私钥 | 上游投毒可致污染产物 |

**任何** LuCI 应用以 root 运行，理论上都能读取私钥。因此控制目标不是"阻止单点访问"，而是"限制可信集合 + 可检测 + 可撤销"。

### 对 `luci-app-netbird` 的静态审计结论（2026-10-31，commit 截止 `main`）

已核查的正面证据：

| 检查项 | 结果 |
|---|---|
| 代码混淆 | 无 `eval` / `base64 -d` / `String.fromCharCode` / `/dev/tcp` |
| 外发域名 | 仅 `api.github.com` 与 `github.com/netbirdio/*`（版本页查询/下载官方二进制） |
| `setup_key` 持久化 | 不落盘；仅存打码 hint（前 6 字符 + `*`）；传参经 `shell_quote`；stdout 回显前替换为 `***` |
| `config.json` 访问 | 只读，仅用于展示预填管理 URL |
| ACL 范围 | 仅 `uci: netbird, netbird_bin` + 自身 ubus 对象；**无 file 权限、无任意 shell** |
| 配置文件权限 | `chmod 0600`，纳入 `sysupgrade.conf` |
| 重连守护脚本 | 无网络请求，不读取配置文件 |

负面/风险项：

1. 上游 README 自述"几乎所有代码是 vibe coding 写的"，逐行人工审查保证较弱
2. 57 stars、单一维护者，缺乏多人监督冗余
3. 其发布流水线使用 `openwrt/gh-action-sdk@main`（浮动引用）
4. 内置二进制版本管理可从 GitHub 下载并替换 `/usr/bin/netbird`（额外攻击面）
5. 提供 `curl | sh` 一键安装脚本 —— **本项目禁用此路径**
6. 必然瞬时可见 `setup_key`（GUI 封装固有属性）

### 控制措施

1. 构建 job 与签名 job 分离，私钥不进构建环境
2. 全部 `uses:` 钉到完整 commit SHA
3. `permissions:` 全局默认 `contents: read`，仅 publish job 提权
4. 不使用 `pull_request_target`；不将 `${{ }}` 直接插入 `run:` 脚本
5. 源码 tarball sha256 强校验
6. `GOFLAGS=-mod=readonly`，启用 Go sumdb
7. 构建不执行上游测试套件（避免运行不受信代码）
8. `-trimpath -buildvcs=false`，固定 `SOURCE_DATE_EPOCH`，追求可复现
9. `luci-app-netbird` 版本变更必须人工合并 PR
10. `setup_key` 在 NetBird 后台设为一次性/限时，异常时可在后台撤销设备

### 残余风险（明确接受）

全自动发布意味着 CI 持有签名私钥。若上游仓库被投毒，产物会携带本仓库签名落到设备。补偿手段为 §11 的 provenance、审计链与一键回滚，而非事前阻断。此风险已由使用者知情选择。

## 11. 验证与回滚

### 验证

`scripts/verify-ipk.sh`（CI 与本地均可运行）检查：

- ipk 归档结构完整（`control.tar.gz` + `data.tar.gz`）
- `Architecture` 字段正确
- `Depends` 含 `kmod-wireguard`、`ca-bundle`
- init 脚本 `sh -n` 语法通过
- `/usr/bin/netbird` 为静态链接（`file` 判定）
- 二进制可执行位正确

设备端验收清单（见 `docs/INSTALL.md`）：

```
opkg list-installed | grep -E 'netbird|ucode'
netbird version
netbird status
logread -e netbird | tail
```

### 回滚

- feed 保留最近 2 个版本：`opkg install netbird=<旧版本>` 直接降级
- 版本级回滚：revert `versions/netbird.env` 的对应 commit
- 应急停用：`/etc/init.d/netbird stop && /etc/init.d/netbird disable`

## 12. iStore 兼容

iStore 官方源（[istoreos/istore-repo](https://github.com/istoreos/istore-repo)）为人工 PR 审核制，索引由官方服务器生成，老版客户端 `is-opkg` 中 `FEEDS_SERVER` 硬编码。因此**无法**将自建源直接注册为 iStore 源。

可行路径：

1. 额外产出 `aarch64_cortex-a53` 命名的同内容 ipk，置于 `istore/` 目录（不混入主 feed，避免 opkg 架构不匹配报错）
2. 通过 iStore 的"手动安装"入口上传该 ipk
3. 将来如愿意，可向上游 `istore-repo` 提 PR 进入商店列表

GUI 的实际来源是 `luci-app-netbird`（LuCI 原生接口），不依赖 iStore。

## 13. OPNsense 扩展（独立立项）

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

## 14. 分阶段实施

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| 1 | 仓库骨架 + 构建脚本，本机跑通 | 产出 ipk，`opkg install` 成功，`netbird version` 正确 |
| 2 | 索引 + 签名 + 设备接入 | 两台设备 `opkg update` 验签通过，可安装可升级 |
| 3 | 全自动流水线 | 新版自动落地并可在设备上升级 |
| 4 | LuCI 集成 | Services → NetBird 可访问，能用 setup key 连接 |
| 5 | OPNsense | 独立设计文档与实施 |

## 15. 待验证事项

以下在实施阶段 1 必须实测确认，若结论不符将调整设计：

1. `netbird` 客户端在 `CGO_ENABLED=0` 下能完整构建且运行正常
2. 静态二进制在 iStoreOS（musl + 6.6 内核）上可执行
3. `luci-app-netbird` 的依赖 `rpcd-mod-ucode`、`ucode`、`ucode-mod-fs`、`ucode-mod-uci`、`conntrack` 在 iStoreOS 24.10 上可获取
4. GitHub Pages 作为 feed 托管的可用性与中国网络环境下的可达性
5. `usign` 在 CI 中可从源码构建，签名产物能被设备上的 opkg 正确校验

## 16. 附录：事实核查记录

| 项目 | 数值 | 来源 |
|---|---|---|
| NetBird 最新版 | v0.82.0（2026-10-29） | GitHub API `releases/latest` |
| NetBird go 要求 | go 1.26.0，toolchain ≥ 1.26.2 | v0.82.0 `go.mod` |
| OpenWrt 24.10 netbird | 0.59.13 | `openwrt/packages` `openwrt-24.10` 分支 Makefile |
| OpenWrt master netbird | 0.81.4 | `openwrt/packages` master Makefile |
| OpenWrt 24.10 golang | 1.23.12 | `lang/golang/golang/Makefile` |
| 快照源包格式 | `.apk` | `downloads.openwrt.org` 实测 |
| `luci-app-netbird` | 0.1.0-r26，`PKGARCH:=all` | 上游 Makefile |
| FreeBSD port netbird | 0.81.5 | `cgit.freebsd.org` |
| OPNsense 25.7 源 | `os-netbird-1.1`、`netbird-0.60.7` | `pkg.opnsense.org` 目录列表 |
| OPNsense 26.1 源 | `os-netbird-1.3_3`、`netbird-0.72.2` | 同上 |

## 17. 需要使用者提供的信息

本文档中的 `<user>` 指 GitHub 用户名占位符。实施阶段 1 开始前需确认以下输入，确认后一次替换到所有文件中：

| 输入项 | 用途 | 当前状态 |
|---|---|---|
| GitHub 用户名 / 组织 | Pages 域名 `https://<user>.github.io/netbird-pkgs/`、仓库地址 | **待提供** |
| 仓库可见性 | 公开（Pages 需公开仓库或付费计划） | 建议公开 |
| usign 密钥口令策略 | 私钥是否加口令 | 建议不加口令（CI 无人值守），靠 Secret 保护 |
| 是否启用 GitHub Pages 自定义域名 | 影响 feed URL 稳定性 | 默认用 `github.io` 域名 |

若 GitHub 用户名为空或与预期不符，所有替代 `<user>` 的位置将无法工作，故此项为实施前置条件。

