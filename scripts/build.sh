#!/usr/bin/env bash
# =============================================================================
# build.sh —— 同步 666OS 已整合 MRS，并编译本仓库自定义/派生规则
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"
exec python3 "$SCRIPT_DIR/build.py" "$@"
