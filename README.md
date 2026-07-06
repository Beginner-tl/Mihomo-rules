# my-rules · 自建 Clash 规则仓库

一套**完全自有的** Clash（mihomo 内核）规则更新链路。GitHub Actions 每天从**原始上游**抓取规则、按你的分类重命名编译成 `.mrs`、推到 `release` 分支，客户端只读你仓库的 raw 链接。

> 🎯 这套仓库存在的意义：**绕开所有二次中转商**（ddgksf2013 / 666OS / YYDS666），分类命名权 100% 在你手里。

---

## 规则溯源：你在用谁的数据？

```
v2fly/domain-list-community ──┐  (域名分类的"祖宗")
Loyalsoldier/domain-list-custom┘
        │
        ▼
MetaCubeX/meta-rules-dat ──────────┐  (mihomo 官方编译，每日 .mrs/.yaml)
                                   │
blackmatrix7/ios_rule_script ──────┤  (668 个 App，一 App 一组)
                                   │  ← ★ 本仓库直连这两个原始上游
                                   ▼
                       ┌──── my-rules (你的仓库)
                       │      ├ GitHub Actions 每日抓取
                       │      ├ 按你的分类去重合并
                       │      └ 编译成 .mrs 推到 release 分支
                       │
                       └──── 你的 Clash 客户端（只读你的 release 分支）

  ╳ ddgksf2013 (墨鱼)    — 经 jsdelivr 中转 blackmatrix7，分类带其习惯  → 已绕开
  ╳ 666OS/rules          — 私有 Action 二次打包，无法 fork 其 workflow  → 已绕开
  ╳ YYDS666 (Pro_cn)     — 引用 666OS/rules                              → 已绕开
```

**为什么是这两个上游？**
- **MetaCubeX/meta-rules-dat**：mihomo 官方维护，每日编译，提供 `.mrs` 二进制（加载最快、省内存）。分类以 `anthropic/openai/perplexity/netflix/...` 形式组织。
- **blackmatrix7/ios_rule_script**：668 个 App 各自独立（含独立的 `Gemini`、`Copilot`、`Claude`），补 meta 没有独立拆出的应用。

两者数据层同源（meta 的 ChinaMax 反手拉 blackmatrix7），配合使用无冲突。

---

## 仓库结构

```
my-rules/
├── .github/workflows/sync-rules.yml   # ★ 核心：定时抓取+编译+发布
├── scripts/
│   ├── sources.yaml                   # ★ 上游映射表（改分类/换上游，只动这里）
│   ├── build.sh                       # 抓取+去重+合并+编译 mrs
│   └── custom/                        # 你的私有补充规则
│       ├── crossborder-ecommerce.list # 🛒 天猫国际/菜鸟（强制直连）
│       ├── game-download.list         # 🎮 游戏下载 CDN
│       ├── game-store.list            # 🎮 游戏商店/购买
│       ├── emby.list                  # 自建影视
│       ├── custom-direct.list         # 模板：自定义直连
│       └── custom-proxy.list          # 模板：自定义代理
├── config/
│   └── mihomo.yaml                    # ★ 完整可用的 Clash 配置（细粒度分组）
└── README.md
```

`release` 分支（由 Action 自动生成，不入 main）：
```
mihomo/
├── domain/  Claude.mrs, ChatGPT.mrs, CrossBorder.mrs, GameDownload.mrs ...
└── ip/      NetflixIP.mrs, TelegramIP.mrs, GoogleIP.mrs, ChinaIP.mrs ...
```

---

## 首次接入（5 步）

### 1. 在 GitHub 创建仓库
新建一个空仓库（不要勾选 README），名字随意（默认 `my-rules`）。把本地这个目录推上去：
```bash
cd my-rules
git init
git add .
git commit -m "init: 自建规则仓库骨架"
git branch -M main
git remote add origin https://github.com/<你的用户名>/my-rules.git
git push -u origin main
```

### 2. 填你的 GitHub 用户名
打开 `config/mihomo.yaml`，把所有 `<YOUR_GITHUB_USERNAME>` 替换成你的 GitHub 账号。
```bash
# 示例（把 YOUR_NAME 换成你的）
sed -i 's|<YOUR_GITHUB_USERNAME>|YOUR_NAME|g' config/mihomo.yaml
```

### 3. 触发首次构建
进入仓库的 **Actions** 页 → 左侧选 `Sync Rules` → 右上角 `Run workflow` → 等约 3-5 分钟。
构建成功后会自动生成 `release` 分支。

