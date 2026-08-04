#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/app/native/android/media_capture_gate"
GRADLEW="$GATE/gradlew"
CORE="$ROOT/app/native/android/media_capture"
UI="$ROOT/app/native/android/media_capture_ui"
ADAPTER="$ROOT/app/packages/app_media_capture_bridge/android"
ADAPTER_MAIN="$ADAPTER/src/main"
PLUGIN_PUBSPEC="$ROOT/app/packages/app_media_capture_bridge/pubspec.yaml"

fail() {
  echo "[media-capture-android] error: $*" >&2
  exit 1
}

stage() {
  echo
  echo "[media-capture-android] $*"
}

require_file() {
  [[ -f "$1" ]] || fail "missing repository file: ${1#"$ROOT"/}"
}

assert_no_match() {
  local description="$1"
  local pattern="$2"
  shift 2
  local output
  local status
  set +e
  output="$(rg -n "$pattern" "$@" 2>&1)"
  status=$?
  set -e
  case "$status" in
    0)
      echo "$output" >&2
      fail "$description"
      ;;
    1) return ;;
    *)
      echo "$output" >&2
      fail "boundary scan failed while checking: $description"
      ;;
  esac
}

assert_match_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual
  local output
  local status
  set +e
  output="$(rg -n "$pattern" "$file" 2>&1)"
  status=$?
  set -e
  case "$status" in
    0) actual="$(wc -l <<< "$output" | tr -d ' ')" ;;
    1) actual=0 ;;
    *)
      echo "$output" >&2
      fail "dependency scan failed in ${file#"$ROOT"/}"
      ;;
  esac
  [[ "$actual" == "$expected" ]] ||
    fail "unexpected dependency edge count in ${file#"$ROOT"/}: expected $expected, got $actual"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    fail "sha256sum or shasum is required"
  fi
}

assert_file_digest() {
  local expected="$1"
  local file="$2"
  require_file "$file"
  [[ ! -L "$file" ]] || fail "tracked gate input must not be a symlink: ${file#"$ROOT"/}"
  local actual
  actual="$(sha256_file "$file")"
  [[ "$actual" == "$expected" ]] ||
    fail "reviewed Gradle input changed: ${file#"$ROOT"/}"
}

assert_trackable_regular_file() {
  local file="$1"
  require_file "$file"
  [[ -f "$file" && ! -L "$file" ]] ||
    fail "gate executable input must be a regular non-symlink file: ${file#"$ROOT"/}"
  if git -C "$ROOT" check-ignore -q "${file#"$ROOT"/}"; then
    fail "gate executable input is ignored by Git: ${file#"$ROOT"/}"
  fi
}

assert_production_dependencies() {
  local file="$1"
  shift
  local actual
  local expected
  actual="$({
    sed -nE 's/^[[:space:]]*(compileOnly|implementation)\((.*)\)[[:space:]]*$/\1(\2)/p' "$file"
  } | LC_ALL=C sort)"
  expected="$(printf '%s\n' "$@" | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] || {
    echo "[media-capture-android] expected production dependencies:" >&2
    echo "$expected" >&2
    echo "[media-capture-android] actual production dependencies:" >&2
    echo "$actual" >&2
    fail "production dependency allowlist changed in ${file#"$ROOT"/}"
  }
}

assert_repository_allowlist() {
  local file="$1"
  shift
  local actual
  local expected
  actual="$({
    sed -nE 's/^[[:space:]]*(google\(\)|mavenCentral\(\)|gradlePluginPortal\(\)|maven\("[^"]+"\))[[:space:]]*$/\1/p' "$file"
  } | LC_ALL=C sort -u)"
  expected="$(printf '%s\n' "$@" | LC_ALL=C sort -u)"
  [[ "$actual" == "$expected" ]] ||
    fail "repository allowlist changed in ${file#"$ROOT"/}"
}

run_gradle() {
  "$GRADLEW" -p "$GATE" \
    --no-build-cache \
    --dependency-verification strict \
    --console=plain \
    "$@"
}

