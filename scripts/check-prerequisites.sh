#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-rg}"

if ! command -v "$RG" >/dev/null 2>&1; then
  cat >&2 <<'EOF'
错误：未找到 ripgrep（rg），仓库质量门禁和 Git Hooks 依赖该工具。
macOS：brew install ripgrep
Ubuntu/Debian：sudo apt-get update && sudo apt-get install --yes ripgrep
EOF
  exit 1
fi

echo "[prerequisites] ripgrep 已就绪。"
