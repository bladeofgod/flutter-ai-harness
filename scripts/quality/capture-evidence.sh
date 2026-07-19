#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
append=0

if [[ "${1:-}" == "--append" ]]; then
  append=1
  shift
fi

if [[ "$#" -lt 3 ]]; then
  echo "Usage: $0 [--append] <output.log> -- <command> [args...]" >&2
  exit 64
fi

output="$1"
shift
if [[ "$1" != "--" ]]; then
  echo "错误：证据输出路径后必须使用 -- 分隔命令。" >&2
  exit 64
fi
shift

if [[ "$#" -eq 0 ]]; then
  echo "错误：缺少需要执行的命令。" >&2
  exit 64
fi

raw_output="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-output.XXXXXX")"
raw_record="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-record.XXXXXX")"
sanitized="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-sanitized.XXXXXX")"
sanitized_command="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-command.XXXXXX")"
cleanup() {
  rm -f -- "$raw_output" "$raw_record" "$sanitized" "$sanitized_command"
}
trap cleanup EXIT

set +e
"$@" > "$raw_output" 2>&1
status=$?
set -e

EVIDENCE_REPO_ROOT="$ROOT" \
  bash "$ROOT/scripts/dart-tool.sh" run tool/redact_evidence.dart \
  --command "$sanitized_command" "$@"

{
  echo "## Command"
  echo
  printf '```text\n'
  cat "$sanitized_command"
  printf '```\n\n'
  echo "Exit code: $status"
  echo
  echo "## Output"
  echo
  printf '```text\n'
  cat "$raw_output"
  printf '\n```\n'
} > "$raw_record"

EVIDENCE_REPO_ROOT="$ROOT" \
  bash "$ROOT/scripts/dart-tool.sh" run tool/redact_evidence.dart \
  "$raw_record" "$sanitized"

mkdir -p "$(dirname "$output")"
if [[ "$append" -eq 1 && -f "$output" ]]; then
  printf '\n' >> "$output"
  cat "$sanitized" >> "$output"
else
  cp "$sanitized" "$output"
fi

bash "$ROOT/scripts/quality/evidence-lint.sh" "$output"
exit "$status"
