# clash-rules

面向 Sparkle / Mihomo 的规则源。

## 规则说明

- 以 [666OS/rules](https://github.com/666OS/rules/tree/release) 的 `release` 分支作为基础规则。
- 同步 666OS 已整合的域名和 IP MRS 规则。
- `GameStore.mrs`：666OS 游戏平台总表加自定义商店规则，走“游戏平台”策略组。
- `GameDownload.mrs`：游戏下载规则。
- `GameDownloadCustom.mrs`：自定义游戏 CDN 规则，直连。
- `CrossBorder.mrs)：跨境电商相关域名，直连。
- 规则产物发布在 `release` 分支的 `mihomo/domain` 和 `mihomo/ip` 目录。
- GitHub Actions 自动同步和编译规则。

Sparkle 覆写：

```
https://raw.githubusercontent.com/Beginner-tl/clash-rules/main/sparkle-override.yaml
```
