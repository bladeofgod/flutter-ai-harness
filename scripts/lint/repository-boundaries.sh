#!/usr/bin/env bash
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${REPOSITORY_ROOT:-$TOOL_ROOT}"
FEATURE_ROOT="$ROOT/app/packages/app_features/lib"
fail=0

echo "[lint] 检查跨 Feature 内部引用"
if [[ -d "$FEATURE_ROOT" ]]; then
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"
    owner="$(sed -nE 's#^.*/(feature_[^/]+)/.*#\1#p' <<< "$file")"
    target="$(rg -o 'feature_[A-Za-z0-9_]+/' <<< "${hit#*:*:}" | tail -n 1 | tr -d '/')"
    if [[ -z "$owner" || "$owner" != "$target" ]]; then
      echo "错误：$owner 不得 import $target 内部实现：$hit"
      fail=1
    fi
  done < <(rg -n "^[[:space:]]*(import|export|part)[[:space:]]+['\"][^'\"]*feature_[A-Za-z0-9_]+/" \
    "$FEATURE_ROOT" -g '*.dart' 2>/dev/null || true)
fi

echo "[lint] 检查 Widget/Page 直接持有或调用 API"
api_hits="$(rg -n -U 'Get\.find[[:space:]]*<[A-Za-z0-9_]+Api>[[:space:]]*\([^)]*\)[[:space:]]*(\.|;)' "$FEATURE_ROOT" \
  -g '**/pages/**/*.dart' -g '**/widgets/**/*.dart' 2>/dev/null || true)"
if [[ -n "$api_hits" ]]; then
  echo "错误：Widget/Page 必须通过 Controller Facade 使用 API："
  echo "$api_hits"
  fail=1
fi

echo "[lint] 检查 Controller 是否通过服务定位器获取 API"
controller_api_hits="$(rg -n -U 'Get\.find[[:space:]]*<[A-Za-z0-9_]+Api>[[:space:]]*\(' "$FEATURE_ROOT" \
  -g '**/controllers/**/*.dart' 2>/dev/null || true)"
if [[ -n "$controller_api_hits" ]]; then
  echo "错误：Controller 必须通过构造函数接收 API："
  echo "$controller_api_hits"
  fail=1
fi

echo "[lint] 检查壳工程是否引用 Feature 内部实现"
shell_feature_hits="$(rg -n "^[[:space:]]*(import|export|part)[[:space:]]+['\"][^'\"]*(package:app_features/(feature_|src/)|app_features/(lib/)?feature_)" \
  "$ROOT/app/apps" -g '*.dart' 2>/dev/null || true)"
if [[ -n "$shell_feature_hits" ]]; then
  echo "错误：壳工程只能引用 app_features 的公开入口："
  echo "$shell_feature_hits"
  fail=1
fi

echo "[lint] 检查 GetX 路由与 Overlay 越界"
getx_ui_hits="$(rg -n 'GetMaterialApp|Get\.(to|off|offAll|back|snackbar|dialog|bottomSheet)' \
  "$ROOT/app" -g '*.dart' 2>/dev/null || true)"
if [[ -n "$getx_ui_hits" ]]; then
  echo "错误：路由使用 go_router，Overlay 使用 Flutter/Context API："
  echo "$getx_ui_hits"
  fail=1
fi

echo "[lint] 检查生成类型是否泄漏到公共 API"
public_targets=()
shopt -s nullglob
for target in \
  "$ROOT"/app/packages/*/lib/*.dart \
  "$FEATURE_ROOT/api" \
  "$FEATURE_ROOT"/feature_*/controllers; do
  [[ -e "$target" ]] && public_targets+=("$target")
done
shopt -u nullglob

proto_hits=""
if [[ "${#public_targets[@]}" -gt 0 ]]; then
  proto_hits="$(rg -n "^[[:space:]]*(import|export)[[:space:]]+['\"][^'\"]*generated/" \
    "${public_targets[@]}" -g '*.dart' 2>/dev/null || true)"
fi
if [[ -n "$proto_hits" ]]; then
  echo "错误：公共 API 和 Controller 不得 import 生成协议类型："
  echo "$proto_hits"
  fail=1
fi

echo "[lint] 检查 Workspace Package 依赖方向"
if [[ -n "${PACKAGE_DEPS_JSON:-}" ]]; then
  if ! bash "$TOOL_ROOT/scripts/dart-tool.sh" run tool/check_package_dependencies.dart \
    --input "$PACKAGE_DEPS_JSON"; then
    fail=1
  fi
else
  if ! bash "$TOOL_ROOT/scripts/dart-tool.sh" run tool/check_package_dependencies.dart; then
    fail=1
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "[lint] 仓库边界检查通过。"
