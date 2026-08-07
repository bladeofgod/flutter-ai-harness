#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${REPOSITORY_ROOT:-$TOOL_ROOT}"
fail=0
targets=()

if [[ "$#" -gt 0 ]]; then
  targets=("$@")
elif [[ -d "$ROOT/docs/reviews/test-evidence" ]]; then
  while IFS= read -r -d '' file; do
    targets+=("$file")
  done < <(find "$ROOT/docs/reviews/test-evidence" -type f -name '*.log' -print0)
fi

if [[ "$#" -eq 0 && -d "$ROOT/docs/app-operator" ]]; then
  while IFS= read -r -d '' file; do
    targets+=("$file")
  done < <(find "$ROOT/docs/app-operator" -type f -print0)
fi

if [[ "$#" -eq 0 && -f "$ROOT/.github/workflows/ci.yml" ]]; then
  if ! ruby "$TOOL_ROOT/scripts/quality/validate-evidence-workflow.rb" \
    "$ROOT/.github/workflows/ci.yml" >/dev/null; then
    echo "错误：CI 测试证据 Artifact 策略无效。" >&2
    fail=1
  fi
fi

if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "[evidence-lint] 当前没有测试证据日志，跳过。"
  exit 0
fi

for file in "${targets[@]}"; do
  if rg -q '^Evidence format: bounded-v1$' "$file"; then
    if ! ruby "$TOOL_ROOT/scripts/quality/validate-bounded-evidence.rb" "$file" >/dev/null; then
      echo "错误：有界测试证据结构或上限无效：$file" >&2
      fail=1
    fi
  fi

  users_pattern='/Use''rs/[^/[:space:]]+'
  home_pattern='/ho''me/[^/[:space:]]+'
  windows_pattern='[A-Za-z]:\\Use''rs\\[^\\[:space:]]+'
  path_hits="$(rg -n "(${users_pattern}|${home_pattern}|${windows_pattern})" "$file" || true)"
  if [[ -n "$path_hits" ]]; then
    echo "错误：测试证据包含未脱敏的用户目录：$file" >&2
    fail=1
  fi

  xcode_destination_hits="$(rg -n '^[[:space:]]*\{[^}]*platform:[^}]*(id:[^<,}]|name:[^<,}])' "$file" || true)"
  if [[ -n "$xcode_destination_hits" ]]; then
    echo "错误：测试证据包含未脱敏的 Xcode 设备标识：$file" >&2
    fail=1
  fi

  temporary_path_hits="$(rg -n '/var/folders/[^[:space:]]+' "$file" || true)"
  if [[ -n "$temporary_path_hits" ]]; then
    echo "错误：测试证据包含未脱敏的本机临时路径：$file" >&2
    fail=1
  fi

  secret_hits="$(rg -n -i '(authorization[[:space:]]*:[[:space:]]*bearer[[:space:]]+[^<[:space:]]|(?:access[_-]?token|refresh[_-]?token|api[_-]?key|password|secret|token)[[:space:]]*[:=][[:space:]]*[^<[:space:],;]|BEGIN [^-]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,})' "$file" || true)"
  if [[ -n "$secret_hits" ]]; then
    echo "错误：测试证据包含未脱敏的凭据形态：$file" >&2
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "[evidence-lint] 测试证据脱敏检查通过。"
