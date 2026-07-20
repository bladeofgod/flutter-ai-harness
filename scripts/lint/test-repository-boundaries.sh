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
  "$FEATURE_ROOT/feature_beta/controllers" \
  "$FIXTURE_ROOT/app/packages/app_data/lib/generated" \
  "$FIXTURE_ROOT/app/packages/app_data/lib/mappers" \
  "$FIXTURE_ROOT/app/apps/demo/lib"

valid_dependencies="$FIXTURE_ROOT/valid-dependencies.json"
cat > "$valid_dependencies" <<'JSON'
{"root":"workspace","packages":[
  {"name":"workspace","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_core","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_ui","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_data","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_im","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_features","kind":"root","source":"root","directDependencies":["app_core","app_data","app_im","app_ui"],"devDependencies":[]},
  {"name":"demo_app","kind":"root","source":"root","directDependencies":["app_core","app_data","app_features","app_im","app_ui"],"devDependencies":[]}
]}
JSON

printf '%s\n' \
  "import 'package:app_features/feature_alpha/controllers/alpha_controller.dart';" \
  'void buildPage() => AlphaController(api: Get.find<ExampleApi>());' \
  > "$FEATURE_ROOT/feature_alpha/pages/allowed.dart"
printf '%s\n' 'class AlphaController { AlphaController({required Object api}); }' \
  > "$FEATURE_ROOT/feature_alpha/controllers/alpha_controller.dart"
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
printf '%s\n' "import 'package:app_features/feature_alpha/controllers/alpha_controller.dart';" \
  > "$FIXTURE_ROOT/app/apps/demo/lib/bad_shell.dart"

invalid_dependencies="$FIXTURE_ROOT/invalid-dependencies.json"
cat > "$invalid_dependencies" <<'JSON'
{"root":"workspace","packages":[
  {"name":"workspace","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_core","kind":"root","source":"root","directDependencies":["app_features"],"devDependencies":[]},
  {"name":"app_ui","kind":"root","source":"root","directDependencies":[],"devDependencies":[]},
  {"name":"app_data","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_im","kind":"root","source":"root","directDependencies":["app_core"],"devDependencies":[]},
  {"name":"app_features","kind":"root","source":"root","directDependencies":["app_core","app_data","app_im","app_ui"],"devDependencies":[]},
  {"name":"demo_app","kind":"root","source":"root","directDependencies":["app_core","app_data","app_features","app_im","app_ui"],"devDependencies":[]}
]}
JSON

if output="$(REPOSITORY_ROOT="$FIXTURE_ROOT" PACKAGE_DEPS_JSON="$invalid_dependencies" \
  bash "$ROOT/scripts/lint/repository-boundaries.sh" 2>&1)"; then
  echo "错误：仓库边界 lint 未拒绝违规 Fixture。" >&2
  exit 1
fi

for expected in double_quote.dart relative_export.dart direct_api.dart app_data.dart \
  bad_controller.dart bad_shell.dart 'app_core 不得依赖 app_features'; do
  if [[ "$output" != *"$expected"* ]]; then
    echo "错误：仓库边界 lint 未报告 $expected。" >&2
    exit 1
  fi
done

echo "[lint-test] 仓库边界 Fixture 通过。"
