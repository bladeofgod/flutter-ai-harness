#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-lint.XXXXXX")"

cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

FEATURE_ROOT="$FIXTURE_ROOT/app/packages/app_features/lib"
mkdir -p \
  "$FEATURE_ROOT/feature_alpha/pages" \
  "$FEATURE_ROOT/feature_alpha/controllers" \
  "$FEATURE_ROOT/feature_alpha/api" \
  "$FEATURE_ROOT/feature_beta/controllers" \
  "$FIXTURE_ROOT/app/packages/app_data/lib/generated" \
  "$FIXTURE_ROOT/app/packages/app_data/lib/mappers" \
  "$FIXTURE_ROOT/app/packages/app_media" \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" \
  "$FIXTURE_ROOT/app/apps/demo" \
  "$FIXTURE_ROOT/app/apps/demo/lib"

printf '%s\n' 'name: app_media_capture_bridge' \
  > "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/pubspec.yaml"
printf '%s\n' 'name: app_media' \
  > "$FIXTURE_ROOT/app/packages/app_media/pubspec.yaml"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" \
  > "$FIXTURE_ROOT/app/apps/demo/.flutter-plugins-dependencies"

valid_dependencies="$FIXTURE_ROOT/valid-dependencies.json"
cat > "$valid_dependencies" <<'JSON'
{"root":"workspace","packages":[
  {"name":"workspace","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_core","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_ui","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_data","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_im","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_media","kind":"root","source":"root","directDependencies":["app_core","app_ui"],"devDependencies":[]},
  {"name":"app_media_capture_bridge","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_features","kind":"root","source":"root","directDependencies":["app_core","app_data","app_im","app_media","app_media_capture_bridge","app_ui"],"devDependencies":[]},
  {"name":"demo_app","kind":"root","source":"root","directDependencies":["app_core","app_data","app_features","app_im","app_media","app_media_capture_bridge","app_ui"],"devDependencies":[]}
]}
JSON

printf '%s\n' \
  "import 'package:app_features/feature_alpha/controllers/alpha_controller.dart';" \
  'void buildPage() => AlphaController(api: Get.find<ExampleApi>());' \
  > "$FEATURE_ROOT/feature_alpha/pages/allowed.dart"
printf '%s\n' 'class AlphaController { AlphaController({required Object api}); }' \
  > "$FEATURE_ROOT/feature_alpha/controllers/alpha_controller.dart"
printf '%s\n' 'const alphaRoutes = <Object>[];' \
  > "$FEATURE_ROOT/feature_alpha/routes.dart"
printf '%s\n' 'class AlphaApiImpl {}' \
  > "$FEATURE_ROOT/feature_alpha/api/alpha_api_impl.dart"
printf '%s\n' "export 'feature_alpha/routes.dart';" \
  > "$FEATURE_ROOT/app_features.dart"
printf '%s\n' "import 'feature_alpha/api/alpha_api_impl.dart';" \
  > "$FEATURE_ROOT/features_registry.dart"
printf '%s\n' "import '../generated/model.pb.dart';" \
  > "$FIXTURE_ROOT/app/packages/app_data/lib/mappers/model_mapper.dart"
printf '%s\n' 'library;' > "$FIXTURE_ROOT/app/packages/app_data/lib/app_data.dart"
printf '%s\n' "import 'package:app_features/app_features.dart';" \
  > "$FIXTURE_ROOT/app/apps/demo/lib/allowed_shell.dart"

REPOSITORY_ROOT="$FIXTURE_ROOT" PACKAGE_DEPS_JSON="$valid_dependencies" \
  bash "$ROOT/scripts/lint/repository-boundaries.sh" >/dev/null

failing_rg="$FIXTURE_ROOT/failing-rg"
cat > "$failing_rg" <<'BASH'
#!/usr/bin/env bash
echo "fixture rg parse error" >&2
exit 2
BASH
chmod +x "$failing_rg"
if RG="$failing_rg" REPOSITORY_ROOT="$FIXTURE_ROOT" \
  PACKAGE_DEPS_JSON="$valid_dependencies" \
  bash "$ROOT/scripts/lint/repository-boundaries.sh" >/dev/null 2>&1; then
  echo "错误：仓库边界 lint 吞掉了 ripgrep 执行错误。" >&2
  exit 1
fi

printf '%s\n' 'import "package:app_features/feature_beta/controllers/beta_controller.dart";' \
  > "$FEATURE_ROOT/feature_alpha/pages/double_quote.dart"
printf '%s\n' "export '../../feature_beta/controllers/beta_controller.dart';" \
  > "$FEATURE_ROOT/feature_alpha/pages/relative_export.dart"
printf '%s\n' 'final api = Get.find<ExampleApi>(tag: "page");' \
  > "$FEATURE_ROOT/feature_alpha/pages/direct_api.dart"
printf '%s\n' "export 'generated/model.pb.dart';" \
  > "$FIXTURE_ROOT/app/packages/app_data/lib/app_data.dart"
printf '%s\n' 'final api = Get.find<ExampleApi>();' \
  > "$FEATURE_ROOT/feature_alpha/controllers/bad_controller.dart"
printf '%s\n' "export 'feature_beta/controllers/beta_controller.dart';" \
  >> "$FEATURE_ROOT/app_features.dart"
printf '%s\n' "import 'package:app_features/feature_alpha/controllers/alpha_controller.dart';" \
  > "$FIXTURE_ROOT/app/apps/demo/lib/bad_shell.dart"

