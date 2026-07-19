#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
targets=()

if [[ "$#" -gt 0 ]]; then
  targets=("$@")
elif [[ -d "$ROOT/docs/reviews/test-evidence" ]]; then
  while IFS= read -r -d '' file; do
    targets+=("$file")
  done < <(find "$ROOT/docs/reviews/test-evidence" -type f -name '*.log' -print0)
fi

if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "[evidence-lint] 当前没有测试证据日志，跳过。"
  exit 0
fi

for file in "${targets[@]}"; do
  path_hits="$(rg -n '(/Users/[^/[:space:]]+|/home/[^/[:space:]]+|[A-Za-z]:\\Users\\[^\\[:space:]]+)' "$file" || true)"
  if [[ -n "$path_hits" ]]; then
    echo "错误：测试证据包含未脱敏的用户目录：$file" >&2
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