report_module_outputs() {
  local name="$1"
  local project="$2"
  local expected_tests="$3"
  local variant
  for variant in Debug Release; do
    local variant_lower
    variant_lower="$(tr '[:upper:]' '[:lower:]' <<< "$variant")"
    local result_dir="$project/build/test-results/test${variant}UnitTest"
    local summary
    local tests
    local skipped
    local failures
    local errors
    local result_files=("$result_dir"/TEST-*.xml)
    [[ -f "${result_files[0]}" ]] ||
      fail "$name $variant did not produce JUnit XML"
    summary="$(awk -F'"' '
      /<testsuite / {
        for (field_index = 1; field_index <= NF; field_index += 1) {
          if ($field_index ~ / tests=$/) tests += $(field_index + 1)
          if ($field_index ~ / skipped=$/) skipped += $(field_index + 1)
          if ($field_index ~ / failures=$/) failures += $(field_index + 1)
          if ($field_index ~ / errors=$/) errors += $(field_index + 1)
        }
      }
      END { printf "%d %d %d %d", tests, skipped, failures, errors }
    ' "${result_files[@]}")"
    read -r tests skipped failures errors <<< "$summary"
    [[ "$tests" -eq "$expected_tests" && "$skipped" -eq 0 && "$failures" -eq 0 && "$errors" -eq 0 ]] ||
      fail "$name $variant test summary is not clean"
    echo "[media-capture-android] $name $variant: $tests tests, $skipped skipped, $failures failures, $errors errors"

    local aar_count
    aar_count="$(find "$project/build/outputs/aar" -maxdepth 1 \
      -type f -name "*-$variant_lower.aar" | wc -l | tr -d ' ')"
    [[ "$aar_count" -eq 1 ]] ||
      fail "$name $variant expected exactly one AAR, got $aar_count"
  done
}

resolve_flutter_root() {
  if [[ -n "${FLUTTER_ROOT:-}" ]]; then
    [[ -x "$FLUTTER_ROOT/bin/flutter" ]] || fail "FLUTTER_ROOT does not contain bin/flutter"
    return
  fi

  local flutter_json
  flutter_json="$(TOOL_WORKDIR="$ROOT/app" bash "$ROOT/scripts/flutter-tool.sh" --version --machine)"
  FLUTTER_ROOT="$(sed -nE 's/^[[:space:]]*"flutterRoot": "([^"]+)",?$/\1/p' <<< "$flutter_json")"
  [[ -n "$FLUTTER_ROOT" && -x "$FLUTTER_ROOT/bin/flutter" ]] ||
    fail "unable to resolve the selected Flutter SDK root"
  export FLUTTER_ROOT
}

validate_toolchain() {
  command -v rg >/dev/null 2>&1 || fail "ripgrep is required"
  command -v git >/dev/null 2>&1 || fail "Git is required"
  assert_trackable_regular_file "$GRADLEW"
  assert_trackable_regular_file "$GATE/gradle/wrapper/gradle-wrapper.jar"
  assert_trackable_regular_file "$GATE/gradle/wrapper/gradle-wrapper.properties"
  assert_file_digest c07475b363508dbe7cf7d1ded1b31f6d44bb97d98d069a455ab862b1fb9b25f0 "$GRADLEW"
  assert_file_digest 2db75c40782f5e8ba1fc278a5574bab070adccb2d21ca5a6e5ed840888448046 \
    "$GATE/gradle/wrapper/gradle-wrapper.jar"
  assert_file_digest 8d3dcc8e3fef9b9865e9e3a6ee453c702a0d8a77da0d7a0ca817d206fdf2176b \
    "$GATE/gradle/wrapper/gradle-wrapper.properties"
  require_file "$CORE/build.gradle.kts"
  require_file "$UI/build.gradle.kts"
  require_file "$ADAPTER/build.gradle.kts"
  require_file "$PLUGIN_PUBSPEC"

  assert_match_count 1 \
    '^distributionUrl=https\\://services\.gradle\.org/distributions/gradle-8\.12-all\.zip$' \
    "$GATE/gradle/wrapper/gradle-wrapper.properties"
  assert_match_count 1 \
    '^distributionSha256Sum=7ebdac923867a3cec0098302416d1e3c6c0c729fc4e2e05c10637a8af33a76c5$' \
    "$GATE/gradle/wrapper/gradle-wrapper.properties"

  local java_spec
  local java_major
  local java_bin
  if [[ -n "${JAVA_HOME:-}" ]]; then
    java_bin="$JAVA_HOME/bin/java"
    [[ -x "$java_bin" ]] || fail "JAVA_HOME does not contain bin/java"
  else
    java_bin="$(command -v java || true)"
    [[ -n "$java_bin" ]] || fail "Java is required"
  fi
  java_spec="$("$java_bin" -XshowSettings:properties -version 2>&1 |
    sed -n 's/^[[:space:]]*java.specification.version = //p' | head -n 1)"
  java_major="${java_spec#1.}"
  java_major="${java_major%%.*}"
  [[ "$java_major" =~ ^[0-9]+$ && "$java_major" -ge 17 ]] ||
    fail "Android Gradle Plugin 8.9.1 requires JDK 17 or newer"

  if [[ -z "${ANDROID_HOME:-}" && -n "${ANDROID_SDK_ROOT:-}" ]]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
  fi
  [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]] ||
    fail "set ANDROID_HOME or ANDROID_SDK_ROOT to an installed Android SDK"

  resolve_flutter_root

  local flutter_version
  flutter_version="$("$FLUTTER_ROOT/bin/flutter" --version --machine |
    sed -nE 's/^[[:space:]]*"flutterVersion": "([^"]+)",?$/\1/p')"
  [[ "$flutter_version" == "3.41.9" ]] ||
    fail "expected Flutter 3.41.9, got ${flutter_version:-unknown}"
}

