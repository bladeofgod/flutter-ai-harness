#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -d "$ROOT/protos" ]]; then
  count="$(find "$ROOT/protos" -type f -name '*.proto' | wc -l | tr -d ' ')"
else
  count=0
fi

if [[ "$count" == "0" ]]; then
  echo "[proto] Demo 尚未定义 Proto，跳过生成。"
  exit 0
fi

echo "错误：检测到 Proto，但 Demo 的公开生成配置尚未建立。请先通过任务卡定义生成输入、输出和 protoc 版本。" >&2
exit 1
