#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-integration.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$FIXTURE_ROOT/app/apps/demo/integration_test" \
  "$FIXTURE_ROOT/app/packages"

FAKE_LOG="$FIXTURE_ROOT/flutter-tool.log"
export FAKE_LOG
cat > "$FIXTURE_ROOT/flutter-tool.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "${TOOL_WORKDIR:?}" "$*" >> "${FAKE_LOG:?}"
BASH

REPOSITORY_ROOT="$FIXTURE_ROOT" \
  FLUTTER_TOOL_SCRIPT="$FIXTURE_ROOT/flutter-tool.sh" \
  bash "$ROOT/scripts/quality/run-integration-tests.sh" >/dev/null

printf '%s\n' 'void main() {}' \
  > "$FIXTURE_ROOT/app/apps/demo/integration_test/smoke_test.dart"
if REPOSITORY_ROOT="$FIXTURE_ROOT" \
  FLUTTER_TOOL_SCRIPT="$FIXTURE_ROOT/flutter-tool.sh" \
  bash "$ROOT/scripts/quality/run-integration-tests.sh" >/dev/null 2>&1; then
  echo "错误：Integration Runner 未拒绝缺少设备 ID 的执行。" >&2
  exit 1
fi

REPOSITORY_ROOT="$FIXTURE_ROOT" \
  FLUTTER_TOOL_SCRIPT="$FIXTURE_ROOT/flutter-tool.sh" \
  INTEGRATION_DEVICE="fixture-device" \
  bash "$ROOT/scripts/quality/run-integration-tests.sh" >/dev/null

expected="$FIXTURE_ROOT/app/apps/demo|test integration_test -d fixture-device"
if ! rg -Fxq "$expected" "$FAKE_LOG"; then
  echo "错误：Integration Runner 未把 Package 和设备传给 Flutter Tool。" >&2
  exit 1
fi

echo "[integration-runner-test] Integration Test Runner Fixture 通过。"
