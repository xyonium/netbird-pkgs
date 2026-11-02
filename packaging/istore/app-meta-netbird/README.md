# iStore 元数据资源

`logo.png` 是 NetBird 官方 logomark，取自 <https://netbird.io/press>
（`Logomark SVG` / 站点 `icon.png`），用于**标识本包所管理的 NetBird 软件本身**，
符合其品牌规范（不改色、不加特效、保持留白）。

- 尺寸 144×144，PNG RGBA，约 5 KB（元数据要求 ≤ 50 KB）
- 商标归 NetBird GmbH 所有；本仓库仅按指示性使用（nominative use），不主张任何权利
- 若 NetBird 官方要求更换或撤下，替换本文件即可，`scripts/make-istore.sh` 会原样打包

不要放回纯色占位图：`tests/make-istore.bats` 会检查图标的字节数与边长，
空白占位图会让测试失败。
