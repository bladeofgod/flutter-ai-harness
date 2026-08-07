#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
append=0
artifact=''
artifact_record=''

while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --append)
      append=1
      shift
      ;;
    --artifact)
      [[ "$#" -ge 2 ]] || { echo "错误：--artifact 缺少路径。" >&2; exit 64; }
      artifact="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

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
sanitized_output="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-sanitized-output.XXXXXX")"
record="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-record.XXXXXX")"
sanitized_command="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-command.XXXXXX")"
versions_raw="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-versions.XXXXXX")"
versions_sanitized="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-versions-sanitized.XXXXXX")"
summary_body="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-summary.XXXXXX")"
cleanup() {
  rm -f -- "$raw_output" "$sanitized_output" "$record" "$sanitized_command" \
    "$versions_raw" "$versions_sanitized" "$summary_body"
  if [[ -n "$artifact_record" ]]; then
    rm -f -- "$artifact_record"
  fi
}
trap cleanup EXIT

set +e
"$@" > "$raw_output" 2>&1
status=$?
set -e

EVIDENCE_REPO_ROOT="$ROOT" \
  bash "$ROOT/scripts/dart-tool.sh" run tool/redact_evidence.dart \
  --command "$sanitized_command" "$@"
EVIDENCE_REPO_ROOT="$ROOT" \
  bash "$ROOT/scripts/dart-tool.sh" run tool/redact_evidence.dart \
  "$raw_output" "$sanitized_output"

{
  bash --version | sed -n '1p'
  command -v make >/dev/null 2>&1 && make --version | sed -n '1p'
  command -v dart >/dev/null 2>&1 && dart --version 2>&1
  command -v flutter >/dev/null 2>&1 && flutter --version 2>&1 | sed -n '1p'
  command -v java >/dev/null 2>&1 && java -version 2>&1 | sed -n '1p'
  command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version
} > "$versions_raw"
EVIDENCE_REPO_ROOT="$ROOT" \
  bash "$ROOT/scripts/dart-tool.sh" run tool/redact_evidence.dart \
  "$versions_raw" "$versions_sanitized"
ruby "$ROOT/scripts/quality/summarize-evidence.rb" \
  "$sanitized_output" "$status" > "$summary_body"

{
  echo "Evidence format: bounded-v1"
  echo
  echo "## Command"
  echo
  printf '```text\n'
  cat "$sanitized_command"
  printf '```\n\n'
  echo "## Tool Versions"
  echo
  printf '```text\n'
  cat "$versions_sanitized"
  printf '```\n\n'
  echo "## Result"
  echo
  echo "Exit code: $status"
  echo
  cat "$summary_body"
} > "$record"

mkdir -p "$(dirname "$output")"
if [[ "$append" -eq 1 && -f "$output" ]]; then
  printf '\n' >> "$output"
  cat "$record" >> "$output"
else
  cp "$record" "$output"
fi

if [[ -n "$artifact" ]]; then
  mkdir -p "$(dirname "$artifact")"
  artifact_record="$(mktemp "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-artifact.XXXXXX")"
  {
    echo "Evidence artifact format: redacted-full-v1"
    echo
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
    cat "$sanitized_output"
    printf '\n```\n'
  } > "$artifact_record"
  if [[ "$append" -eq 1 && -f "$artifact" ]]; then
    printf '\n' >> "$artifact"
    cat "$artifact_record" >> "$artifact"
  else
    cp "$artifact_record" "$artifact"
  fi
  rm -f -- "$artifact_record"
  artifact_record=''
  bash "$ROOT/scripts/quality/evidence-lint.sh" "$artifact"
fi

bash "$ROOT/scripts/quality/evidence-lint.sh" "$output"
exit "$status"
