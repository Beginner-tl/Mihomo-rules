#!/usr/bin/env bash
# =============================================================================
# build.sh —— 抓取上游规则、合并去重、编译 mihomo .mrs
# =============================================================================
# 工作流：
#   1. 解析 scripts/sources.yaml（用内嵌 Python，避免依赖 yq）
#   2. 对每个 category：
#        - 下载每个 source.url（拼上 suffix）
#        - 按 source.format 解析成「纯域名行」或「纯 CIDR 行」
#        - 追加 custom/*.list
#        - sort -u 去重
#        - 用 mihomo convert-ruleset 编译成 .mrs
#   3. 输出到 dist/mihomo/{domain,ip}/<Name>.mrs
#
# 单个上游失败不中断整体（打印 WARN 继续下一个），保证产物可用。
# =============================================================================
set -euo pipefail

# ---------- 路径与参数 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_YAML="$SCRIPT_DIR/sources.yaml"
CUSTOM_DIR="$SCRIPT_DIR/custom"
DIST="$REPO_ROOT/dist"
MIHOMO_BIN="${MIHOMO_BIN:-mihomo}"   # 由 workflow 注入；本地测试可用 PATH 里的 mihomo

# 临时工作区
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DOMAIN_OUT="$DIST/mihomo/domain"
IP_OUT="$DIST/mihomo/ip"
mkdir -p "$DOMAIN_OUT" "$IP_OUT"

# 颜色
C_RED='\033[31m'; C_YEL='\033[33m'; C_GRN='\033[32m'; C_BLU='\033[34m'; C_RST='\033[0m'
log()  { printf "${C_BLU}[*]${C_RST} %s\n" "$*"; }
ok()   { printf "${C_GRN}[✓]${C_RST} %s\n" "$*"; }
warn() { printf "${C_YEL}[!]${C_RST} %s\n" "$*" >&2; }
err()  { printf "${C_RED}[✗]${C_RST} %s\n" "$*" >&2; }

# ---------- 解析 sources.yaml → JSON ----------
# 用 Python 标准库解析（CI 环境自带 python3），把每个 category 展开成扁平结构
parse_sources() {
  python3 - "$SOURCES_YAML" <<'PY'
import sys, json, yaml, os
with open(sys.argv[1], encoding='utf-8') as f:
    doc = yaml.safe_load(f)
# 展开锚点：meta_domain / meta_ip / bm 在 yaml 里是标量字符串，source 里用 suffix 拼接
cats = []
for c in doc.get('categories', []):
    srcs = []
    for s in c.get('sources', []) or []:
        url = s.get('url','') + (s.get('suffix','') or '')
        srcs.append({
            'url': url,
            'format': s.get('format','plain'),
            'invert': bool(s.get('invert', False)),
        })
    cats.append({
        'name': c['name'],
        'behavior': c['behavior'],
        'sources': srcs,
        'custom': c.get('custom', []) or [],
    })
print(json.dumps(cats))
PY
}

# ---------- 下载（带重试，失败返回空）----------
fetch() {
  local url="$1" dest="$2"
  local code
  for attempt in 1 2 3; do
    code=$(curl -fsSL --connect-timeout 15 --max-time 60 -o "$dest" -w '%{http_code}' "$url" 2>/dev/null || true)
    if [[ "$code" == "200" ]]; then return 0; fi
    sleep $((attempt * 2))
  done
  return 1
}

# ---------- 格式解析器：输出标准域名行（+.domain 或裸 domain）----------
# 输入：源文件路径 + format
# （invert 参数为预留，当前未实现取反；如需排除某上游的域名，改用 custom 维护白名单）
parse_domains() {
  local file="$1" fmt="$2" invert="${3:-false}"
  case "$fmt" in
    dnsmasq)
      # meta .list 格式：每行可能是 +.domain / 裸 domain / # 注释 / include: 指令
      grep -vE '^\s*(#|$)' "$file" 2>/dev/null \
        | grep -vE '^(include|attribute):' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
      ;;
    classical)
      # blackmatrix7 .yaml payload：DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD,x
      grep -E '^\s*-\s*(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD)' "$file" 2>/dev/null \
        | sed -E 's/^\s*-\s*//; s/[[:space:]]*$//' \
        | awk -F',' '{
            t=$1; d=$2;
            if (t=="DOMAIN-SUFFIX")        print "+." d;
            else if (t=="DOMAIN-KEYWORD")  print "keyword:" d;   # 保留标记，编译前过滤
            else if (t=="DOMAIN")          print d;
          }' || true
      ;;
    plain)
      grep -vE '^\s*(#|$)' "$file" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
      ;;
  esac
}

# ---------- 格式解析器：输出标准 CIDR 行 ----------
parse_cidrs() {
  local file="$1" fmt="$2"
  case "$fmt" in
    dnsmasq|cidr)
      grep -vE '^\s*(#|$)' "$file" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
      ;;
    classical)
      grep -E '^\s*-\s*IP-CIDR' "$file" 2>/dev/null \
        | sed -E 's/^\s*-\s*//; s/[[:space:]]*$//' \
        | awk -F',' '{print $2}' || true
      ;;
    plain)
      grep -vE '^\s*(#|$)' "$file" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
      ;;
  esac
}

