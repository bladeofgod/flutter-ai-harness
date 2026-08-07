#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/git-hooks/safe-fixture-cleanup.sh"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-hook-cleanup-test.XXXXXX")"
TEST_ROOT_REAL="$(cd "$TEST_ROOT" && pwd -P)"
cleanup() {
  if [[ -d "$TEST_ROOT_REAL" ]]; then
    find -P "$TEST_ROOT_REAL" -depth -delete
  fi
}
trap cleanup EXIT

assert_rejected() {
  local fixture_root="$1"
  local expected_real_root="$2"
  local expected_real_parent="$3"
  local output
  if output="$(safe_delete_hook_fixture_root \
    "$fixture_root" "$expected_real_root" "$expected_real_parent" 2>&1)"; then
    echo "错误：Fixture 安全清理接受了非法根目录。" >&2
    exit 1
  fi
  if [[ "$output" != "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" ]]; then
    echo "错误：Fixture 安全清理输出了不稳定诊断。" >&2
    exit 1
  fi
}

valid_root="$(mktemp -d "$TEST_ROOT/flutter-ai-harness-hook.XXXXXX")"
valid_real_root="$(cd "$valid_root" && pwd -P)"
mkdir -p "$valid_root/.git/objects/aa" "$TEST_ROOT/external-target"
printf '%s\n' readonly > "$valid_root/.git/objects/aa/object"
chmod 0444 "$valid_root/.git/objects/aa/object"
printf '%s\n' keep > "$TEST_ROOT/external-target/marker"
ln -s "$TEST_ROOT/external-target" "$valid_root/external-link"

safe_delete_hook_fixture_root "$valid_root" "$valid_real_root" "$TEST_ROOT_REAL"
[[ ! -e "$valid_root" ]]
[[ -f "$TEST_ROOT/external-target/marker" ]]
safe_delete_hook_fixture_root "$valid_root" "$valid_real_root" "$TEST_ROOT_REAL"

wrong_prefix="$(mktemp -d "$TEST_ROOT/not-a-hook-fixture.XXXXXX")"
wrong_prefix_real="$(cd "$wrong_prefix" && pwd -P)"
assert_rejected "$wrong_prefix" "$wrong_prefix_real" "$TEST_ROOT_REAL"
[[ -d "$wrong_prefix" ]]

replacement_target="$(mktemp -d "$TEST_ROOT/replacement-target.XXXXXX")"
replacement_link="$TEST_ROOT/flutter-ai-harness-hook.abcdef"
ln -s "$replacement_target" "$replacement_link"
assert_rejected "$replacement_link" "$replacement_target" "$TEST_ROOT_REAL"
[[ -d "$replacement_target" ]]

tampered_root="$(mktemp -d "$TEST_ROOT/flutter-ai-harness-hook.XXXXXX")"
tampered_real_root="$(cd "$tampered_root" && pwd -P)"
assert_rejected "$tampered_root" "$valid_real_root" "$TEST_ROOT_REAL"
[[ -d "$tampered_real_root" ]]

echo "[hook-cleanup-test] Hook Fixture 安全清理通过。"
