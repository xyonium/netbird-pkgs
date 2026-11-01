# NetBird 自建软件包仓库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建并发布带 usign 签名的 OpenWrt opkg 源，提供最新 NetBird 客户端与自建 LuCI 管理界面，并产出可直接 PR 到 iStoreOS 的上架产物。

**Architecture:** 用 Go 1.26.2 交叉编译 `./client`，以标准 `tar`/`gzip` 手工组装 ipk（24.10 SDK 的 Go 1.23 无法编译上游）；CI 分离构建与签名，`usign` 签 `Packages`，GitHub Pages 原子部署，GitHub Releases 保存不可变归档；另出 `aarch64_cortex-a53` 变体与 `app-meta` 元数据供 iStoreOS PR。

**Tech Stack:** POSIX shell、bats-core、Go 1.26.2、GNU tar/gzip、usign、GitHub Actions、OpenWrt opkg/ipk、LuCI/ucode。

**Spec:** `docs/superpowers/specs/2026-10-31-netbird-pkgs-design.md`（v2.4）

## Global Constraints

- 上游固定：`NETBIRD_VERSION` / `NETBIRD_COMMIT` / `NETBIRD_SHA256` / `NETBIRD_PKG_RELEASE` 仅在 `versions/netbird.env`；构建前必须校验 tarball sha256。
- 构建：`CGO_ENABLED=0 GOOS=linux GOARCH=arm64|amd64 GOTOOLCHAIN=local GOFLAGS=-mod=readonly`；`-trimpath -buildvcs=false -buildmode=exe -tags load_wgnt_from_rsrc`；ldflags 注入 `version.version`、`main.commit`、`main.date=$SOURCE_DATE_EPOCH`、`main.builtBy=netbird-pkgs`；入口 `./client`。
- 架构：feed 用 `aarch64_generic` / `x86_64`；iStore 变体用 `aarch64_cortex-a53`；LuCI 为 `all`。同一版本不得覆盖已有文件名。
- ipk：外层 gzip tar，顺序 `./debian-binary`、`./data.tar.gz`、`./control.tar.gz`；`control.tar.gz` 只含 `./control`（**不生成 conffiles**）；确定性参数 `tar --sort=name --mtime=@$SOURCE_DATE_EPOCH --owner=0 --group=0 --numeric-owner` + `gzip -9n`。
- 包内路径：`/usr/bin/netbird`(0755)、`/etc/init.d/netbird`(0755)、`/usr/share/licenses/netbird/{LICENSE,THIRD-PARTY-NOTICES.txt}`(0644)；运行态 `/etc/netbird/config.json`(0600)。
- init 环境：`NB_CONFIG=/etc/netbird/config.json`、`NB_STATE_DIR=/etc/netbird`、`NB_DISABLE_SSH_CONFIG=1`、`NB_DNS_STATE_FILE=/var/lib/netbird/state.json`；`/etc/netbird.env` **只解析不 source**，白名单仅 `NB_LOG_FILE NB_LOG_LEVEL SSL_CERT_FILE`。
- 签名：只签 `Packages`；`usign -S -m Packages -s <key>` 默认产出 `Packages.sig`；指纹为 16 位小写十六进制；公钥名必须等于指纹。
- 发布：`v<version>-r<pkg_release>`；feed 每架构保留最近 2 个上游版本（同版本保留最高 pkg release）；Release 资产不可变。
- 仓库：`xyonium/netbird-pkgs`，默认分支 `main`，公开；Pages `https://xyonium.github.io/netbird-pkgs/`；签名 Secret `USIGN_SECRET_KEY_B64` 仅 `release` environment 可见；部署 job 使用 `github-pages` environment。
- 脚本约定：`#!/bin/sh` + `set -eu`；`LC_ALL=C`、`TZ=UTC`；退出码 0/1/2；产物只写 `dist/` 或 `--outdir`；网络访问仅 `resolve-upstream.sh` 与 `install-feed.sh`。
- 构建不执行上游脚本/测试；工作流不把 `${{ }}` 插入 `run:`；所有 `uses:` 钉完整 commit SHA。

## Review Focus