# ---------- 编译单个分类 ----------
build_category() {
  local name="$1" behavior="$2"
  shift 2
  # 剩余参数：JSON 字符串（sources + custom）
  local spec="$1"

  local raw="$TMP/$name.raw"      # 合并后的原始域名/CIDR 行
  local final="$TMP/$name.list"   # 去重 + 过滤 keyword 后的最终列表
  local payload="$TMP/$name.payload.yaml"  # mihomo convert 输入（yaml payload 格式）
  local outdir outpath
  : > "$raw"

  # 1. 处理每个上游 source
  local n_src; n_src=$(python3 -c "import json;d=json.loads('''$spec''');print(len(d['sources']))")
  local i=0
  while [[ $i -lt $n_src ]]; do
    local url fmt invert
    url=$(python3 -c "import json;d=json.loads('''$spec''');print(d['sources'][$i]['url'])")
    fmt=$(python3 -c "import json;d=json.loads('''$spec''');print(d['sources'][$i]['format'])")
    invert=$(python3 -c "import json;d=json.loads('''$spec''');print(d['sources'][$i]['invert'])")
    local dl="$TMP/${name}_${i}.src"
    if fetch "$url" "$dl"; then
      if [[ "$behavior" == "ipcidr" ]]; then
        parse_cidrs "$dl" "$fmt" >> "$raw"
      else
        parse_domains "$dl" "$fmt" >> "$raw"
      fi
      ok "  拉取: $url"
    else
      warn "  上游失败（跳过）: $url"
    fi
    i=$((i+1))
  done

  # 2. 追加 custom/*.list（这些是 plain 格式，每行一条）
  local n_custom; n_custom=$(python3 -c "import json;d=json.loads('''$spec''');print(len(d['custom']))")
  local j=0
  while [[ $j -lt $n_custom ]]; do
    local cf
    cf=$(python3 -c "import json;d=json.loads('''$spec''');print(d['custom'][$j])")
    local cfp="$CUSTOM_DIR/$cf"
    if [[ -f "$cfp" ]]; then
      if [[ "$behavior" == "ipcidr" ]]; then
        parse_cidrs "$cfp" plain >> "$raw"
      else
        parse_domains "$cfp" plain >> "$raw"
      fi
      ok "  自定义: $cf"
    else
      warn "  自定义文件不存在（跳过）: $cf"
    fi
    j=$((j+1))
  done

  # 3. 清洗：去注释/空行、去重、过滤掉 keyword: 行（MRS domain 不支持 KEYWORD）
  if [[ "$behavior" == "domain" ]]; then
    grep -vE '^\s*(#|keyword:|$)' "$raw" | awk '{print $0}' | sort -u > "$final" || true
  else
    grep -vE '^\s*(#|$)' "$raw" | awk '{print $0}' | sort -u > "$final" || true
  fi

  local count; count=$(wc -l < "$final" | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    warn "  [$name] 合并后为空，跳过编译"
    return 0
  fi

  # 4. 生成 mihomo convert-ruleset 能识别的 yaml payload
  #    domain behavior: payload 是纯域名列表（+.domain 形式直接可用）
  #    ipcidr  behavior: payload 是纯 CIDR 列表
  {
    echo "payload:"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$behavior" == "domain" ]]; then
        echo "  - \"$line\""
      else
        echo "  - \"$line\""
      fi
    done < "$final"
  } > "$payload"

  # 5. 编译 .mrs
  if [[ "$behavior" == "domain" ]]; then
    outdir="$DOMAIN_OUT"; outpath="$DOMAIN_OUT/$name.mrs"
  else
    outdir="$IP_OUT"; outpath="$IP_OUT/$name.mrs"
  fi
  mkdir -p "$outdir"
  if "$MIHOMO_BIN" convert-ruleset "$behavior" yaml "$payload" "$outpath" >/dev/null 2>&1; then
    ok "[$name] 编译完成 → ${outpath#$REPO_ROOT/}（$count 条）"
  else
    err "[$name] 编译失败，保留 payload 供调试: $payload"
    return 1
  fi
}

# ---------- 主流程 ----------
main() {
  log "解析 sources.yaml ..."
  local cats; cats="$(parse_sources)"
  local total; total=$(python3 -c "import json;print(len(json.loads('''$cats''')))")
  log "共 $total 个分类待构建"
  echo

  local idx=0 fail=0
  while [[ $idx -lt $total ]]; do
    local name behavior spec
    name=$(python3 -c "import json;d=json.loads('''$cats''');print(d[$idx]['name'])")
    behavior=$(python3 -c "import json;d=json.loads('''$cats''');print(d[$idx]['behavior'])")
    spec=$(python3 -c "import json,sys;d=json.loads('''$cats''');print(json.dumps(d[$idx]))")
    log "构建: $name ($behavior)"
    if ! build_category "$name" "$behavior" "$spec"; then
      fail=$((fail+1))
    fi
    echo
    idx=$((idx+1))
  done

  log "构建结束。成功 $((total-fail))/$total"
  if [[ $fail -gt 0 ]]; then
    warn "有 $fail 个分类失败（已跳过），其余产物已生成"
  fi
  # 清理空的临时 raw（保留非空的供调试）
  return 0
}

main "$@"
