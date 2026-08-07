#!/usr/bin/env bash

safe_delete_hook_fixture_root() {
  if [[ "$#" -ne 3 ]]; then
    echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
    return 1
  fi

  local fixture_root="$1"
  local expected_real_root="$2"
  local expected_real_parent="$3"

  if [[ -z "$fixture_root" || -z "$expected_real_root" || -z "$expected_real_parent" ||
    "$fixture_root" != /* || "$expected_real_root" != /* || "$expected_real_parent" != /* ]]; then
    echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
    return 1
  fi

  if [[ ! -e "$fixture_root" && ! -L "$fixture_root" ]]; then
    return 0
  fi
  if [[ -L "$fixture_root" || ! -d "$fixture_root" ]]; then
    echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
    return 1
  fi

  local actual_real_root
  local actual_real_parent
  local fixture_basename
  actual_real_root="$(cd -- "$fixture_root" && pwd -P)" || {
    echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
    return 1
  }
  actual_real_parent="$(cd -- "$(dirname -- "$fixture_root")" && pwd -P)" || {
    echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
    return 1
  }
  fixture_basename="$(basename -- "$actual_real_root")"

  case "$fixture_basename" in
    flutter-ai-harness-hook.??????) ;;
    *)
      echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
      return 1
      ;;
  esac

  if [[ "$actual_real_root" != "$expected_real_root" ||
    "$actual_real_parent" != "$expected_real_parent" ||
    "$actual_real_root" != "$expected_real_parent/$fixture_basename" ]]; then
    echo "错误：拒绝清理未经验证的 Hook Fixture 临时目录。" >&2
    return 1
  fi

  find -P "$actual_real_root" -depth -delete
}