validate_transfer_adapter() {
  stage "Validate Wire V3 transfer Adapter, private cache and plugin registration"

  assert_match_count 1 \
    '^internal const val MEDIA_CAPTURE_WIRE_VERSION = 3$' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt"
  assert_match_count 2 \
    '"materialize_media_resource"' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt"
  assert_match_count 3 \
    '"release_materialized_media"' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt"
  assert_match_count 1 \
    'const val TRANSFER_RELATIVE_PATH = "app_media_capture_bridge/exports"' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt"
  assert_match_count 1 \
    'Uri\.fromFile\(' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt"
  assert_match_count 1 \
    '^import android\.util\.Base64$' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt"
  assert_match_count 1 \
    'copyConfirmedMediaToSink\(' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture/MediaCaptureBridgeController.kt"
  assert_match_count 1 \
    'package: com\.example\.media_capture' \
    "$PLUGIN_PUBSPEC"
  assert_match_count 2 \
    'pluginClass: MediaCaptureBridgePlugin' \
    "$PLUGIN_PUBSPEC"

  assert_no_match \
    "Adapter production code must not use API-26 java.util.Base64" \
    'java\.util\.Base64' \
    "$ADAPTER_MAIN"
  assert_no_match \
    "Adapter Manifest must not add permissions or exported components" \
    'uses-permission|<activity|<service|<receiver|<provider' \
    "$ADAPTER_MAIN/AndroidManifest.xml"
  assert_no_match \
    "Transfer Adapter must not log local locators or handles" \
    'android\.util\.Log|println\(|printStackTrace\(' \
    "$ADAPTER_MAIN/kotlin/com/example/media_capture"
}

