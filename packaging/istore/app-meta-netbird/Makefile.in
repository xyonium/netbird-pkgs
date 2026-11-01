# This is free software, licensed under the Apache License, Version 2.0.
# Rendered by scripts/make-istore.sh — do not edit the copy in dist/.

include $(TOPDIR)/rules.mk

PKG_NAME:=netbird
PKG_VERSION:=@VERSION@
PKG_RELEASE:=@RELEASE@
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

include ../../meta.mk

# call BuildPackage - OpenWrt buildroot signature