- `/etc/netbird.env` 中出现引号、空格、`$(...)`、超长行或非白名单键时，init 必须不执行、不误传、不崩溃。
- 同一输入两次构建的 ipk 必须字节一致；任何 mtime/排序/gzip 头差异都要在测试中暴露。
- 包 `Architecture` 字段与 feed/目录不一致时（aarch64_generic vs aarch64_cortex-a53）必须被 verify 或 iStore 布局测试拦截。
- feed 生成过程中出现「索引引用的 ipk 不存在」「旧版本被删但索引仍引用」「签名与索引不同步」时，发布脚本必须失败而不是产出半成品。
- LuCI 上游改动 `binary_source` 默认值或文件路径时，补丁必须显式失败（而不是静默回到 `release`）。

---

## File Structure

```
Makefile                       # lint/test/build/feed/istore/e2e 入口
LICENSE                        # MIT（本仓库脚本与文档）
.gitignore                     # dist/、.sdk/、*.ipk、*.log
.github/
  workflows/upstream-watch.yml
  workflows/build-release.yml
  dependabot.yml
packaging/netbird/control.in
packaging/netbird/netbird.init
packaging/luci-app-netbird/patches/0001-default-binary-source-opkg.patch
packaging/istore/app-meta-netbird/{Makefile,logo.png}
scripts/resolve-upstream.sh
scripts/build-netbird.sh
scripts/build-netbird-ipk.sh
scripts/collect-licenses.sh
scripts/verify-ipk.sh
scripts/make-feed.sh
scripts/sign-feed.sh
scripts/build-luci-ipk.sh
scripts/make-istore.sh
scripts/install-feed.sh
tests/helper.bash
tests/netbird-init.bats
tests/build-netbird.bats
tests/build-netbird-ipk.bats
tests/verify-ipk.bats
tests/resolve-upstream.bats
tests/collect-licenses.bats
tests/make-feed.bats
tests/sign-feed.bats
tests/install-feed.bats
tests/build-luci-ipk.bats
tests/make-istore.bats
tests/workflows.bats
tests/fixtures/static.go
versions/netbird.env
versions/luci-app-netbird.env
keys/netbird-pkgs.pub
docs/{INSTALL,REVIEW,THREAT-MODEL,ISTORE-PR}.md
README.md
```

职责：`packaging/` 只放包元数据与补丁；`scripts/` 每个脚本一个职责、由同名 bats 覆盖；`tests/helper.bash` 提供建 fixture ipk / 假 root 的工具；工作流只调用脚本，不内联业务逻辑。

---

### Task 0: 仓库与发布基础设施（一次性，人工）

**Files:**
- Create: `keys/netbird-pkgs.pub`（提交到仓库）

**Interfaces:**
- Produces: 远程仓库 `xyonium/netbird-pkgs`、Pages（Actions 源）、`release` environment 与 `USIGN_SECRET_KEY_B64`、`github-pages` environment、签名公钥与指纹。

- [ ] **Step 1: 创建仓库并推送**

```bash
gh repo create xyonium/netbird-pkgs --public --source=. --remote=origin --push
```

Expected: `gh repo view xyonium/netbird-pkgs` 显示仓库，默认分支 `main`。

- [ ] **Step 2: 启用 Pages（GitHub Actions 作为源）**

```bash
gh api -X POST repos/xyonium/netbird-pkgs/pages -f build_type=workflow
gh api repos/xyonium/netbird-pkgs/pages --jq '.build_type, .html_url'
```

Expected: `workflow`；`https://xyonium.github.io/netbird-pkgs/`（首次部署前 404 属正常）。

- [ ] **Step 3: 生成 usign 密钥并保存 Secret**

```bash
usign -G -s /tmp/netbird-pkgs.sec -p keys/netbird-pkgs.pub -c "netbird-pkgs feed signing key"
gh api -X PUT repos/xyonium/netbird-pkgs/environments/release >/dev/null
gh secret set USIGN_SECRET_KEY_B64 --env release --body "$(base64 -w0 /tmp/netbird-pkgs.sec)"
usign -F -p keys/netbird-pkgs.pub
```

Expected: 指纹为 16 位十六进制；`gh secret list --env release` 含 `USIGN_SECRET_KEY_B64`；私钥不进入 git（`/tmp` 自行销毁）。

