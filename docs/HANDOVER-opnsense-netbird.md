# 交接：把 netbird 0.82.0 推到 OPNsense

> 写于 2026-11-02。给新 session 用。**这是一个独立任务，与 netbird-pkgs 仓库的构建流水线无关**，
> 只共用"我们关心的 netbird 版本号"这一个事实。

## 结论先说

**不需要新插件，也不需要第三方源。OPNsense 已经有官方 netbird 插件。**

要做的只有一件事：**把 FreeBSD ports 里的 `security/netbird` 从 0.81.5 升到 0.82.0**，
然后 OPNsense 的 `os-netbird` 插件会自动用上新版二进制。

## 现状（已核实）

| 组件 | 位置 | 当前版本 | 说明 |
|---|---|---|---|
| OPNsense 插件（GUI） | [`opnsense/plugins` → `security/netbird`](https://github.com/opnsense/plugins/tree/master/security/netbird) | `PLUGIN_VERSION=1.3` `PLUGIN_REVISION=3` | 纯 GUI，`PLUGIN_DEPENDS=netbird`，维护者 `dev@netbird.io` |
| netbird 二进制 | [`freebsd/freebsd-ports` → `security/netbird`](https://github.com/freebsd/freebsd-ports/tree/main/security/netbird) | **`DISTVERSION=0.81.5`** | 由 FreeBSD ports 用 `go:modules` 编译 |
| 我们的仓库 | `versions/netbird.env` | **`0.82.0`** | 上游 0.82.0 发布于 2026-10-29 |

**所以差距只有一处：FreeBSD ports 停在 0.81.5，落后一个版本。**

时间线（`security/netbird` 的提交史）：
- 2026-10-20 `various: Bump Go ports for Go 1.26.10 / 1.27.3`
- 2026-10-24 `update 0.81.0 => 0.81.4`
- 2026-10-26 `Update 0.81.4 => 0.81.5`
- 2026-10-29 上游发布 **0.82.0** ← 此后无人跟进
- 我查过 `freebsd/freebsd-ports` 的 open PR：**没有** netbird 相关的升级 PR

即：这是一个**无人认领、范围很小**的 PR 机会。

## 要做的事（FreeBSD ports PR）

改 `security/netbird/` 下两个文件：

**1. `Makefile`** —— 只改版本号：
```
DISTVERSION=	0.81.5     →   DISTVERSION=	0.82.0
```

**2. `distinfo`** —— 需要重新生成（`go` 模块的 `.mod` 和 `.zip` 校验和）：
```sh
cd /path/to/freebsd-ports/security/netbird
make makesum        # 或在 ports 树根用 poudriere/testport
```
`distinfo` 现在长这样（两行 SHA256 + 两行 SIZE）：
```
SHA256 (go/security_netbird/netbird-v0.81.5/v0.81.5.mod) = …
SIZE   (go/security_netbird/netbird-v0.81.5/v0.81.5.mod) = 18247
SHA256 (go/security_netbird/netbird-v0.81.5/v0.81.5.zip) = …
SIZE   (go/security_netbird/netbird-v0.81.5/v0.81.5.zip) = 11668809
```

注意该 port 用 `GO_MODULE=github.com/netbirdio/netbird`，`distinfo` 里的路径会随版本号变化
（`netbird-v0.82.0/`），**必须用 `make makesum` 重新生成，不能手改版本号**。

## 提交前必须验证

FreeBSD ports 有硬性验收，别只改版本号就提：

```sh
# 1) 至少能干净地抓取 + 校验 + 构建
make -C security/netbird makesum
make -C security/netbird distclean
make -C security/netbird stage

# 2) 官方推荐的完整检查（会跑 poudriere，比较慢）
#    https://docs.freebsd.org/en/books/porters-handbook/
poudriere testport -j <jail> security/netbird
```

**重点看 0.82.0 有没有引入新的 Go 依赖或 CGO 需求**。该 port 用
`GO_TARGET=./client:${netbird}` 和 `-tags freebsd`，如果上游改了 build tag 或
新增了 FreeBSD 不支持的依赖，这里会暴露。

## 一个可以顺带确认的点

`os-netbird` 的 `PLUGIN_VERSION=1.3` / `PLUGIN_REVISION=3`。如果 netbird 0.82.0 改了
CLI 输出格式或配置文件结构，插件可能需要跟一个小版本。**升级 ports 后请在 OPNsense 上
实际验证插件还能正常读写状态**（`netbird status`、GUI 里 VPN → NetBird 页面）。
不需要改就先不动插件 —— 别为了凑版本号动它。

## 如果你其实想要"第三方源"方案

不是不行，但**没必要**：

- OPNsense 的插件安装走 pkg（FreeBSD），源是官方 `pkg.opnsense.org`；加第三方源需要
  用户手改 `/usr/local/etc/pkg/repos/`，且插件和二进制版本要自己保证兼容。
- 而我们能提供的 Linux 静态二进制**在 FreeBSD 上根本跑不了**（FreeBSD 需要 FreeBSD
  ABI 的可执行文件，Linux 二进制要靠 linuxulator，不适合做 VPN 守护进程）。
- 结论：**走上游 ports 升级，让官方渠道分发**，比自己维护一个 FreeBSD 源省事得多，
  而且用户升级路径是统一的 `pkg upgrade`。

## 别做的事

- 不要给 OPNsense 提"新增 netbird 插件"的 PR —— 已经有了，会直接被拒。
- 不要在 `opnsense/plugins` 里改 `PLUGIN_DEPENDS`，那个值是对的。
- 不要用我们仓库的 Go 版本号（1.26.2）去改 ports —— ports 有自己的 `USES=go:modules`
  和 Go 版本策略。

## 参考资料

- [OPNsense Netbird 插件文档](https://docs.opnsense.org/manual/how-tos/netbird.html)
- [NetBird 官方 OPNsense 安装说明](https://docs.netbird.io/get-started/install/opnsense)
- [FreeBSD Porter's Handbook](https://docs.freebsd.org/en/books/porters-handbook/)
- FreeBSD ports 提交规范：标题格式 `security/netbird: Update 0.81.5 => 0.82.0`

## 优先级说明

**这件事不紧急。** 0.81.5 → 0.82.0 是一个小版本；我们自己的 OpenWrt feed 已经是 0.82.0，
不受影响。等你有空再做，或者干脆等 FreeBSD 的维护者（`dev@netbird.io`，就是 NetBird 官方）
自己跟。真正值得先做的是 iStore 上架那条线。