validate_dependency_boundaries() {
  stage "Validate dependency direction and reproducibility"

  assert_file_digest 9dfee90fa6fbfb281f69cf79a5eb418651abf18aa7545c6bea612874c455afa5 \
    "$GATE/build.gradle.kts"
  assert_file_digest 26134db70bb57177212f147d6920d21f59ee6fa829b73ae6f84d5ae2f974dce0 \
    "$GATE/settings.gradle.kts"
  assert_file_digest 1d08c6e29614f2fab4b44b677c91ce283e81b45c3e4351eee54b040fe8267137 \
    "$GATE/gradle.properties"
  assert_file_digest 60c8cdb48f5c222cf4d8e221d06a98db834f0b8ef13be2c03a10eac88d740e00 \
    "$GATE/gradle/verification-metadata.xml"
  assert_file_digest a5c6a687855975640608e035c0709f134890590305e9802a21a820dd66e3455f \
    "$CORE/build.gradle.kts"
  assert_file_digest 9bc4a2fc03e2e2e1863204518e8aa7b15278d929f6ade977c1f8a29bade8c805 \
    "$CORE/settings.gradle.kts"
  assert_file_digest 858c2b8f6ce36e56bb8f50642411c175459aec77175820fe97392e559c7973a4 \
    "$CORE/gradle.properties"
  assert_file_digest 7c762ec9dbc0cf890e735872697ad73de5054d556905cfa4203215d335fea6fe \
    "$UI/build.gradle.kts"
  assert_file_digest 85922d37f5819523a8826024cccb0a15414cd02865f1291d93fdf5d4ff114fd3 \
    "$UI/settings.gradle.kts"
  assert_file_digest 858c2b8f6ce36e56bb8f50642411c175459aec77175820fe97392e559c7973a4 \
    "$UI/gradle.properties"
  assert_file_digest 01661dcd32e26a21f529e0bf244ef4f9ef38e66376d96b4a17864ecc850f84af \
    "$ADAPTER/build.gradle.kts"
  assert_file_digest f5358f99ff97e50bad3520b1024a7ef4bab2ff8459adf353ccb348f6da11b8e5 \
    "$ADAPTER/settings.gradle.kts"
  assert_file_digest ee12152131934d0cf3586576f4ee7385c8783081846717ea2953d2fc8881e51b \
    "$ADAPTER/gradle.properties"

  [[ "$(cd "$CORE" && pwd -P)" == "$ROOT/app/native/android/media_capture" ]] ||
    fail "Core project path escaped the repository layout"
  [[ "$(cd "$UI" && pwd -P)" == "$ROOT/app/native/android/media_capture_ui" ]] ||
    fail "Native UI project path escaped the repository layout"
  [[ "$(cd "$ADAPTER" && pwd -P)" == "$ROOT/app/packages/app_media_capture_bridge/android" ]] ||
    fail "Adapter project path escaped the repository layout"

  assert_no_match \
    "Core must not import Flutter or Channel APIs" \
    'io\.flutter|org\.flutter|MethodChannel|EventChannel|BinaryMessenger|StandardMethodCodec' \
    "$CORE/src/main"
  assert_no_match \
    "Native UI must not import Flutter or CameraX implementation APIs" \
    'io\.flutter|org\.flutter|MethodChannel|EventChannel|BinaryMessenger|StandardMethodCodec|androidx\.camera|SurfaceProvider|PreviewView' \
    "$UI/src/main"

  assert_match_count 0 'project\(' "$CORE/build.gradle.kts"
  assert_match_count 1 'implementation\(project\(":media_capture_core"\)\)' "$UI/build.gradle.kts"
  assert_match_count 1 'implementation\(project\(":media_capture_core"\)\)' "$ADAPTER/build.gradle.kts"
  assert_match_count 1 'implementation\(project\(":media_capture_ui"\)\)' "$ADAPTER/build.gradle.kts"
  assert_match_count 1 '^include\(":media_capture_core"\)$' "$UI/settings.gradle.kts"
  assert_match_count 1 '^include\(":media_capture_core"\)$' "$ADAPTER/settings.gradle.kts"
  assert_match_count 1 '^include\(":media_capture_ui"\)$' "$ADAPTER/settings.gradle.kts"
  assert_match_count 1 '^project\(":media_capture_core"\)\.projectDir = file\("\.\./media_capture"\)$' "$GATE/settings.gradle.kts"
  assert_match_count 1 '^project\(":media_capture_ui"\)\.projectDir = file\("\.\./media_capture_ui"\)$' "$GATE/settings.gradle.kts"
  assert_match_count 1 '^project\(":media_capture_bridge"\)\.projectDir = file\("\.\./\.\./\.\./packages/app_media_capture_bridge/android"\)$' "$GATE/settings.gradle.kts"
  assert_match_count 1 'id\("com\.android\.library"\) version "8\.9\.1"' "$CORE/build.gradle.kts"
  assert_match_count 1 'id\("org\.jetbrains\.kotlin\.android"\) version "2\.1\.0"' "$CORE/build.gradle.kts"
  assert_match_count 1 'val cameraXVersion = "1\.5\.1"' "$CORE/build.gradle.kts"
  assert_match_count 1 'val coroutinesVersion = "1\.9\.0"' "$CORE/build.gradle.kts"
  assert_match_count 1 'val coroutinesVersion = "1\.9\.0"' "$UI/build.gradle.kts"
  assert_match_count 1 'val coroutinesVersion = "1\.9\.0"' "$ADAPTER/build.gradle.kts"

  assert_production_dependencies "$CORE/build.gradle.kts" \
    'implementation("androidx.camera:camera-camera2:$cameraXVersion")' \
    'implementation("androidx.camera:camera-lifecycle:$cameraXVersion")' \
    'implementation("androidx.camera:camera-video:$cameraXVersion")' \
    'implementation("androidx.camera:camera-view:$cameraXVersion")' \
    'implementation("androidx.exifinterface:exifinterface:1.4.2")' \
    'implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$coroutinesVersion")'
  assert_production_dependencies "$UI/build.gradle.kts" \
    'implementation("androidx.core:core-ktx:1.16.0")' \
    'implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.2")' \
    'implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$coroutinesVersion")' \
    'implementation(project(":media_capture_core"))'
  assert_production_dependencies "$ADAPTER/build.gradle.kts" \
    'compileOnly("io.flutter:flutter_embedding_debug:$flutterEngineVersion")' \
    'implementation("androidx.core:core-ktx:1.16.0")' \
    'implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.2")' \
    'implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$coroutinesVersion")' \
    'implementation(project(":media_capture_core"))' \
    'implementation(project(":media_capture_ui"))'

  assert_repository_allowlist "$CORE/settings.gradle.kts" \
    'google()' 'mavenCentral()' 'gradlePluginPortal()'
  assert_repository_allowlist "$UI/settings.gradle.kts" \
    'google()' 'mavenCentral()' 'gradlePluginPortal()'
  assert_repository_allowlist "$ADAPTER/settings.gradle.kts" \
    'google()' 'mavenCentral()' 'gradlePluginPortal()' \
    'maven("https://storage.googleapis.com/download.flutter.io")'

  assert_no_match \
    "Gradle inputs must not use dynamic or snapshot versions" \
    '"[^"]*(\+|latest|LATEST|SNAPSHOT)[^"]*"' \
    "$CORE/build.gradle.kts" "$UI/build.gradle.kts" "$ADAPTER/build.gradle.kts"
  assert_no_match \
    "Gradle inputs must not use local or flat repositories" \
    'mavenLocal\(|flatDir\s*\{' \
    "$CORE/settings.gradle.kts" "$UI/settings.gradle.kts" "$ADAPTER/settings.gradle.kts"
  assert_no_match \
    "Tracked Android module inputs must not contain workstation paths" \
    '/(Users|home)/[^$]|[A-Za-z]:\\\\' \
    "$CORE/build.gradle.kts" "$CORE/settings.gradle.kts" "$CORE/gradle.properties" \
    "$UI/build.gradle.kts" "$UI/settings.gradle.kts" "$UI/gradle.properties" \
    "$ADAPTER/build.gradle.kts" "$ADAPTER/settings.gradle.kts" "$ADAPTER/gradle.properties"
}

