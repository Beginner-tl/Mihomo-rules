# clash-rules

这是一个面向 Sparkle / Mihomo 的下游规则源：

- 以 [666OS/rules 的 release 分支](https://github.com/666OS/rules/tree/release)作为已整合规则基线；
- 镜像其 domain/ip 下的 MRS 文件到本仓库的 release 分支；
- 用 666OS 的 `Games.txt` 加上本仓库的 `game-store.list`，重新编译 `GameStore.mrs`；
- 使用游戏 CDN 规则生成 `GameDownloadCustom.mrs`，并镜像现有的游戏游戏下载 MRS 为 `GameDownload.mrs`；
- 编译 `CrossBorder.mrs`，用于把天猫国际、菜鸟国际、Alibaba/WorldFirst 等域名优先直连。

## 自动更新

GitHub Actions 工作流 [sync-rules.yml](.github/workflows/sync-rules.yml) 会在每天北京时间 00:30、手动运行或 scripts 发生变更时执行：

1. 拉取 666OS/rules 的 `release` 分支；
2. 同步其现成 MRS；
3. 下载游戏游戏下载 MRS；
4. 编译本仓库的派生和自定义规则；
5. 将全量产物强制发布到本仓库的 `release` 分支。

工作流使用 GitHub Actions 自动提供的 `GITHUB_TOKEN` 推送产物，不需要配置或索取你的个人 Token。

## Sparkle 使用

在 Sparkle 的“覆写”中新建远程 YAML，引用：

```
https://raw.githubusercontent.com/Beginner-tl/clash-rules/main/sparkle-override.yaml
```

覆写中的规则集会从以下位置加载：

```
https://raw.githubusercontent.com/Beginner-tl/clash-rules/release/mihomo/domain/<Name>.mrs
https://raw.githubusercontent.com/Beginner-tl/clash-rules/release/mihomo/ip/<Name>.mrs
```

订阅和覆写仍然是分开的：Sub-Store 提供节点订阅，Sparkle 覆写负责代理组、故障转移、规则顺序以及规则集地址。

当前覆写的目标是：

- 游戏商店/登录/社区等命中 `商店` 时进入“游戏平台”策略组；
- 游戏下载先匹配 `下载` 和 `下载补充`，直连；
- `CrossBorder` 和 `alimama.hk` 在国外流量之前优先直连；
- 其余平台策略组仍可在 Sparkle 中选择地区、故障转移、手动节点、自动测速和负载均衡。

## 自定义规则

- [game-store.list](scripts/custom/game-store.list)：游戏商店/平台补充；
- [game-download.list](scripts/custom/game-download.list)：游戏下载 CDN 补充；
- [crossborder-ecommerce.list](scripts/custom/crossborder-ecommerce.list)：跨境电商直连补充；
- [custom-direct.list](scripts/custom/custom-direct.list) 和 [custom-proxy.list](scripts/custom/custom-proxy.list)：留作后续追加；
- `emby.list` 默认不参与公开构建。私人影视域名不要提交到公开仓库。

MRS 是二进制规则集，不能把多个 MRS 文件直接拼接；本项目通过上游 TXT + 自定义文本重新编译需要合并的分类，其余分类直接镜像上游 MRS。