- [ ] **Step 4: 创建 `github-pages` environment 与分支保护**

用仓库 Settings → Environments 创建 `github-pages`（无需密钥）；在 Rules 中禁止 `main` 强推与删除，允许 GitHub Actions bot 直接提交 `versions/*.env`。API 失败时用 UI 完成并在 PR 描述记录。

- [ ] **Step 5: 验证并提交公钥**

```bash
gh api repos/xyonium/netbird-pkgs/environments --jq '.environments[].name'
git add keys/netbird-pkgs.pub && git commit -m "chore(keys): publish feed signing public key" && git push
```

Expected: environments 含 `release`、`github-pages`；公钥已推送。

---

### Task 1: 仓库骨架 + init 脚本（含环境变量白名单解析）

**Files:**
- Create: `Makefile`、`.gitignore`、`LICENSE`、`packaging/netbird/netbird.init`
- Test: `tests/netbird-init.bats`、`tests/helper.bash`

**Interfaces:**
- Consumes: 无。
- Produces: `packaging/netbird/netbird.init`（供 Task 2 打包）；`make test`（运行 `tests/*.bats`）；`tests/helper.bash` 中的 `make_fixture_binary <path>`。

- [ ] **Step 1: 写失败测试 `tests/netbird-init.bats`**

```bash
setup() {
  INIT="$BATS_TEST_DIRNAME/../packaging/netbird/netbird.init"
  TMP="$(mktemp -d)"
}
teardown() { rm -rf "$TMP"; }

@test "whitelist only: NB_LOG_FILE/NB_LOG_LEVEL/SSL_CERT_FILE" {
  source "$INIT"
  procd_append_param() { echo "$*" >> "$TMP/params"; }
  printf '%s\n' 'NB_LOG_FILE=syslog' 'NB_LOG_LEVEL="debug"' \
    'SSL_CERT_FILE=/etc/ssl/certs/ca.pem' 'NB_STATE_DIR=/evil' > "$TMP/env"
  append_env_from_file "$TMP/env"
  run cat "$TMP/params"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "env NB_LOG_FILE=syslog" ]
  [ "${lines[1]}" = "env NB_LOG_LEVEL=debug" ]
  [ "${lines[2]}" = "env SSL_CERT_FILE=/etc/ssl/certs/ca.pem" ]
  [ "${#lines[@]}" -eq 3 ]
}
@test "ignores comments, garbage and missing file" {
  source "$INIT"
  procd_append_param() { echo "$*" >> "$TMP/params"; }
  printf '%s\n' '# comment' 'garbage' '' 'NB_LOG_FILE=syslog' > "$TMP/env"
  append_env_from_file "$TMP/env"
  append_env_from_file "$TMP/missing"
  [ "$(wc -l < "$TMP/params")" -eq 1 ]
}
@test "never sources /etc/netbird.env" {
  run grep -E '(^|[[:space:]])(\.|source)[[:space:]]+/etc/netbird\.env' "$INIT"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: 运行确认失败**

Run: `bats tests/netbird-init.bats`
Expected: FAIL（`packaging/netbird/netbird.init` 不存在）

- [ ] **Step 3: 实现 `packaging/netbird/netbird.init`**

按 spec §7.3 原样落地：`START=99`、`STOP=10`、`USE_PROCD=1`；`start_service` 先 `mkdir -p /var/lib/netbird`、`umask 077`；`procd_set_param command /usr/bin/netbird service run`；四个固定 env；调用 `append_env_from_file /etc/netbird.env`；`pidfile /var/run/netbird.pid`；`respawn 3600 5 5`。解析函数用 `IFS= read -r line`、跳过空行/`#`、`key=${line%%=*}`、`val=${line#*=}`、`case` 白名单、去掉成对双引号后 `procd_append_param env "$key=$val"`。

同时创建 `Makefile`：

```make
SHELL := /bin/sh
.PHONY: test lint
test:
	bats tests
lint:
	sh -n packaging/netbird/netbird.init
	shellcheck -s sh $(shell git ls-files 'scripts/*.sh')
```

`.gitignore`：`dist/`、`.sdk/`、`*.ipk`、`*.log`。`LICENSE`：MIT。