run_module_gate() {
  local name="$1"
  local project_name="$2"
  local project="$3"
  local expected_tests="$4"
  stage "$name: clean, Debug/Release tests, lint, AAR assembly and resolved dependency graph"
  run_gradle \
    ":$project_name:clean" \
    ":$project_name:test" \
    ":$project_name:lint" \
    ":$project_name:assembleDebug" \
    ":$project_name:assembleRelease" \
    ":$project_name:dependencies" --configuration debugRuntimeClasspath \
    --rerun-tasks
  report_module_outputs "$name" "$project" "$expected_tests"
}

assert_contract_test_classes() {
  local result_dir="$1"
  shift
  while [[ "$#" -gt 0 ]]; do
    local class_name="$1"
    local expected_tests="$2"
    shift 2
    local result_file="$result_dir/TEST-$class_name.xml"
    require_file "$result_file"
    local summary
    summary="$(awk -F'"' '
      /<testsuite / {
        for (field_index = 1; field_index <= NF; field_index += 1) {
          if ($field_index ~ / tests=$/) tests += $(field_index + 1)
          if ($field_index ~ / skipped=$/) skipped += $(field_index + 1)
          if ($field_index ~ / failures=$/) failures += $(field_index + 1)
          if ($field_index ~ / errors=$/) errors += $(field_index + 1)
        }
      }
      END { printf "%d %d %d %d", tests, skipped, failures, errors }
    ' "$result_file")"
    local tests
    local skipped
    local failures
    local errors
    read -r tests skipped failures errors <<< "$summary"
    [[ "$tests" -eq "$expected_tests" && "$skipped" -eq 0 && "$failures" -eq 0 && "$errors" -eq 0 ]] ||
      fail "contract vector class did not execute cleanly: $class_name"
    echo "[media-capture-android] contract vector: $class_name ($tests tests)"
  done
}

