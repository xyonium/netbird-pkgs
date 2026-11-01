# 威胁模型

## 信任边界

| 组件 | 权限 | 风险 |
|---|---|---|
| `netbird` 二进制 | root | WireGuard 私钥落盘（`/etc/netbird/config.json`，0600） |
| `luci-app-netbird` | root（LuCI/ubus） | 可读任意文件，含 `config.json`；可切换二进制来源 |
| 本仓库 CI | 写 Release + 持签名私钥 | 上游投毒可污染产物 |
| `release` environment | 仅签名 job 可见 | 工作流配置错误扩大暴露面 |
| iStore 分发 | iStoreOS 的 feed 信任 | 脱离本仓库 `usign` 校验 |

## 控制措施

- 构建 job 不注入 Secret；签名 job 不执行上游代码；两者用 artifact + `SHA256SUMS` 衔接。
- 全部 `uses:` 钉完整 SHA；默认 `permissions: contents: read`，按 job 提权。
- 源码 tarball sha256、`GOFLAGS=-mod=readonly`、Go sumdb、`GOTOOLCHAIN=local`。
- `-trimpath -buildvcs=false`、固定 `SOURCE_DATE_EPOCH`；CI 夜间双构建比对。
- `luci-app-netbird` 版本必须人工合并 PR；`binary_source` 默认 `opkg`。
- 签名私钥仅存 `release` environment secret；公钥与指纹公示。
- 发布附 SLSA provenance 与 `SHA256SUMS`。

## 残余风险（接受）

CI 持有签名私钥：上游投毒会产出带本仓库签名的包。补偿是轮换、provenance、
审计链与回滚，而非事前阻断。`sha256` 只证明首次获取后的完整性，不能证明首次
获取的 tarball 即上游真实产物。

## 密钥轮换

1. 计划内：生成新钥 → 发布新公钥并留约一周导入窗口 → 切换签名 → 两个周期后移除旧钥。
2. 应急：撤销 Secret、生成新钥、重签 feed、发布通告；未导入新钥的设备会验签失败（预期）。
3. 私钥不加口令（CI 无人值守）；保护面为 Secret + environment 分支限制 + 仓库权限。
