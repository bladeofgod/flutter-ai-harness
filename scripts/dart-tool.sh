#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${TOOL_WORKDIR:-$ROOT/app}"
cd "$WORKDIR"

if command -v fvm >/dev/null 2>&1; then
  exec fvm dart "$@"
fi

if [[ -x "$ROOT/app/.fvm/flutter_sdk/bin/dart" ]]; then
  exec "$ROOT/app/.fvm/flutter_sdk/bin/dart" "$@"
fi

if command -v dart >/dev/null 2>&1; then
  exec dart "$@"
fi

echo "错误：未找到 Dart。请安装 FVM 并执行 fvm install，或将 Dart 加入 PATH。" >&2
exit 1