run_contract_matrix() {
  stage "Re-run Android capability, renderer, UI and Wire contract vectors"
  run_gradle \
    :media_capture_core:testDebugUnitTest \
    --tests 'com.example.mediacapture.MediaCaptureCoreStateTest' \
    --tests 'com.example.mediacapture.MediaCaptureRenderViewTest' \
    --tests 'com.example.mediacapture.MediaCaptureRenderBackgroundGateTest' \
    --tests 'com.example.mediacapture.RenderAttachmentTest' \
    --tests 'com.example.mediacapture.ThumbnailJobTest' \
    --rerun-tasks
  assert_contract_test_classes "$CORE/build/test-results/testDebugUnitTest" \
    com.example.mediacapture.MediaCaptureCoreStateTest 10 \
    com.example.mediacapture.MediaCaptureRenderViewTest 8 \
    com.example.mediacapture.MediaCaptureRenderBackgroundGateTest 3 \
    com.example.mediacapture.RenderAttachmentTest 9 \
    com.example.mediacapture.ThumbnailJobTest 11

  run_gradle \
    :media_capture_ui:testDebugUnitTest \
    --tests 'com.example.mediacapture.ui.MediaCaptureFlowCoordinatorTest' \
    --tests 'com.example.mediacapture.ui.MediaCaptureUiPresenterTest' \
    --rerun-tasks
  assert_contract_test_classes "$UI/build/test-results/testDebugUnitTest" \
    com.example.mediacapture.ui.MediaCaptureFlowCoordinatorTest 19 \
    com.example.mediacapture.ui.MediaCaptureUiPresenterTest 10

  run_gradle \
    :media_capture_bridge:testDebugUnitTest \
    --tests 'com.example.media_capture.MediaCaptureWireCodecTest' \
    --tests 'com.example.media_capture.MediaCaptureBridgeControllerTest' \
    --tests 'com.example.media_capture.BoundedCommandHandlerTest' \
    --tests 'com.example.media_capture.MediaCaptureTransferStoreTest' \
    --tests 'com.example.media_capture.AndroidContractVectorGateTest' \
    --rerun-tasks
  assert_contract_test_classes "$ADAPTER/build/test-results/testDebugUnitTest" \
    com.example.media_capture.MediaCaptureWireCodecTest 5 \
    com.example.media_capture.MediaCaptureBridgeControllerTest 40 \
    com.example.media_capture.BoundedCommandHandlerTest 3 \
    com.example.media_capture.MediaCaptureTransferStoreTest 12 \
    com.example.media_capture.AndroidContractVectorGateTest 3
}

