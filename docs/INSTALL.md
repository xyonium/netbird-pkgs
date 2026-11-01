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