- [ ] **Step 4: 运行确认通过**

Run: `make test`
Expected: PASS（3 个测试）

- [ ] **Step 5: Commit**

```bash
git add Makefile .gitignore LICENSE packaging/netbird/netbird.init tests/
git commit -m "feat(init): add netbird procd init with safe env whitelist"
```

---

### Task 2: ipk 组装脚本

**Files:**
- Create: `packaging/netbird/control.in`、`scripts/build-netbird-ipk.sh`
- Test: `tests/build-netbird-ipk.bats`

**Interfaces:**
- Consumes: `packaging/netbird/{control.in,netbird.init}`、输入二进制。
- Produces: `build-netbird-ipk.sh --arch <aarch64_generic|x86_64> --version <v> --binary <path> --outdir <dir> [--pkg-release N] [--source-date-epoch N]`；输出 `<outdir>/netbird_<v>-r<N>_<arch>.ipk` 与 `.sha256`；退出码 0/1/2。

- [ ] **Step 1: 写失败测试**

断言：缺失二进制 → 1；非法架构 → 2；产物外层 `tar tzf` 依次为 `./debian-binary`、`./data.tar.gz`、`./control.tar.gz`；`control.tar.gz` 仅含 `./control` 且无 `conffiles`；control 含 `Package: netbird`、`Version: 0.82.0-r1`、`Architecture: aarch64_generic`、`Depends: kmod-wireguard, ca-bundle`、`License: BSD-3-Clause`、`SourceDateEpoch: 1700000000`；data 中 `/usr/bin/netbird` 权限 0755、init 0755、许可 0644；同一 `SOURCE_DATE_EPOCH` 两次构建 sha256 相同。

- [ ] **Step 2: 运行确认失败**

Run: `bats tests/build-netbird-ipk.bats`
Expected: FAIL（脚本不存在）

- [ ] **Step 3: 实现**

`control.in` 用 `@VERSION@ @ARCH@ @PKG_RELEASE@ @INSTALLED_SIZE@ @SOURCE_DATE_EPOCH@` 占位；脚本校验参数与二进制可执行，构造 `dist/pkg/{control,data}`，计算 `Installed-Size`（KB），按 Global Constraints 的 tar/gzip 参数生成两层归档，输出 sha256。所有临时目录 `mktemp -d` + `trap`。

- [ ] **Step 4: 运行确认通过**

Run: `bats tests/build-netbird-ipk.bats`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add packaging/netbird/control.in scripts/build-netbird-ipk.sh tests/build-netbird-ipk.bats
git commit -m "feat(pkg): assemble deterministic netbird ipk without SDK"
```

---

### Task 2b: Go 构建封装

**Files:**
- Create: `scripts/build-netbird.sh`
- Test: `tests/build-netbird.bats`

**Interfaces:**
- Consumes: 源码树、`GO`（默认 `go`）、`SOURCE_DATE_EPOCH`。
- Produces: `build-netbird.sh --arch <aarch64_generic|x86_64> --version <v> --commit <sha> --source <dir> --outdir <dir> [--dry-run]`；输出 `<outdir>/netbird`；退出码 0/1/2。

- [ ] **Step 1: 写失败测试**

断言 `--dry-run` 输出含：`CGO_ENABLED=0`、`GOOS=linux`、`GOARCH=arm64`、`GOTOOLCHAIN=local`、`GOFLAGS=-mod=readonly`、`-trimpath`、`-buildvcs=false`、`-buildmode=exe`、`-tags load_wgnt_from_rsrc`、四个 `-X`（version/commit/date/builtBy）、入口 `./client`；`GO=/tmp/fake-go` 输出 `go1.25.0` 时退出 1；缺 `SOURCE_DATE_EPOCH` 退出 2。

- [ ] **Step 2: 运行确认失败** → `bats tests/build-netbird.bats` FAIL

- [ ] **Step 3: 实现**

校验 `"$GO" version` 以 `go1.26.2` 开头；`SOURCE_DATE_EPOCH` 必须为正整数；拼出命令；`--dry-run` 打印到 stdout 后退出；否则执行并运行 `"$outdir/netbird" version`，输出必须等于 `--version`。

- [ ] **Step 4: 运行确认通过** → PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/build-netbird.sh tests/build-netbird.bats
git commit -m "feat(build): wrap pinned Go build with flags and version self-check"
```