run_gate_fixture() {
  stage "Compile the cross-module Gate and emulator-only lifecycle/UI suite"
  run_gradle \
    :clean :lint :assembleDebug :assembleRelease :assembleDebugAndroidTest \
    :media_capture_bridge:assembleDebugAndroidTest \
    --rerun-tasks
}

run_optional_instrumented_tests() {
  stage "Check optional emulator test layer"
  local adb_bin=""
  if [[ -x "$ANDROID_HOME/platform-tools/adb" ]]; then
    adb_bin="$ANDROID_HOME/platform-tools/adb"
  elif command -v adb >/dev/null 2>&1; then
    adb_bin="$(command -v adb)"
  fi

  if [[ -z "$adb_bin" ]]; then
    echo "[media-capture-android] adb unavailable; instrumented tests not run"
    return
  fi

  local emulator_count
  local physical_count
  emulator_count="$($adb_bin devices 2>/dev/null |
    awk '$1 ~ /^emulator-/ && $2 == "device" { count += 1 } END { print count + 0 }')"
  physical_count="$($adb_bin devices 2>/dev/null |
    awk '$1 !~ /^emulator-/ && $1 != "List" && $2 == "device" { count += 1 } END { print count + 0 }')"
  if [[ "$emulator_count" -eq 0 ]]; then
    echo "[media-capture-android] no ready emulator; connectedDebugAndroidTest not run"
    return
  fi
  [[ "$emulator_count" -eq 1 ]] || fail "instrumented Gate requires exactly one ready emulator"
  [[ "$physical_count" -eq 0 ]] ||
    fail "disconnect physical devices before running the emulator-only instrumented Gate"

  local emulator_serial
  emulator_serial="$($adb_bin devices 2>/dev/null |
    awk '$1 ~ /^emulator-/ && $2 == "device" { print $1 }')"
  local emulator_sdk
  emulator_sdk="$($adb_bin -s "$emulator_serial" shell getprop ro.build.version.sdk 2>/dev/null |
    tr -d '\r[:space:]')"
  [[ "$emulator_sdk" =~ ^[0-9]+$ ]] || fail "unable to determine emulator Android SDK level"
  if [[ "$emulator_sdk" == "23" ]]; then
    echo "[media-capture-android] API 23 emulator selected; minimum-SDK Store runtime will be verified"
  else
    echo "[media-capture-android] emulator SDK $emulator_sdk selected; suites will run, but API 23 Store runtime remains unverified"
  fi
  ANDROID_SERIAL="$emulator_serial" run_gradle \
    :connectedDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.example.mediacapture.gate.MediaCaptureGateInstrumentedTest \
    --rerun-tasks
  ANDROID_SERIAL="$emulator_serial" run_gradle \
    :media_capture_bridge:connectedDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.example.media_capture.MediaCaptureTransferStoreInstrumentedTest \
    --rerun-tasks
}

stage "Validate locked toolchain"
validate_toolchain
validate_dependency_boundaries
validate_transfer_adapter
run_module_gate "Core" media_capture_core "$CORE" 88
run_module_gate "Native UI" media_capture_ui "$UI" 42
run_module_gate "Bridge Adapter" media_capture_bridge "$ADAPTER" 71
run_contract_matrix
run_gate_fixture
run_optional_instrumented_tests

stage "PASS"
echo "[media-capture-android] static Android gate passed; Host and physical-device validation remain separate"
