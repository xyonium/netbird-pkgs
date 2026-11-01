# iStoreOS 上架 PR 清单

## 产物

`make istore` 生成 `dist/istore/`：

```
bin/packages/aarch64_cortex-a53/nas/netbird_<ver>-r<N>_aarch64_cortex-a53.ipk
bin/packages/x86_64/nas/netbird_<ver>-r<N>_x86_64.ipk
bin/packages/all/nas_luci/luci-app-netbird_<lv>-r<lr>_all.ipk
bin/packages/all/nas_luci/luci-i18n-netbird-zh-cn_<lv>-r<lr>_all.ipk   # 若构建产出
applications/app-meta-netbird/{Makefile,logo.png}
```

- aarch64 包由 `aarch64_generic` 产物重打包 `Architecture` 得到，二进制不变。
- iStoreOS 的 aarch64 opkg 配置同时接受 `aarch64_generic`（优先级 5）与 `aarch64_cortex-a53`（优先级 10），所以 cortex-a53 标签可安装；它**不是** CPU 指令集优化，Go 的 arm64 产物是通用 ARMv8-A。
- 文件名含版本且不可重复，符合 iStore「每次上传不能重名」。

## 步骤

1. **元数据 PR（先做）**
   - fork `linkease/openwrt-app-meta`，从 `main` 拉临时分支；
   - 复制 `dist/istore/applications/app-meta-netbird/` 到 `applications/`；
   - 提交 PR，记录 PR 链接。

2. **ipk PR**
   - fork `istoreos/istore-repo`，从 `main` 拉临时分支；
   - 复制 `dist/istore/bin/packages/**` 到 fork 的 `bin/packages/**`；
   - 目标分支必须选 **`pending`**；
   - 不要改 `.github/workflows` 或 `repo/`。

3. **PR 模板填写**
   - [x] 文件已经上传
   - [x] 确认 PR 的目标分支是 `pending`
   - 元数据 PR 链接：<第 1 步的链接>
   - 开源软件：是
   - 代码仓库：https://github.com/xyonium/netbird-pkgs

4. **PR 描述（补齐最新完整组合）**

   > 官方 OpenWrt 源的 `netbird` 仍为 0.59.13，iStore 中也缺少可用的 LuCI 管理界面；本 PR 提供最新的 `netbird 0.82.0`（aarch64_cortex-a53 / x86_64）与 `luci-app-netbird 0.1.0-r26`，补齐「最新二进制 + LuCI」的完整组合。源码与构建：https://github.com/xyonium/netbird-pkgs 。

## 被拒时的退路

- iStore README 规定「不要提交 OpenWrt 官方源已有的包」。`netbird` 属于官方已有包，但有 `tailscale` 先例（官方也有，iStore 仍收录新版本）。若维护者拒绝 netbird：仅保留 `luci-app-netbird`（官方源没有），netbird 继续由自建签名 feed 分发。
- 上架后由 iStore 分发，不再经过本仓库 `usign` 校验；自建 feed 仍是权威来源，设备可同时添加，opkg 按版本取新。

## 版本更新

每次发版后重跑 `make istore`，只上传新文件名；旧文件由上游合并时清理。元数据 `PKG_RELEASE` 在仅改元数据时递增。
