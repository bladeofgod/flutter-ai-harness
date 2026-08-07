#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-evidence-test.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

evidence="$FIXTURE_ROOT/evidence.log"
artifact="$FIXTURE_ROOT/full.log"
private_unix="/Use""rs/alice/project"
private_windows='C:\Use''rs\bob\project'
multiline_argument=$'line-one   \nline-two\r\tend'
xcode_device='{ platform:iOS, arch:arm64, id:fixture-device-id, name:Fixture iPhone, error:iOS is not installed. }'
xcode_mac='{ platform:macOS, arch:arm64, id:fixture-host-id, name:Fixture Mac }'
result_bundle='/var/folders/fixture/session/T/ResultBundle.xcresult'
bash "$ROOT/scripts/quality/capture-evidence.sh" --artifact "$artifact" "$evidence" -- \
  bash -c 'printf "%s\n" "path=$1" "windows=$2" "Authorization: Bearer fixture-bearer" "token=fixture-token" "api_key=fixture-api-key" "ghp_12345678901234567890" "-----BEGIN PRIVATE KEY-----" "fixture-private-key" "-----END PRIVATE KEY-----" "$3" "$4" "$5" "kept-output"' \
  fixture "$private_unix" "$private_windows" "$xcode_device" "$xcode_mac" \
  "$result_bundle" 'value   ' "$multiline_argument"

rg -q 'kept-output' "$evidence"
rg -q '<home>/project' "$evidence"
rg -q 'token=<redacted>' "$evidence"
rg -q 'Authorization: Bearer <redacted>' "$evidence"
rg -q '<redacted-private-key>' "$evidence"
rg -q 'id:<redacted-device-id>' "$evidence"
rg -q 'name:<redacted-device-name>' "$evidence"
rg -q '<temporary-path>' "$evidence"
rg -Fq "'value   '" "$evidence"
rg -Fq "\$'line-one   \\nline-two\\r\\tend'" "$evidence"
if rg -q 'alice|bob|fixture-bearer|fixture-token|fixture-api-key|fixture-private-key|ghp_|fixture-device-id|fixture-host-id|Fixture iPhone|Fixture Mac|/var/folders/' "$evidence"; then
  echo "错误：证据采集器未脱敏 Fixture。" >&2
  exit 1
fi
rg -q '^Evidence format: bounded-v1$' "$evidence"
rg -q '^Evidence artifact format: redacted-full-v1$' "$artifact"
rg -q 'kept-output' "$artifact"
rg -q '^Output SHA-256: [0-9a-f]{64}$' "$evidence"
rg -q '^Original output bytes: [0-9]+$' "$evidence"
rg -q '^Original output lines: [0-9]+$' "$evidence"
rg -q '^Truncated: no$' "$evidence"

bash "$ROOT/scripts/quality/capture-evidence.sh" --append "$evidence" -- \
  bash -c 'printf "progress   \rcomplete   \nsecond-command\n"'
if [[ "$(rg -c '^## Command$' "$evidence")" -ne 2 ]]; then
  echo "错误：证据追加模式未保留两条命令。" >&2
  exit 1
fi
if ! rg -q '^progress$' "$evidence" || ! rg -q '^complete$' "$evidence" ||
  LC_ALL=C rg -U $'\r|[ \t]+$' "$evidence" >/dev/null; then
  echo "错误：证据采集器未规范化终端回车或行尾空格。" >&2
  exit 1
fi

if bash "$ROOT/scripts/quality/capture-evidence.sh" "$FIXTURE_ROOT/failure.log" -- \
  bash -c 'exit 7'; then
  echo "错误：证据采集器未透传失败退出码。" >&2
  exit 1
fi
rg -q 'Exit code: 7' "$FIXTURE_ROOT/failure.log"

huge="$FIXTURE_ROOT/huge.log"
huge_artifact="$FIXTURE_ROOT/huge-full.log"
bash "$ROOT/scripts/quality/capture-evidence.sh" --artifact "$huge_artifact" "$huge" -- \
  bash -c 'for index in $(seq 1 3000); do printf "progress-%04d\n" "$index"; done; echo "All tests passed"'
