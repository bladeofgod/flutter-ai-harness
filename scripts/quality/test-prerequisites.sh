#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RG=true bash "$ROOT/scripts/check-prerequisites.sh" >/dev/null

if RG=flutter_ai_harness_missing_rg \
  bash "$ROOT/scripts/check-prerequisites.sh" >/dev/null 2>&1; then
  echo "错误：前置检查未拒绝缺失的 ripgrep。" >&2
  exit 1
fi

echo "[prerequisites-test] ripgrep 前置检查 Fixture 通过。"
