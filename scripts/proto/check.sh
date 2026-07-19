#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -d "$ROOT/protos" ]]; then
  count="$(find "$ROOT/protos" -type f -name '*.proto' | wc -l | tr -d ' ')"
else
  count=0
fi

if [[ "$count" == "0" ]]; then
  echo "[proto-check] Demo 尚未定义 Proto，跳过同步检查。"
  exit 0
fi

echo "错误：Proto 同步检查尚未随 Demo 协议任务实现。" >&2
exit 1
