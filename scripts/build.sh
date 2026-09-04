#!/usr/bin/env bash
# =============================================================================
# build.sh —— 同步基础规则，并编译本仓库规则与可读 TXT
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"
exec python3 "$SCRIPT_DIR/build.py" "$@"