---

### Task 3: ipk 校验脚本

**Files:**
- Create: `scripts/verify-ipk.sh`
- Test: `tests/verify-ipk.bats`、`tests/fixtures/static.go`

**Interfaces:**
- Consumes: Task 2 产物。
- Produces: `verify-ipk.sh --ipk <path> --arch <arch> [--version <v>] [--skip-binary-check]`；逐项输出，任一失败退出 1。

- [ ] **Step 1: 写失败测试**

用例：架构不符、缺 `ca-bundle`、init `sh -n` 失败、二进制非静态（用 `/bin/true` 复制进包）、二进制无执行位、合法包 + `--version 0.82.0` 通过；`--skip-binary-check` 时跳过静态与版本检查。

- [ ] **Step 2: 运行确认失败**

Run: `bats tests/verify-ipk.bats`
Expected: FAIL

- [ ] **Step 3: 实现**

检查外层结构/顺序、control 必需字段、文件白名单（允许 `/usr/share/licenses/netbird/*`）、`file` 含 `statically linked` 且 `readelf -l` 无 `INTERP`、`sh -n` init、可选 `netbird version` 输出等于 `--version`。

- [ ] **Step 4: 运行确认通过**

Run: `bats tests/verify-ipk.bats`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-ipk.sh tests/verify-ipk.bats tests/fixtures/static.go
git commit -m "feat(verify): validate ipk structure, arch, deps and static binary"
```

---

### Task 4: 上游版本解析

**Files:**
- Create: `scripts/resolve-upstream.sh`
- Test: `tests/resolve-upstream.bats`、`tests/fixtures/release.json`

**Interfaces:**
- Consumes: `versions/netbird.env`（可选）、GitHub API JSON（测试用 fixture，生产用 `GH_TOKEN` 请求）。
- Produces: stdout `VERSION=… COMMIT=… SHA256=… CHANGED=0|1`；退出码 0/1/2。

- [ ] **Step 1: 写失败测试**

fixture 含 `tag_name`、`target_commitish`、`tarball_url`；断言新版本输出 `CHANGED=1`、版本去掉 `v`、commit 为短 SHA；env 已有同版本 → `CHANGED=0`；env 中 `NETBIRD_PKG_RELEASE=2` 保持不变；tarball 校验和计算由 `--tarball <file>` 测试模式注入（避免网络）。

- [ ] **Step 2: 运行确认失败** → `bats tests/resolve-upstream.bats` FAIL

- [ ] **Step 3: 实现**

`--repo netbirdio/netbird`、`--env-file`、`--fixture <json>`、`--tarball <file>`；版本比较用 `sort -V`；`sha256sum` 计算；不写文件（由工作流负责写入）。

- [ ] **Step 4: 运行确认通过** → PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/resolve-upstream.sh tests/resolve-upstream.bats tests/fixtures/release.json
git commit -m "feat(upstream): resolve latest netbird release and checksum"
```

---

### Task 5: 第三方许可收集

**Files:**
- Create: `scripts/collect-licenses.sh`
- Test: `tests/collect-licenses.bats`

**Interfaces:**
- Consumes: Go module cache 目录（`GOMODCACHE`）。
- Produces: `collect-licenses.sh --mod-cache <dir> --out <file>`；按模块名排序输出；缺失许可的模块写入 `MISSING: <module>` 段但退出 0（人工复核）。

