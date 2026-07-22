#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

packages="$({
  find "$ROOT/app/apps" "$ROOT/app/packages" -type f -path '*/test/*_test.dart' 2>/dev/null || true
} | sed -E 's#^(.*/(apps|packages)/[^/]+)/.*#\1#' | sort -u)"

if [[ -z "$packages" ]]; then
  echo "[test] 当前没有测试文件，跳过。"
  exit 0
fi

status=0
while IFS= read -r package <&3; do
  [[ -n "$package" ]] || continue
  echo "[test] $(basename "$package")"
  if rg -q 'sdk:[[:space:]]+flutter' "$package/pubspec.yaml"; then
    if ! TOOL_WORKDIR="$package" bash "$ROOT/scripts/flutter-tool.sh" test; then
      status=1
    fi
  else
    if ! TOOL_WORKDIR="$package" bash "$ROOT/scripts/dart-tool.sh" test; then
      status=1
    fi
  fi
done 3<<< "$packages"

exit "$status"
