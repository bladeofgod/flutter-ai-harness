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
revision: 1
id: profile-save
status: ready
task: S2-001
title: Save profile
sources:
  - type: task
    ref: docs/tasks/sprint-2/S2-001-profile.md
platforms: [android, ios]
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

write_passed_audit() {
  cat > "$TASK_DIR/S2-001-profile.audit.yaml" <<'YAML'
version: 1
spec: docs/tasks/sprint-2/S2-001-profile.spec.yaml
specId: profile-save
specRevision: 1
status: passed
items:
  - id: save
    status: covered
    evidence: [app/example.dart:10]
  - id: success-visible
    status: covered
    evidence: [app/example.dart:20]
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

sed -i.bak '/platforms:/a\
setup: []' "$TASK_DIR/S2-001-profile.spec.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝已移除的 Setup 字段。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak \
  's#docs/tasks/sprint-2/S2-001-profile.md#docs/tasks/done/S2-001-profile.md#' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝失效的任务 Source。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak 's/status: ready/status: draft/' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
sed -i.bak 's/openQuestions: \[\]/openQuestions: [Need product decision]/' \
  "$TASK_DIR/S2-001-profile.spec.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.spec.yaml.bak"
run_check >/dev/null

write_ready_spec
write_passed_audit
run_check >/dev/null

sed -i.bak 's/specRevision: 1/specRevision: 2/' \
  "$TASK_DIR/S2-001-profile.audit.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝过期的静态审计。" >&2
  exit 1
fi
write_passed_audit

sed -i.bak 's/status: covered/status: missing/g' \
  "$TASK_DIR/S2-001-profile.audit.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝包含 missing 的 passed 审计。" >&2
  exit 1
fi
write_passed_audit
run_check >/dev/null

DONE_DIR="$FIXTURE_ROOT/docs/tasks/done"
mkdir -p "$DONE_DIR"
mv "$TASK_DIR/S2-001-profile.md" "$DONE_DIR/S2-001-profile.md"
mv "$TASK_DIR/S2-001-profile.spec.yaml" \
  "$DONE_DIR/S2-001-profile.spec.yaml"
mv "$TASK_DIR/S2-001-profile.audit.yaml" \
  "$DONE_DIR/S2-001-profile.audit.yaml"
sed -i.bak 's#docs/tasks/sprint-2/#docs/tasks/done/#g' \
  "$DONE_DIR/S2-001-profile.spec.yaml" \
  "$DONE_DIR/S2-001-profile.audit.yaml"
rm -f -- \
  "$DONE_DIR/S2-001-profile.spec.yaml.bak" \
  "$DONE_DIR/S2-001-profile.audit.yaml.bak"
run_check >/dev/null

rm -f -- "$DONE_DIR/S2-001-profile.audit.yaml"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝缺少 passed 审计的归档 Spec。" >&2
  exit 1
fi

echo "[spec-test] UI 行为 Spec、静态审计与失败 Fixture 通过。"
