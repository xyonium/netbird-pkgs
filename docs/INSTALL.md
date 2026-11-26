# 安装与验收

## 1. 接入 feed

```sh
wget -O /tmp/netbird-pkgs.pub https://xyonium.github.io/netbird-pkgs/keys/netbird-pkgs.pub
usign -F -p /tmp/netbird-pkgs.pub          # 记下 16 位指纹
scripts/install-feed.sh --feed-url https://xyonium.github.io/netbird-pkgs \
  --key-file /tmp/netbird-pkgs.pub --arch auto --yes
opkg update
```

`--arch auto` 只在 feed 支持的架构（`aarch64_generic`、`x86_64`）中选择；
iStoreOS 额外登记的 `aarch64_cortex-a53` 是商店标签，不是本 feed 的目录。

## 2. 安装与自建管理面

```sh
opkg install netbird luci-app-netbird
netbird up --management-url https://netbird.example.com --setup-key <KEY>
netbird status          # Management: Connected
```

LuCI：Services → NetBird → 认证页填 Management URL 与 Setup Key。

私有 CA：

```sh
cat internal-ca.pem >> /etc/ssl/certs/ca-certificates.crt
# 或
echo 'SSL_CERT_FILE=/etc/ssl/certs/internal-ca.pem' >> /etc/netbird.env
/etc/init.d/netbird restart
```

## 3. 验收清单

```sh
netbird version
netbird status
/etc/init.d/netbird enable && reboot
pgrep -f 'netbird service run'
logread -e netbird | tail
ls -l /etc/netbird/config.json          # 0600
opkg install netbird=<旧版本>            # 降级路径
nslookup <内网域名>                      # DNS 正常
nft list ruleset | grep -i netbird      # fw4 规则存在
grep -i netbird /etc/ssh/sshd_config || true
```

## 4. 回滚与停用

```sh
opkg install netbird=<旧版本>
/etc/init.d/netbird stop && /etc/init.d/netbird disable
```

## 5. 故障排查

- `opkg update` 验签失败：确认 `/etc/opkg/keys/<16 位指纹>` 与 feed 的 `Packages.sig` 对应；缓存 10 分钟后重试。
- 服务不启动：`logread -e netbird`；确认 `/etc/netbird` 可写、`/var/lib/netbird` 已创建。
- LuCI 页面无日志：确认 `/etc/netbird.env` 含 `NB_LOG_FILE=syslog`（LuCI 首次启动会写入）。
- **同机开着 passwall / mwan3 时，LAN 代理不通但本机与直连正常**：NetBird 启用高级路由
  （且未关闭 `accept_client_routes`）时有两处影响：
  1. 会写入全局 `net.ipv4.conf.all.src_valid_mark=1`，导致 LAN 入站命中 TPROXY
     （`fwmark 1 → table 100 local`）的包在内核源地址反查时因 `accept_local=0`
     被当成 `martian_source` 静默丢弃（`/proc/net/stat/rt_cache` 中 `in_martian_src`
     计数增长），即使 `table 7120` 为空且 `fwmark 1` 排在前面也会失效；
  2. 会安装 `105: lookup main suppress_prefixlength 0` 与
     `110: not fwmark 0x1bd00 lookup netbird`，查 `main` 时抑制 `/0` 默认路由并接管给
     `table 7120`（与出口节点、mwan3 或抢先启动的策略路由冲突）。

  处置方式：
  - **仅需被 SSH 连入（无需接收对端路由）**：在 LuCI / UCI 中关闭
    `accept_client_routes`（`--disable-client-routes=true`），NetBird 会直接跳过
    路由初始化，既不改 `src_valid_mark`、不装 `105/110`，也不会在 `main` 表插
    legacy `/32` 排除路由；
  - **需要接收对端私网路由**：在上游修复 `all.src_valid_mark=1`（见
    `netbirdio/netbird#4575`）正式发版前，写入 `NB_USE_LEGACY_ROUTING=true` 到
    `/etc/netbird.env` 后重启服务即可：

        echo 'NB_USE_LEGACY_ROUTING=true' >> /etc/netbird.env
        /etc/init.d/netbird restart
        ip rule show | grep -E '105|110'            # 应无输出
        sysctl -n net.ipv4.conf.all.src_valid_mark  # 应为 0

    注意：此前若曾跑过未加该开关的高级路由，旧版本可能已把 `all.src_valid_mark`
    设为 `1` 且服务停止前未恢复时不会自动清零，必要时重启路由或执行
    `sysctl -w net.ipv4.conf.all.src_valid_mark=0`。legacy 代价是改走 `/32`
    exclusion route，不应在同机同时启用 Exit Node（`0.0.0.0/0`）或接管系统 DNS
    （`enable_dns=0`）。
