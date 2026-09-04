# Mihomo

面向 Sparkle / Mihomo 的规则源。

## 规则说明

- 规则细则来自多个公开上游，包括 [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script)、[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)、[Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) 等；本仓库按用途整理后发布。
- 提供域名和 IP 的 MRS 规则，同时保留可直接查看的 TXT 规则。
- `GameStore.mrs/txt`：游戏平台和商店规则，走“游戏平台”策略组。
- `GameDownload.mrs`：游戏下载规则。
- `GameDownloadCustom.mrs/txt`：自定义游戏 CDN 规则，直连。
- `CrossBorder.mrs/txt`：跨境电商相关域名，直连。
- 规则产物发布在 `main` 分支的 `mihomo/domain` 和 `mihomo/ip` 目录。
- GitHub Actions 自动同步、编译并发布 MRS/TXT。

Sparkle 覆写：

```
https://raw.githubusercontent.com/Beginner-tl/Mihomo-rules/main/sparkle-override.yaml
```
