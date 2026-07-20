#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${REPOSITORY_ROOT:-$TOOL_ROOT}"
FLUTTER_TOOL_SCRIPT="${FLUTTER_TOOL_SCRIPT:-$TOOL_ROOT/scripts/flutter-tool.sh}"

test_files="$({
  rg --files "$ROOT/app/apps" "$ROOT/app/packages" \
    -g '**/integration_test/**/*_test.dart' 2>/dev/null || true
} | sort)"

if [[ -z "$test_files" ]]; then
  echo "[integration-test] 当前没有 Integration Test，跳过。"
  exit 0
fi

if [[ -z "${INTEGRATION_DEVICE:-}" ]]; then
  echo "错误：检测到 Integration Test，请通过 INTEGRATION_DEVICE 指定设备 ID。" >&2
  echo "示例：make integration-test INTEGRATION_DEVICE=<device-id>" >&2
  exit 64
fi

packages="$(sed -E 's#^(.*/(apps|packages)/[^/]+)/.*#\1#' <<< "$test_files" | sort -u)"
status=0
while IFS= read -r package; do
  [[ -n "$package" ]] || continue
  echo "[integration-test] $(basename "$package") @ $INTEGRATION_DEVICE"
  if ! TOOL_WORKDIR="$package" bash "$FLUTTER_TOOL_SCRIPT" \
    test integration_test -d "$INTEGRATION_DEVICE"; then
    status=1
  fi
done <<< "$packages"

exit "$status"