invalid_dependencies="$FIXTURE_ROOT/invalid-dependencies.json"
cat > "$invalid_dependencies" <<'JSON'
{"root":"workspace","packages":[
  {"name":"workspace","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_core","kind":"root","source":"root","directDependencies":["app_features","app_media_capture_bridge"],"devDependencies":[]},
  {"name":"app_ui","kind":"root","source":"root","directDependencies":["app_media_capture_bridge"],"devDependencies":[]},
  {"name":"app_data","kind":"root","source":"root","directDependencies":["app_core","app_media","app_media_capture_bridge"],"devDependencies":[]},
  {"name":"app_im","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_media","kind":"root","source":"root","directDependencies":["app_core","app_features","app_media_capture_bridge","app_ui"],"devDependencies":[]},
  {"name":"app_media_capture_bridge","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_features","kind":"root","source":"root","directDependencies":["app_core","app_data","app_im","app_media","app_media_capture_bridge","app_ui"],"devDependencies":[]},
  {"name":"demo_app","kind":"root","source":"root","directDependencies":["app_core","app_data","app_features","app_im","app_media","app_media_capture_bridge","app_ui"],"devDependencies":[]}
]}
JSON

if output="$(REPOSITORY_ROOT="$FIXTURE_ROOT" PACKAGE_DEPS_JSON="$invalid_dependencies" \
  bash "$ROOT/scripts/lint/repository-boundaries.sh" 2>&1)"; then
  echo "错误：仓库边界 lint 未拒绝违规 Fixture。" >&2
  exit 1
fi

for expected in double_quote.dart relative_export.dart direct_api.dart app_data.dart \
  bad_controller.dart app_features.dart bad_shell.dart \
  'app_core 不得依赖 app_features, app_media_capture_bridge' \
  'app_ui 不得依赖 app_media_capture_bridge' \
  'app_data 不得依赖 app_media, app_media_capture_bridge' \
  'app_media 不得依赖 app_features, app_media_capture_bridge' \
  'app_media_capture_bridge 不得依赖 app_core'; do
  if [[ "$output" != *"$expected"* ]]; then
    echo "错误：仓库边界 lint 未报告 $expected。" >&2
    exit 1
  fi
done

assert_discovery_rejected() {
  local input="$1"
  local label="$2"
  if bash "$ROOT/scripts/dart-tool.sh" run tool/check_flutter_plugin_discovery.dart \
    --input "$input" \
    --workspace-root "$FIXTURE_ROOT/app" \
    >/dev/null 2>&1; then
    echo "错误：Plugin discovery 门禁未拒绝 $label。" >&2
    exit 1
  fi
}

invalid_discovery="$FIXTURE_ROOT/invalid-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":true}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" > "$invalid_discovery"
assert_discovery_rejected "$invalid_discovery" "dev dependency"

duplicate_discovery="$FIXTURE_ROOT/duplicate-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false},{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" > "$duplicate_discovery"
assert_discovery_rejected "$duplicate_discovery" "duplicate plugin entry"

non_native_discovery="$FIXTURE_ROOT/non-native-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":false,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" > "$non_native_discovery"
assert_discovery_rejected "$non_native_discovery" "non-native plugin"

wrong_path_discovery="$FIXTURE_ROOT/wrong-path-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$FIXTURE_ROOT/app/apps/demo" > "$wrong_path_discovery"
assert_discovery_rejected "$wrong_path_discovery" "unexpected plugin path"

missing_graph_discovery="$FIXTURE_ROOT/missing-graph-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[]}\n' \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge" > "$missing_graph_discovery"
assert_discovery_rejected "$missing_graph_discovery" "missing dependency graph entry"

inside_workspace="$FIXTURE_ROOT/inside-symlink-workspace"
mkdir -p "$inside_workspace/packages" "$inside_workspace/reviewed-alternative"
ln -s "$inside_workspace/reviewed-alternative" \
  "$inside_workspace/packages/app_media_capture_bridge"
inside_symlink_discovery="$FIXTURE_ROOT/inside-symlink-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$inside_workspace/packages/app_media_capture_bridge" > "$inside_symlink_discovery"
if bash "$ROOT/scripts/dart-tool.sh" run tool/check_flutter_plugin_discovery.dart \
  --input "$inside_symlink_discovery" --workspace-root "$inside_workspace" \
  >/dev/null 2>&1; then
  echo "错误：Plugin discovery 门禁未拒绝仓库内 Package 符号链接。" >&2
  exit 1
fi

outside_workspace="$FIXTURE_ROOT/outside-symlink-workspace"
outside_plugin="$FIXTURE_ROOT/outside-plugin"
mkdir -p "$outside_workspace/packages" "$outside_plugin"
ln -s "$outside_plugin" "$outside_workspace/packages/app_media_capture_bridge"
outside_symlink_discovery="$FIXTURE_ROOT/outside-symlink-plugin-discovery.json"
printf '{"plugins":{"android":[{"name":"app_media_capture_bridge","path":"%s/","native_build":true,"dependencies":[],"dev_dependency":false}]},"dependencyGraph":[{"name":"app_media_capture_bridge","dependencies":[]}]}\n' \
  "$outside_workspace/packages/app_media_capture_bridge" > "$outside_symlink_discovery"
if bash "$ROOT/scripts/dart-tool.sh" run tool/check_flutter_plugin_discovery.dart \
  --input "$outside_symlink_discovery" --workspace-root "$outside_workspace" \
  >/dev/null 2>&1; then
  echo "错误：Plugin discovery 门禁未拒绝仓库外 Package 符号链接。" >&2
  exit 1
fi

echo "[lint-test] 仓库边界 Fixture 通过。"
