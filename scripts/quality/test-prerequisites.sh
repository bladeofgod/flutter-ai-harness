#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RG=true bash "$ROOT/scripts/check-prerequisites.sh" >/dev/null

if RG=flutter_ai_harness_missing_rg \
  bash "$ROOT/scripts/check-prerequisites.sh" >/dev/null 2>&1; then
  echo "错误：前置检查未拒绝缺失的 ripgrep。" >&2
  exit 1
fi

setup_plan="$(make --no-print-directory -n -C "$ROOT" setup)"
check_plan="$(make --no-print-directory -n -C "$ROOT" check)"
bootstrap_plan="$(make --no-print-directory -n -C "$ROOT" bootstrap)"

if [[ "$setup_plan" != *"scripts/check-prerequisites.sh"* ]]; then
  echo "错误：make setup 未运行前置检查。" >&2
  exit 1
fi
if [[ "$check_plan" != *"scripts/check-prerequisites.sh"* ]]; then
  echo "错误：make check 未运行前置检查。" >&2
  exit 1
fi
if [[ "$bootstrap_plan" == *"scripts/check-prerequisites.sh"* ]]; then
  echo "错误：make bootstrap 不应依赖仅质量门禁需要的 ripgrep。" >&2
  exit 1
fi

echo "[prerequisites-test] ripgrep 前置检查与 Make 依赖边界 Fixture 通过。"
