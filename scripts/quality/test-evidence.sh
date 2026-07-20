#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-test.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

evidence="$FIXTURE_ROOT/evidence.log"
private_unix="/Use""rs/alice/project"
private_windows='C:\Use''rs\bob\project'
bash "$ROOT/scripts/quality/capture-evidence.sh" "$evidence" -- \
  bash -c 'printf "%s\n" "path=$1" "windows=$2" "Authorization: Bearer fixture-bearer" "token=fixture-token" "api_key=fixture-api-key" "ghp_12345678901234567890" "-----BEGIN PRIVATE KEY-----" "fixture-private-key" "-----END PRIVATE KEY-----" "kept-output"' \
  fixture "$private_unix" "$private_windows"

rg -q 'kept-output' "$evidence"
rg -q '<home>/project' "$evidence"
rg -q 'token=<redacted>' "$evidence"
rg -q 'Authorization: Bearer <redacted>' "$evidence"
rg -q '<redacted-private-key>' "$evidence"
if rg -q 'alice|bob|fixture-bearer|fixture-token|fixture-api-key|fixture-private-key|ghp_' "$evidence"; then
  echo "错误：证据采集器未脱敏 Fixture。" >&2
  exit 1
fi

bash "$ROOT/scripts/quality/capture-evidence.sh" --append "$evidence" -- \
  bash -c 'printf "%s\n" "second-command"'
if [[ "$(rg -c '^## Command$' "$evidence")" -ne 2 ]]; then
  echo "错误：证据追加模式未保留两条命令。" >&2
  exit 1
fi

if bash "$ROOT/scripts/quality/capture-evidence.sh" "$FIXTURE_ROOT/failure.log" -- \
  bash -c 'exit 7'; then
  echo "错误：证据采集器未透传失败退出码。" >&2
  exit 1
fi
rg -q 'Exit code: 7' "$FIXTURE_ROOT/failure.log"

printf '%s\n' "${private_unix%/project}/raw" "${private_windows%\\project}\\raw" \
  'Authorization: Bearer not-redacted' 'password=not-redacted' \
  > "$FIXTURE_ROOT/unsafe.log"
if bash "$ROOT/scripts/quality/evidence-lint.sh" "$FIXTURE_ROOT/unsafe.log" >/dev/null 2>&1; then
  echo "错误：evidence lint 未拒绝原始路径和凭据。" >&2
  exit 1
fi

operator_report="$FIXTURE_ROOT/docs/app-operator/runs/example/android.run.yaml"
mkdir -p "$(dirname "$operator_report")"
printf '%s\n' 'version: 1' 'token=not-redacted' > "$operator_report"
if REPOSITORY_ROOT="$FIXTURE_ROOT" \
  bash "$ROOT/scripts/quality/evidence-lint.sh" >/dev/null 2>&1; then
  echo "错误：evidence lint 未扫描 App Operator 产物。" >&2
  exit 1
fi

echo "[evidence-test] 证据采集、脱敏和门禁 Fixture 通过。"