- [ ] **Step 1: 写失败测试**：假模块目录含 `LICENSE`/`LICENSE.md`/`COPYING`；断言输出包含模块路径与许可原文、排序、缺失项段落；无模块目录 → 退出 1。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：遍历 `cache/download/**/@v/*.zip` 不可行（不解压），改为遍历 `--mod-cache` 下已解压模块目录（`<module>@<version>`），收集顶层许可文件；`set -eu`。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add scripts/collect-licenses.sh tests/collect-licenses.bats
git commit -m "feat(license): collect third-party notices from module cache"
```

---

### Task 6: feed 索引生成

**Files:**
- Create: `scripts/make-feed.sh`
- Test: `tests/make-feed.bats`

**Interfaces:**
- Consumes: 同目录下的 ipk（Task 2/9 产物）。
- Produces: `make-feed.sh --dir <feed> --arch <arch> [--retain N=2] [--ipk <path>]…`；写 `<dir>/Packages`、`<dir>/Packages.gz`；退出码 0/1/2。

- [ ] **Step 1: 写失败测试**

断言：索引字段 `Package/Version/Depends/Architecture/Installed-Size/Filename/Size/SHA256sum/Section/Category/License/Description`；按 `Package`+`Version` 排序；`Filename` 为相对路径；`Packages.gz` 可解压且 `gzip -n`（无时间戳）；保留最近 2 个上游版本；引用缺失 ipk → 退出 1；空目录生成空索引退出 0。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：从每个 ipk 的 `control.tar.gz` 提取 control；用 `awk` 排序；`gzip -9n`。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add scripts/make-feed.sh tests/make-feed.bats
git commit -m "feat(feed): build deterministic opkg index with retention"
```

---

### Task 7: feed 签名与验签

**Files:**
- Create: `scripts/sign-feed.sh`
- Test: `tests/sign-feed.bats`

**Interfaces:**
- Consumes: Task 6 的 `Packages`、usign 私钥/公钥。
- Produces: `sign-feed.sh --dir <feed> --key <secret>` 或 `--verify <pub>`；生成/校验 `Packages.sig`；退出码 0/1/2。

- [ ] **Step 1: 写失败测试**（无 usign 时 `skip`）

断言：签名后 `usign -V -m Packages -p pub` 通过；篡改 `Packages` 后失败；缺私钥退出 1；指纹为 16 位十六进制。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：`usign -S -m "$dir/Packages" -s "$key"`；`--verify` 用 `usign -V -m … -p …`；签名后立即自验签。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add scripts/sign-feed.sh tests/sign-feed.bats
git commit -m "feat(sign): sign and self-verify opkg Packages with usign"
```

---

### Task 8: 设备接入脚本

**Files:**
- Create: `scripts/install-feed.sh`
- Test: `tests/install-feed.bats`

**Interfaces:**
- Consumes: feed URL、公钥 URL。
- Produces: `install-feed.sh --feed-url <url> --key-url <url> [--arch auto] [--root <dir>] [--yes]`；幂等写 `<root>/etc/opkg/customfeeds.conf`；公钥入 `<root>/etc/opkg/keys/<fp>`；退出码 0/1/2。

- [ ] **Step 1: 写失败测试**

假 root + 假 `opkg-key`/`usign` 脚本；断言 feed 行只写一次、指纹文件权限 0644、`--arch auto` 在 fixture 架构表中选最高优先级（`aarch64_cortex-a53 10` 优先于 `aarch64_generic 5`）、`--yes` 跳过确认、无 `--yes` 时提示且不写。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：`--root` 前缀所有路径；下载用 `wget`/`uclient-fetch`/`curl` 之一；优先 `opkg-key add`，回退 `usign -F` + `cp`；写入前打印 diff 式变更。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add scripts/install-feed.sh tests/install-feed.bats
git commit -m "feat(install): idempotent device feed and key setup"
```

---

### Task 9: LuCI 包构建与补丁

**Files:**
- Create: `scripts/build-luci-ipk.sh`、`packaging/luci-app-netbird/patches/0001-default-binary-source-opkg.patch`
- Test: `tests/build-luci-ipk.bats`、`tests/fixtures/netbird_bin`

**Interfaces:**
- Consumes: 上游源码、OpenWrt SDK 目录、Task 3 校验脚本。
- Produces: `build-luci-ipk.sh --source <dir> --sdk <dir> --version <v> --release <r> --outdir <dir>`；输出 `luci-app-netbird_<v>-r<r>_all.ipk`、可选 i18n 包与 `.sha256`。

- [ ] **Step 1: 写失败测试**

