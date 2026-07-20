#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-spec.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

TASK_DIR="$FIXTURE_ROOT/docs/tasks/sprint-2"
mkdir -p "$TASK_DIR"
printf '%s\n' '# S2-001 Profile' > "$TASK_DIR/S2-001-profile.md"

run_check() {
  bash "$ROOT/scripts/dart-tool.sh" run tool/validate_ui_specs.dart \
    --root "$FIXTURE_ROOT"
}

write_ready_spec() {
  cat > "$TASK_DIR/S2-001-profile.spec.yaml" <<'YAML'
version: 1
id: profile-save
status: ready
task: S2-001
title: Save profile
sources:
  - type: task
    ref: docs/tasks/sprint-2/S2-001-profile.md
platforms: [android, ios]
setup:
  - id: profile-open
    description: Profile is open
steps:
  - id: save
    action: tap
    target:
      by: key
      value: profile_save
assertions:
  - id: success-visible
    condition: visible
    target:
      by: text
      value: Saved
teardown: []
openQuestions: []
YAML
}

write_ready_spec
run_check >/dev/null

sed -i.bak 's/assertions:/assertions: []\nignored:/' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝缺少 Assertion 的 ready Spec。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak 's/action: tap/action: coordinate_tap/' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝不支持的 Action。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak 's/status: ready/status: draft/' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
sed -i.bak 's/openQuestions: \[\]/openQuestions: [Need product decision]/' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.spec.yaml.bak"
run_check >/dev/null

echo "[spec-test] UI 行为 Spec Schema 与失败 Fixture 通过。"