### 4. 填你的机场订阅
打开 `config/mihomo.yaml`，找到 `proxy-providers.Sub.url`，取消注释并填你的机场订阅链接：
```yaml
proxy-providers:
  Sub:
    url: https://your-airport-subscription-link.yaml   # ← 你的订阅
```
> ⚠️ 订阅链接只在你本地，`.gitignore` 已排除 `*.sub.yaml`，别提交到仓库。

### 5. 导入客户端
把 `config/mihomo.yaml` 整个内容导入 Clash Verge Rev / Clash Meta。
**接入完成**，以后规则每天自动更新，你无需再做任何事。

---

## 日常维护指南

### 想加/改一个分类（最常见）
编辑 `scripts/sources.yaml`，每个分类是一段：
```yaml
  - name: Claude                    # 最终 .mrs 文件名
    behavior: domain                # domain 或 ipcidr
    sources:
      - { url: *meta_domain, suffix: anthropic.list, format: dnsmasq }
      - { url: *bm, suffix: Claude/Claude.yaml, format: classical }
    custom: [custom/xxx.list]       # 可选：追加私有域名
```
改完 `git push`，Action 自动触发重建。

### 想给某个分类补私有域名
编辑对应的 `scripts/custom/*.list`，每行一个域名：
- `+.domain` = 该域及其所有子域
- `bare.domain` = 精确匹配
- `#` 开头 = 注释

### 想改某个应用的默认分流区域
编辑 `config/mihomo.yaml` 的锚点数组。例如想让 Claude 改走日本优先，把对应组的 `proxies: *us-first` 改成 `proxies: *jp-first`：
```yaml
  - { name: Claude, type: select, proxies: *jp-first, icon: ... }   # us-first → jp-first
```
或在客户端 UI 里直接切组（`store-selected: true` 已开启，选择会被记住）。

### 想换上游 / 增减上游
在 `sources.yaml` 对应分类的 `sources` 列表里增删条目即可。多源会自动合并去重。

---

## 你的定制分类说明

### 🛒 跨境电商（强制直连）
天猫国际商家中心 + 菜鸟国际 + AliExpress/Alibaba 卖家后台 + WorldFirst 收款。
- 规则集：`CrossBorder.mrs`
- 策略组：`跨境电商`（默认 DIRECT）
- **规则位置**：在 `国外流量` 之前 —— 根治"阿里域名被通用代理规则带走"的老毛病
- 域名清单：`scripts/custom/crossborder-ecommerce.list`

### 🎮 游戏（拆下载/商店两组）
- **游戏下载**（`GameDownload.mrs` → `游戏下载`组）：Steam/Epic/EA/Ubisoft/Battle.net/GOG/Rockstar 的 CDN 大文件，默认倾向直连/低延迟
- **游戏商店**（`GameStore.mrs` → `游戏商店`组）：各平台商店/购买 + PS Store/eShop/Xbox，默认走代理解锁锁区
- 拆分原理：MRS 是域名级规则无法按 URL 路径区分，故按**子域名**归类（CDN 子域 vs 商店子域）
- 域名清单：`scripts/custom/game-download.list` + `game-store.list`

---

## 关键技术点

- **格式**：`.mrs`（mihomo 原生二进制规则集），加载速度和内存占用显著优于 YAML
- **编译工具**：`mihomo convert-ruleset <behavior> yaml <input.yaml> <output.mrs>`（见 mihomo wiki）
- **raw 链接**：`https://raw.githubusercontent.com/<用户名>/my-rules/release/mihomo/<domain|ip>/<Name>.mrs`
- **更新频率**：每日北京时间 00:30 自动构建（UTC 16:30），可随时手动触发
- **容错**：单个上游拉取失败不影响其他分类，保证产物可用

---

## 常见问题

**Q: 首次构建后 `release` 分支没有文件？**
检查 Actions 运行日志。最常见原因是上游某个 URL 临时不可达——build.sh 会跳过失败的上游继续编译，只要至少有一个上游成功就会有产物。

**Q: 某个网站分流不对怎么办？**
1. 在客户端看连接日志，确认它命中的是哪个规则
2. 如果是被通用 `Proxy` 规则误伤：把域名加到对应的 `custom/*.list`
3. 如果完全没命中：加到 `custom-direct.list` 或 `custom-proxy.list`，并在 `sources.yaml` 对应分类挂上 `custom:` 引用

**Q: 想关掉某个分类（比如不用 TikTok）？**
在 `sources.yaml` 删掉那段，同时在 `config/mihomo.yaml` 的 `rules` 和 `proxy-groups` 里删掉对应行，push 即可。

**Q: 可以用回 YAML 格式不用 mrs 吗？**
可以。把 `config/mihomo.yaml` 里 rule-providers 的 `format: mrs` 改成 `format: yaml`，并把 build.sh 的编译产物换成 yaml。但 mrs 更快，不推荐改。