[[ "$(wc -c < "$huge" | tr -d '[:space:]')" -le 65536 ]]
[[ "$(wc -l < "$huge" | tr -d '[:space:]')" -le 600 ]]
rg -q '^Truncated: yes$' "$huge"
rg -q 'use the redacted CI artifact for full output' "$huge"
rg -q 'All tests passed' "$huge"
rg -q 'progress-3000' "$huge_artifact"

for position in head tail; do
  failure="$FIXTURE_ROOT/failure-$position.log"
  if [[ "$position" == head ]]; then
    command_body='echo "fatal: first-root-head"; for index in $(seq 1 400); do echo "noise-$index"; done; exit 9'
  else
    command_body='for index in $(seq 1 400); do echo "noise-$index"; done; echo "error: first-root-tail"; exit 9'
  fi
  if bash "$ROOT/scripts/quality/capture-evidence.sh" "$failure" -- bash -c "$command_body"; then
    echo "错误：巨大失败 Fixture 未透传退出码。" >&2
    exit 1
  fi
  rg -q "first-root-$position" "$failure"
  rg -q '^Selection: failure-root-context-v1$' "$failure"
done

cp "$huge" "$FIXTURE_ROOT/tampered.log"
sed -i.bak 's/^Summary output bytes: [0-9][0-9]*/Summary output bytes: 1/' \
  "$FIXTURE_ROOT/tampered.log"
rm -f -- "$FIXTURE_ROOT/tampered.log.bak"
if bash "$ROOT/scripts/quality/evidence-lint.sh" "$FIXTURE_ROOT/tampered.log" >/dev/null 2>&1; then
  echo "错误：evidence lint 未拒绝被篡改的 summary metadata。" >&2
  exit 1
fi

printf '%s\n' "${private_unix%/project}/raw" "${private_windows%\\project}\\raw" \
  'Authorization: Bearer not-redacted' 'password=not-redacted' \
  > "$FIXTURE_ROOT/unsafe.log"
if bash "$ROOT/scripts/quality/evidence-lint.sh" "$FIXTURE_ROOT/unsafe.log" >/dev/null 2>&1; then
  echo "错误：evidence lint 未拒绝原始路径和凭据。" >&2
  exit 1
fi

printf '%s\n' "$xcode_device" "$xcode_mac" "$result_bundle" \
  > "$FIXTURE_ROOT/unsafe-xcode.log"
if bash "$ROOT/scripts/quality/evidence-lint.sh" "$FIXTURE_ROOT/unsafe-xcode.log" >/dev/null 2>&1; then
  echo "错误：evidence lint 未拒绝 Xcode 设备标识和本机临时路径。" >&2
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

ruby "$ROOT/scripts/quality/validate-evidence-workflow.rb" "$ROOT/.github/workflows/ci.yml"
for mutation in always retention action missing; do
  workflow="$FIXTURE_ROOT/ci-$mutation.yml"
  cp "$ROOT/.github/workflows/ci.yml" "$workflow"
  case "$mutation" in
    always) sed -i.bak 's/if: always()/if: success()/g' "$workflow" ;;
    retention) sed -i.bak 's/retention-days: 14/retention-days: 30/g' "$workflow" ;;
    action) sed -i.bak 's#actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02#actions/upload-artifact@v4#g' "$workflow" ;;
    missing) sed -i.bak 's/if-no-files-found: error/if-no-files-found: ignore/g' "$workflow" ;;
  esac
  rm -f -- "$workflow.bak"
  if ruby "$ROOT/scripts/quality/validate-evidence-workflow.rb" "$workflow" >/dev/null 2>&1; then
    echo "错误：CI evidence policy 未拒绝 $mutation 漂移。" >&2
    exit 1
  fi
done

echo "[evidence-test] 证据采集、脱敏和门禁 Fixture 通过。"
