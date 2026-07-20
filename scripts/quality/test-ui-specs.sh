#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-spec.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

TASK_DIR="$FIXTURE_ROOT/docs/tasks/sprint-2"
IMPLEMENTATION="app/apps/demo/lib/profile_page.dart"
mkdir -p "$TASK_DIR" "$(dirname "$FIXTURE_ROOT/$IMPLEMENTATION")"
printf '%s\n' '# S2-001 Profile' > "$TASK_DIR/S2-001-profile.md"
cat > "$FIXTURE_ROOT/$IMPLEMENTATION" <<'DART'
class ProfilePage {
  void open() {
    render();
  }

  void save() {
    persist();
    showSuccess();
  }

  void render() {}

  void persist() {}

  void showSuccess() {}
}
DART

run_check() {
  bash "$ROOT/scripts/dart-tool.sh" run tool/validate_ui_specs.dart \
    --root "$FIXTURE_ROOT"
}

implementation_digest() {
  bash "$ROOT/scripts/dart-tool.sh" run tool/implementation_digest.dart \
    --root "$FIXTURE_ROOT" "$IMPLEMENTATION"
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
  local digest
  digest="$(implementation_digest)"
  cat > "$TASK_DIR/S2-001-profile.audit.yaml" <<YAML
version: 1
spec: docs/tasks/sprint-2/S2-001-profile.spec.yaml
specId: profile-save
specRevision: 1
status: passed
implementationDigest: $digest
items:
  - id: save
    status: covered
    evidence: [$IMPLEMENTATION:6]
  - id: success-visible
    status: covered
    evidence: [$IMPLEMENTATION:8]
YAML
}

write_passed_report() {
  local platform="$1"
  local timestamp="$2"
  local device_kind="emulator"
  local os_version="Android 15"
  if [[ "$platform" == "ios" ]]; then
    device_kind="simulator"
    os_version="iOS 18.5"
  fi
  local digest
  digest="$(implementation_digest)"
  local report_dir="$FIXTURE_ROOT/docs/app-operator/runs/profile-save"
  mkdir -p "$report_dir"
  cat > "$report_dir/$timestamp-$platform.run.yaml" <<YAML
version: 1
spec: docs/tasks/sprint-2/S2-001-profile.spec.yaml
audit: docs/tasks/sprint-2/S2-001-profile.audit.yaml
specId: profile-save
specRevision: 1
implementationDigest: $digest
platform: $platform
status: passed
environment:
  osVersion: $os_version
  deviceKind: $device_kind
  buildMode: debug
  flutterVersion: 3.35.7
  marionetteVersion: 0.6.0
items:
  - id: save
    status: passed
    evidence: []
  - id: success-visible
    status: passed
    evidence: []
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

sed -i.bak "s#$IMPLEMENTATION:6#app/does-not-exist.dart:999#" \
  "$TASK_DIR/S2-001-profile.audit.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝不存在的静态审计证据。" >&2
  exit 1
fi
write_passed_audit

sed -i.bak "s#$IMPLEMENTATION:6#$IMPLEMENTATION:999#" \
  "$TASK_DIR/S2-001-profile.audit.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝越界行号证据。" >&2
  exit 1
fi
write_passed_audit

mkdir -p "$FIXTURE_ROOT/app/apps/demo/test"
cp "$FIXTURE_ROOT/$IMPLEMENTATION" \
  "$FIXTURE_ROOT/app/apps/demo/test/profile_page_test.dart"
sed -i.bak "s#$IMPLEMENTATION:6#app/apps/demo/test/profile_page_test.dart:6#" \
  "$TASK_DIR/S2-001-profile.audit.yaml"
rm -f -- "$TASK_DIR/S2-001-profile.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝测试文件作为实现证据。" >&2
  exit 1
fi
write_passed_audit

printf '%s\n' '// implementation changed' >> "$FIXTURE_ROOT/$IMPLEMENTATION"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝实现变化后的过期审计。" >&2
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

write_passed_report android 20260720-120000
write_passed_report ios 20260720-120100
run_check >/dev/null

sed -i.bak 's/deviceKind: emulator/deviceKind: simulator/' \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120000-android.run.yaml"
rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120000-android.run.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝与平台不匹配的运行环境。" >&2
  exit 1
fi
write_passed_report android 20260720-120000

sed -i.bak 's/implementationDigest: ./implementationDigest: 0/' \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120000-android.run.yaml"
rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120000-android.run.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝与 Audit 不一致的运行报告。" >&2
  exit 1
fi
write_passed_report android 20260720-120000
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
  "$DONE_DIR/S2-001-profile.audit.yaml" \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/"*.run.yaml
rm -f -- \
  "$DONE_DIR/S2-001-profile.spec.yaml.bak" \
  "$DONE_DIR/S2-001-profile.audit.yaml.bak" \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/"*.run.yaml.bak
run_check >/dev/null

rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120100-ios.run.yaml"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝缺少声明平台报告的归档 Spec。" >&2
  exit 1
fi
write_passed_report ios 20260720-120100
sed -i.bak 's#docs/tasks/sprint-2/#docs/tasks/done/#g' \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120100-ios.run.yaml"
rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120100-ios.run.yaml.bak"
run_check >/dev/null

rm -f -- "$DONE_DIR/S2-001-profile.audit.yaml"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝缺少 passed 审计的归档 Spec。" >&2
  exit 1
fi

echo "[spec-test] UI 行为 Spec、静态审计与失败 Fixture 通过。"
