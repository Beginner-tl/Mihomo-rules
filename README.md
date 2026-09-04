# clash-rules

面向 Sparkle / Mihomo 的规则源。

## 规则说明

- 提供域名和 IP 的 MRS 规则，同时保留可直接查看的 TXT 规则。
- `GameStore.mrs/txt`：游戏平台和商店规则，走“游戏平台”策略组。
- `GameDownload.mrs`：游戏下载规则。
- `GameDownloadCustom.mrs/txt`：自定义游戏 CDN 规则，直连。
- `CrossBorder.mrs/txt`：跨境电商相关域名，直连。
- 规则产物发布在 `release` 分支的 `mihomo/domain` 和 `mihomo/ip` 目录。
- GitHub Actions 自动同步、编译并发布 MRS/TXT。

Sparkle 覆写：

```
https://raw.githubusercontent.com/Beginner-tl/clash-rules/main/sparkle-override.yaml
```
