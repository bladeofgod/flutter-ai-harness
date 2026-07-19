#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${TOOL_WORKDIR:-$ROOT/app}"
cd "$WORKDIR"

if command -v fvm >/dev/null 2>&1; then
  exec fvm flutter "$@"
fi

if [[ -x "$ROOT/app/.fvm/flutter_sdk/bin/flutter" ]]; then
  exec "$ROOT/app/.fvm/flutter_sdk/bin/flutter" "$@"
fi

if command -v flutter >/dev/null 2>&1; then
  exec flutter "$@"
fi

echo "错误：未找到 Flutter。请安装 FVM 并执行 fvm install，或将 Flutter 加入 PATH。" >&2
exit 1
