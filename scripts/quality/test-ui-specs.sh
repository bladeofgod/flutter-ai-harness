#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-spec.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

SPEC_DIR="$FIXTURE_ROOT/docs/app-operator/specs"
SPEC_ID="profile-save"
IMPLEMENTATION="app/apps/demo/lib/profile_page.dart"
PRODUCT_SOURCE="docs/product/profile.md"
TASK_SOURCE="profile-flow"
mkdir -p \
  "$SPEC_DIR" \
  "$FIXTURE_ROOT/docs/tasks" \
  "$(dirname "$FIXTURE_ROOT/$PRODUCT_SOURCE")" \
  "$(dirname "$FIXTURE_ROOT/$IMPLEMENTATION")"
printf '%s\n' '# Profile behavior' > "$FIXTURE_ROOT/$PRODUCT_SOURCE"
printf '%s\n' '# Profile flow task' > \
  "$FIXTURE_ROOT/docs/tasks/$TASK_SOURCE.md"
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
  cat > "$SPEC_DIR/$SPEC_ID.spec.yaml" <<'YAML'
version: 1
revision: 1
id: profile-save
status: ready
title: Save profile
sources:
  - type: product
    ref: docs/product/profile.md
  - type: task
    ref: profile-flow
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
  cat > "$SPEC_DIR/$SPEC_ID.audit.yaml" <<YAML
version: 1
spec: docs/app-operator/specs/profile-save.spec.yaml
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
  cat > "$report_dir/$platform.run.yaml" <<YAML
version: 1
spec: docs/app-operator/specs/profile-save.spec.yaml
audit: docs/app-operator/specs/profile-save.audit.yaml
specId: profile-save
specRevision: 1
implementationDigest: $digest
platform: $platform
status: passed
environment:
  osVersion: $os_version
  deviceKind: $device_kind
  buildMode: debug
  flutterVersion: 3.41.9
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
  "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝缺少 Assertion 的 ready Spec。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak 's/action: tap/action: coordinate_tap/' \
  "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝不支持的 Action。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak '/platforms:/a\
setup: []' "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝已移除的 Setup 字段。" >&2
  exit 1
fi
write_ready_spec

mkdir -p "$FIXTURE_ROOT/docs/tasks/done"
mv "$FIXTURE_ROOT/docs/tasks/$TASK_SOURCE.md" \
  "$FIXTURE_ROOT/docs/tasks/done/$TASK_SOURCE.md"
run_check >/dev/null

sed -i.bak 's/ref: profile-flow/ref: missing-flow/' \
  "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝不存在的任务 slug Source。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak \
  's#docs/product/profile.md#docs/product/missing.md#' \
  "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝失效的产品 Source。" >&2
  exit 1
fi
write_ready_spec

sed -i.bak '/status: ready/a\
task: profile-save' "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝已移除的 task 字段。" >&2
  exit 1
fi
write_ready_spec

mkdir -p "$FIXTURE_ROOT/docs/tasks"
cp "$SPEC_DIR/$SPEC_ID.spec.yaml" \
  "$FIXTURE_ROOT/docs/tasks/$SPEC_ID.spec.yaml"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝任务目录中的 Spec。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/$SPEC_ID.spec.yaml"
run_check >/dev/null

sed -i.bak 's/status: ready/status: draft/' \
  "$SPEC_DIR/$SPEC_ID.spec.yaml"
sed -i.bak 's/openQuestions: \[\]/openQuestions: [Need product decision]/' \
  "$SPEC_DIR/$SPEC_ID.spec.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.spec.yaml.bak"
run_check >/dev/null

write_ready_spec
write_passed_audit
run_check >/dev/null

sed -i.bak 's/specRevision: 1/specRevision: 2/' \
  "$SPEC_DIR/$SPEC_ID.audit.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝过期的静态审计。" >&2
  exit 1
fi
write_passed_audit

sed -i.bak "s#$IMPLEMENTATION:6#app/does-not-exist.dart:999#" \
  "$SPEC_DIR/$SPEC_ID.audit.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝不存在的静态审计证据。" >&2
  exit 1
fi
write_passed_audit

sed -i.bak "s#$IMPLEMENTATION:6#$IMPLEMENTATION:999#" \
  "$SPEC_DIR/$SPEC_ID.audit.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝越界行号证据。" >&2
  exit 1
fi
write_passed_audit

mkdir -p "$FIXTURE_ROOT/app/apps/demo/test"
cp "$FIXTURE_ROOT/$IMPLEMENTATION" \
  "$FIXTURE_ROOT/app/apps/demo/test/profile_page_test.dart"
sed -i.bak "s#$IMPLEMENTATION:6#app/apps/demo/test/profile_page_test.dart:6#" \
  "$SPEC_DIR/$SPEC_ID.audit.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.audit.yaml.bak"
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
  "$SPEC_DIR/$SPEC_ID.audit.yaml"
rm -f -- "$SPEC_DIR/$SPEC_ID.audit.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝包含 missing 的 passed 审计。" >&2
  exit 1
fi
write_passed_audit
run_check >/dev/null

write_passed_report android
write_passed_report ios
run_check >/dev/null

rm -f -- "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/ios.run.yaml"
run_check >/dev/null
write_passed_report ios

cp "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/android.run.yaml" \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120000-android.run.yaml"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝带时间戳的历史运行报告。" >&2
  exit 1
fi
rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/20260720-120000-android.run.yaml"

sed -i.bak 's/deviceKind: emulator/deviceKind: simulator/' \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/android.run.yaml"
rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/android.run.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝与平台不匹配的运行环境。" >&2
  exit 1
fi
write_passed_report android

sed -i.bak 's/implementationDigest: ./implementationDigest: 0/' \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/android.run.yaml"
rm -f -- \
  "$FIXTURE_ROOT/docs/app-operator/runs/profile-save/android.run.yaml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Spec Check 未拒绝与 Audit 不一致的运行报告。" >&2
  exit 1
fi
write_passed_report android
run_check >/dev/null

echo "[spec-test] UI 行为 Spec、静态审计与失败 Fixture 通过。"