断言：补丁在 fixture `netbird_bin` 上可 apply，结果 `binary_source` 默认值为 `opkg`；补丁对已修改文件再次 apply 失败（不静默）；缺参数退出 2；真实 SDK 构建标记为 integration（`bats` 中 `skip` 除非 `SDK_DIR` 存在）。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：`patch -p1 < …`；调用 `make -C "$SDK" package/luci-app-netbird/compile`；复制上游 `LICENSE`/`NOTICE` 到 `data/usr/share/doc/luci-app-netbird/` 并追加 Tailscale BSD-3 文本；产物交 `verify-ipk.sh --arch all`。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add scripts/build-luci-ipk.sh packaging/luci-app-netbird tests/build-luci-ipk.bats tests/fixtures/netbird_bin
git commit -m "feat(luci): build pinned luci-app-netbird with opkg binary source default"
```

---

### Task 10: iStore 上架 bundle

**Files:**
- Create: `scripts/make-istore.sh`、`packaging/istore/app-meta-netbird/{Makefile,logo.png}`、`docs/ISTORE-PR.md`
- Test: `tests/make-istore.bats`

**Interfaces:**
- Consumes: Task 2（aarch64_generic + x86_64）、Task 9（all + 可选 i18n）。
- Produces: `make-istore.sh --ipk-dir <dir> --outdir <dir> [--version <v>] [--pkg-release <n>]`；

```
<outdir>/bin/packages/aarch64_cortex-a53/nas/netbird_<v>-r<n>_aarch64_cortex-a53.ipk
<outdir>/bin/packages/x86_64/nas/netbird_<v>-r<n>_x86_64.ipk
<outdir>/bin/packages/all/nas_luci/luci-app-netbird_<lv>-r<lr>_all.ipk
<outdir>/applications/app-meta-netbird/{Makefile,logo.png}
```

- [ ] **Step 1: 写失败测试**

断言：源 ipk 不被修改；a53 变体 control 的 `Architecture` 改变且其他字段不变；x86_64/LuCI 原样复制；元数据 `PKG_VERSION` 与 netbird 版本一致、`META_DEPENDS:=+netbird +luci-app-netbird`、`META_LUCI_ENTRY:=/cgi-bin/luci/admin/services/netbird`；错误输入退出 2；`logo.png` ≤ 50KB。

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：解包→替换 Architecture→确定性重打包；复制其他包；用 `sed` 按版本渲染模板；校验目录名/文件名与 control 架构一致。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 写 `docs/ISTORE-PR.md`**

包含：bundle 内容、元数据 PR 步骤、ipk PR 到 `pending` 的步骤、PR 模板字段、描述文案（「官方源 0.59.13，缺 LuCI；本 PR 补齐最新完整组合」）、被拒退路、a53 标签说明。

- [ ] **Step 6: Commit**

```bash
git add scripts/make-istore.sh packaging/istore tests/make-istore.bats docs/ISTORE-PR.md
git commit -m "feat(istore): produce PR-ready ipk bundle and app metadata"
```

---

### Task 11: CI 工作流

**Files:**
- Create: `.github/workflows/upstream-watch.yml`、`.github/workflows/build-release.yml`、`.github/dependabot.yml`
- Test: `tests/workflows.bats`

**Interfaces:**
- Consumes: Task 4/2/5/6/7/9/10 脚本。
- Produces: 周更版本提交、构建/签名/发布、Pages 部署。

- [ ] **Step 1: 写失败测试**

断言（grep YAML）：`upstream-watch` 有 `schedule` + `workflow_dispatch` + `contents: write`；`build-release` 有 `workflow_run`（监听 upstream-watch）与 `workflow_dispatch`；job 名为 `build`、`build-luci`、`sign-publish`、`deploy-pages`；`sign-publish` 使用 `environment: release`，`deploy-pages` 使用 `environment: github-pages`；`sign-publish` 含 `pages` 之外的写权限；无 `pull_request_target`；所有 `uses:` 带 40 位 SHA。

- [ ] **Step 2: 运行确认失败** → `bats tests/workflows.bats` FAIL

- [ ] **Step 3: 实现工作流**

`upstream-watch`：checkout → `resolve-upstream.sh` → 无变化退出 → 下载 tarball 校验 → 更新 env（新版本 `PKG_RELEASE=1`）→ bot commit。
`build-release`：`build`（matrix；setup-go 1.26.2；下载校验；`build-netbird.sh`；collect-licenses；build-netbird-ipk；verify；upload artifact + SHA256SUMS）；`build-luci`（SDK + patch + build + verify）；`sign-publish`（下载 artifact + 校验 SHA256SUMS；取回上一版；make-feed；make-istore；sign；Release；attest；upload-pages-artifact）；`deploy-pages`（deploy-pages + 抽样校验）。
`dependabot.yml`：`github-actions` 周更。

- [ ] **Step 4: 运行确认通过** → `bats tests/workflows.bats` PASS；`actionlint` 通过

- [ ] **Step 5: Commit**

```bash
git add .github/ tests/workflows.bats
git commit -m "ci: add upstream watch, build/sign/release pipeline and pages deploy"
```

---

### Task 12: 本地一键验收与文档

**Files:**
- Modify: `Makefile`（`build`/`feed`/`istore`/`e2e` 目标）
- Create: `README.md`、`docs/INSTALL.md`、`docs/REVIEW.md`、`docs/THREAT-MODEL.md`
- Test: `tests/e2e.bats`

**Interfaces:**
- `make e2e`：用 fixture 二进制跑通 build-netbird-ipk → verify → make-feed → 用临时密钥 sign → 假 root install-feed → 断言 `Packages.sig` 与 feed 行；同一 `SOURCE_DATE_EPOCH` 构建两次并比较 ipk sha256。

- [ ] **Step 1: 写失败测试**：`bats tests/e2e.bats` 断言 `make e2e` 退出 0，且 `dist/feed/Packages.sig` 存在、假 root 的 `customfeeds.conf` 含一行。
- [ ] **Step 2: 运行确认失败**
- [ ] **Step 3: 实现 `make e2e` 与文档**：README 给出 feed 地址、指纹、安装命令、iStore 上架说明；INSTALL 给自建管理面（`--management-url`、私有 CA、`SSL_CERT_FILE`）与设备验收；REVIEW 记录上游修正与 LuCI 副作用；THREAT-MODEL 按 spec §11。
- [ ] **Step 4: 运行确认通过**
- [ ] **Step 5: Commit**

```bash
git add Makefile README.md docs tests/e2e.bats
git commit -m "feat(local): one-command e2e flow and operator docs"
```

---

### Task 13: 真机验收与 iStore PR（人工）

**Files:**
- Modify: `docs/ISTORE-PR.md`（勾选清单）、`docs/INSTALL.md`（实测结果）

- [ ] **Step 1:** 在 R4S 与 R68S 上 `opkg update && opkg install netbird luci-app-netbird`；按 spec §12.4 验收（版本、状态、重启、降级、DNS、fw4、SSH、卸载）。
- [ ] **Step 2:** 两机分别用 `netbird up --management-url <自建地址> --setup-key <KEY>` 与 LuCI 认证页连接自建管理面，重启后复查。
- [ ] **Step 3:** 用 iStore「手动安装」上传 `aarch64_cortex-a53` 变体，确认可装可启（如架构被拒，记录实际报错到 §19）。
- [ ] **Step 4:** 提 `openwrt-app-meta` PR（先），再提 `istore-repo` PR 到 `pending`，描述使用「补齐最新完整组合」文案。
- [ ] **Step 5:** 把 PR 链接与结果写回 `docs/ISTORE-PR.md`，提交。

---

## Self-Review

- **Spec coverage:** §7.1–7.7（任务 0/1/2/2b/9/10/12）、§8（9/11）、§9（6/7/8/11）、§10（11）、§11（12）、§12（1–12）、§13（各脚本任务）、§14（错误路径测试）、§15（6/11）、§16（10/13）、§18（阶段映射）、§19（13）、§22（2/9/12）。OPNsense（§17）按 spec 明确不在本期。
- **Step scan:** 每个测试步给断言，每个实现步给签名/产物；无 “handle edge cases” 类空步。
- **Type consistency:** 脚本参数与 spec §13 一致；`install-feed.sh` 的 `--root` 已在 spec 增补；iStore 路径与 §16 一致。
- **Review Focus:** 每项都已落到任务（1：env；2：确定性；3/10：架构；6/7：feed 一致性；9：补丁失败）。
- **Proportion:** 13 个任务覆盖 6 个阶段；实现细节交给执行者，计划只锁定接口与验收。
