# netbird-pkgs

NetBird 客户端与 LuCI 管理界面的 OpenWrt 软件包仓库（iStoreOS 24.10 / opkg）。

- 上游：`netbirdio/netbird`（客户端，BSD-3-Clause）
- 管理面：支持 NetBird Cloud 与**自建管理面**（自定义 `--management-url`）
- Feed：`https://xyonium.github.io/netbird-pkgs/`
- 公钥指纹：见 `keys/netbird-pkgs.pub` 的 `usign -F -p` 输出

## 设备安装

```sh
# 下载并执行（先检查脚本内容）
scripts/install-feed.sh --feed-url https://xyonium.github.io/netbird-pkgs \
  --key-url https://xyonium.github.io/netbird-pkgs/keys/netbird-pkgs.pub \
  --arch auto --yes
opkg update
opkg install netbird luci-app-netbird
```

自建管理面：

```sh
netbird up --management-url https://netbird.example.com --setup-key <KEY>
```

详见 [docs/INSTALL.md](docs/INSTALL.md)。

## 本仓库构建

```sh
make lint test      # shellcheck + bats（含 e2e）
make e2e            # 两次构建比对 + 索引 + 签名 + 假 root 安装
```

真实构建需要 Go `1.26.2`、GNU tar/gzip；CI 使用 `setup-go` 固定版本。

## iStoreOS 上架

`make istore`（CI 中由 `build-release` 调用）生成 `dist/istore/`，PR 步骤见
[docs/ISTORE-PR.md](docs/ISTORE-PR.md)。

## 许可

本仓库脚本与文档：MIT。`netbird` 客户端：BSD-3-Clause，许可文本随包安装；
`luci-app-netbird`：Apache-2.0。详见 [docs/REVIEW.md](docs/REVIEW.md) 与包内
`/usr/share/licenses/`。
