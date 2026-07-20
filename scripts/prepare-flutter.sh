#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_VERSION="$(sed -nE \
  's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
  "$ROOT/app/.fvmrc")"

if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "错误：无法从 app/.fvmrc 读取 Flutter 版本。" >&2
  exit 1
fi

if command -v fvm >/dev/null 2>&1; then
  echo "[setup] 使用 FVM 准备 Flutter $EXPECTED_VERSION"
  (
    cd "$ROOT/app"
    fvm install "$EXPECTED_VERSION"
  )
elif ! command -v flutter >/dev/null 2>&1; then
  echo "错误：未找到 FVM 或 Flutter。请先安装 FVM，或安装 Flutter $EXPECTED_VERSION。" >&2
  exit 1
else
  echo "[setup] 未检测到 FVM，校验系统 Flutter"
fi

actual_version="$(
  bash "$ROOT/scripts/flutter-tool.sh" --version \
    | sed -nE '1s/^Flutter ([^[:space:]]+).*/\1/p'
)"
if [[ "$actual_version" != "$EXPECTED_VERSION" ]]; then
  echo "错误：当前 Flutter 为 ${actual_version:-unknown}，要求 $EXPECTED_VERSION。" >&2
  exit 1
fi

echo "[setup] Flutter $EXPECTED_VERSION 已就绪。"
