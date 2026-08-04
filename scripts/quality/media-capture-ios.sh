#!/usr/bin/env bash
set -euo pipefail

umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE="$ROOT/app/native/ios/MediaCapture"
UI="$ROOT/app/native/ios/MediaCaptureUI"
ADAPTER="$ROOT/app/packages/app_media_capture_bridge/ios/app_media_capture_bridge"
ADAPTER_TOOL="$ROOT/app/packages/app_media_capture_bridge/ios/tool"
CONTRACT="$ROOT/docs/bridge/contracts/media-capture.wire.json"
VECTOR_TEST="$ADAPTER/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift"
REAL_HOST_IOS="$ROOT/app/apps/demo/ios"
REAL_HOST_PUBSPEC="$ROOT/app/apps/demo/pubspec.yaml"
TEMP_ROOT_ALIAS="$(mktemp -d "${TMPDIR:-/tmp}/media-capture-ios-gate.XXXXXX")"
TEMP_ROOT="$(cd "$TEMP_ROOT_ALIAS" && pwd -P)"
FLUTTER_EXECUTABLE=''
FLUTTER_ROOT_PATH=''

cleanup() {
  if [[ -d "$TEMP_ROOT_ALIAS" ]]; then
    find -P "$TEMP_ROOT_ALIAS" -depth -delete
  fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
chmod 700 "$TEMP_ROOT_ALIAS"

fail() {
  printf '[media-capture-ios] error: %s\n' "$*" >&2
  exit 1
}

stage() {
  printf '\n[media-capture-ios] %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

require_file() {
  [[ -f "$1" && ! -L "$1" ]] ||
    fail "missing regular repository file: ${1#"$ROOT"/}"
}

assert_file_digest() {
  local expected="$1"
  local file="$2"
  local actual
  actual="$(ruby -rdigest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$file")" ||
    fail "unable to hash reviewed input: ${file#"$ROOT"/}"
  [[ "$actual" == "$expected" ]] || fail "reviewed input digest drifted: ${file#"$ROOT"/}"
}

assert_no_match() {
  local description="$1"
  local pattern="$2"
  shift 2
  local status
  set +e
  rg -n "$pattern" "$@" >/dev/null 2>&1
  status=$?
  set -e
  case "$status" in
    0)
      fail "$description"
      ;;
    1) return ;;
    *)
      fail "scan failed while checking: $description"
      ;;
  esac
}

assert_import_allowlist() {
  local directory="$1"
  local allowed="$2"
  if ! ruby - "$directory" "$allowed" <<'RUBY'
root = ARGV.fetch(0)
allowed = ARGV.fetch(1).split(",").to_h { |module_name| [module_name, true] }
files = Dir.glob(File.join(root, "**", "*.swift")).sort
abort "no Swift sources found" if files.empty?

import_pattern = /\A\s*(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)|(?:(?:private|fileprivate|internal|package|public)\s+))*import(?:\s+(?:typealias|struct|class|enum|protocol|let|var|func))?\s+([A-Za-z_][A-Za-z0-9_]*)(?:\.[A-Za-z_][A-Za-z0-9_]*)*\s*(?:\/\/.*)?\z/

files.each do |file|
  File.foreach(file) do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("//") || !stripped.match?(/\bimport\b/)

    match = line.match(import_pattern)
    abort "unrecognized Swift import declaration" unless match
    module_name = match[1]
    abort "unexpected Swift import module: #{module_name}" unless allowed[module_name]
  end
end
RUBY
  then
    fail "import allowlist failed under ${directory#"$ROOT"/}"
  fi
}

assert_exact_package_graph() {
  if ! ruby -rjson -ropen3 - "$CORE" "$UI" "$ADAPTER" <<'RUBY'
def reject(message)
  warn "package graph mismatch: #{message}"
  exit 1
end

def dump_package(path)
  output, _error, status = Open3.capture3("swift", "package", "dump-package", chdir: path)
  reject("swift package dump-package failed") unless status.success?
  JSON.parse(output)
rescue JSON::ParserError
  reject("swift package dump-package returned invalid JSON")
end

def dependency_shape(dependency)
  if (by_name = dependency["byName"])
    ["byName", by_name.fetch(0)]
  elsif (product = dependency["product"])
    ["product", product.fetch(0), product.fetch(1)]
  else
    reject("unsupported target dependency shape")
  end
end

def validate_package(path, expected)
  package = dump_package(path)
  reject("unexpected package name") unless package["name"] == expected.fetch(:name)
  reject("unexpected tools version") unless package.dig("toolsVersion", "_version") == "5.9.0"
  reject("unexpected platform baseline") unless package["platforms"] == [
    {"options" => [], "platformName" => "ios", "version" => "13.0"},
  ]

  dependencies = package.fetch("dependencies").map do |dependency|
    file_system = dependency["fileSystem"]
    reject("only local filesystem package dependencies are allowed") unless file_system&.length == 1
    File.realpath(file_system.fetch(0).fetch("path"))
  end
  reject("package dependency set drifted") unless dependencies == expected.fetch(:dependencies).map { |item| File.realpath(item) }

  products = package.fetch("products").map do |product|
    type = product.fetch("type")
    reject("only library products are allowed") unless type.keys == ["library"]
    [product.fetch("name"), product.fetch("targets")]
  end
  reject("product graph drifted") unless products == expected.fetch(:products)

  targets = package.fetch("targets").map do |target|
    [
      target.fetch("name"),
      target.fetch("type"),
      target.fetch("dependencies").map { |dependency| dependency_shape(dependency) },
    ]
  end
  reject("target dependency graph drifted") unless targets == expected.fetch(:targets)
end

core, ui, adapter = ARGV
validate_package(core, {
  name: "MediaCapture",
  dependencies: [],
  products: [
    ["MediaCapture", ["MediaCapture"]],
    ["MediaCaptureAppleRendering", ["MediaCaptureAppleRendering"]],
  ],
  targets: [
    ["MediaCapture", "regular", []],
    ["MediaCaptureAppleRendering", "regular", [["byName", "MediaCapture"]]],
    ["MediaCaptureTests", "test", [["byName", "MediaCapture"], ["byName", "MediaCaptureAppleRendering"]]],
    ["MediaCaptureAppleRenderingTests", "test", [["byName", "MediaCapture"], ["byName", "MediaCaptureAppleRendering"]]],
    ["MediaCapturePublicConsumerTests", "test", [["byName", "MediaCapture"], ["byName", "MediaCaptureAppleRendering"]]],
  ],
})
validate_package(ui, {
  name: "MediaCaptureUI",
  dependencies: [core],
  products: [["MediaCaptureUI", ["MediaCaptureUI"]]],
  targets: [
    ["MediaCaptureUI", "regular", [["product", "MediaCapture", "MediaCapture"], ["product", "MediaCaptureAppleRendering", "MediaCapture"]]],
    ["MediaCaptureUITests", "test", [["byName", "MediaCaptureUI"]]],
  ],
})
validate_package(adapter, {
  name: "app_media_capture_bridge",
  dependencies: [core, ui],
  products: [
    ["app-media-capture-bridge", ["app_media_capture_bridge"]],
    ["MediaCaptureBridgeCore", ["MediaCaptureBridgeCore"]],
  ],
  targets: [
    ["MediaCaptureBridgeCore", "regular", [["product", "MediaCapture", "MediaCapture"], ["product", "MediaCaptureUI", "MediaCaptureUI"]]],
    ["app_media_capture_bridge", "regular", [["byName", "MediaCaptureBridgeCore"]]],
    ["MediaCaptureBridgeCoreTests", "test", [["byName", "MediaCaptureBridgeCore"], ["product", "MediaCapture", "MediaCapture"]]],
  ],
})
RUBY
  then
    fail "Swift Package graph validation failed"
  fi
}

require_test() {
  local directory="$1"
  local name="$2"
  rg -q "func $name\\(" "$directory" || fail "required XCTest is missing: $name"
}

show_failure() {
  : "$1"
  printf '%s\n' '[media-capture-ios] private build output was not emitted' >&2
}

assert_no_concurrency_warnings() {
  local log="$1"
  local status
  set +e
  rg -i -n 'warning:.*(sendable|actor[- ]isolated|main actor|concurren|data race|non-sendable)' \
    "$log" >/dev/null 2>&1
  status=$?
  set -e
  case "$status" in
    0)
      fail "Swift concurrency warnings were emitted"
      ;;
    1) return ;;
    *)
      fail "concurrency warning scan failed"
      ;;
  esac
}

path_digest() {
  ruby -rdigest - "$@" <<'RUBY'
digest = Digest::SHA256.new

ARGV.each_with_index do |root, root_index|
  unless File.exist?(root) || File.symlink?(root)
    digest << "missing\0#{root_index}\0"
    next
  end

  entries = if File.directory?(root) && !File.symlink?(root)
              Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
                .reject { |entry| [".", ".."].include?(File.basename(entry)) }
                .sort
            else
              [root]
            end
  entries.each do |entry|
    relative = entry == root ? "." : entry.delete_prefix(root + File::SEPARATOR)
    stat = File.lstat(entry)
    digest << "entry\0#{root_index}\0#{relative}\0#{stat.mode}\0"
    if stat.symlink?
      digest << "link\0#{File.readlink(entry)}\0"
    elsif stat.file?
      digest << "file\0#{File.binread(entry)}\0"
    elsif stat.directory?
      digest << "directory\0"
    else
      digest << "special\0"
    end
  end
end

puts digest.hexdigest
RUBY
}

validate_toolchain() {
  stage "Validate macOS, Xcode, Flutter and repository inputs"
  [[ "$(uname -s)" == "Darwin" ]] || fail "the iOS gate requires macOS"
  for command in find git rg ruby sed swift tail wc xcodebuild xcrun; do
    require_command "$command"
  done
  for file in \
    "$CORE/Package.swift" \
    "$UI/Package.swift" \
    "$ADAPTER/Package.swift" \
    "$CONTRACT" \
    "$VECTOR_TEST" \
    "$ADAPTER_TOOL/verify-core-tests.sh" \
    "$ADAPTER_TOOL/verify-host-route.sh" \
    "$ADAPTER_TOOL/test-safe-workspace-copy.sh" \
    "$ADAPTER_TOOL/copy-safe-workspace.sh" \
    "$ADAPTER_TOOL/safe-rsync-copy.sh" \
    "$ADAPTER_TOOL/Package.core-tests.swift"; do
    require_file "$file"
  done

  xcrun --find simctl >/dev/null
  xcrun --sdk iphonesimulator --show-sdk-path >/dev/null

  local flutter_json
  local flutter_version
  local flutter_root
  flutter_json="$(TOOL_WORKDIR="$ROOT/app" bash "$ROOT/scripts/flutter-tool.sh" --version --machine)"
  flutter_version="$(ruby -rjson -e 'puts JSON.parse($stdin.read).fetch("flutterVersion", "")' <<<"$flutter_json")"
  flutter_root="$(ruby -rjson -e 'puts JSON.parse($stdin.read).fetch("flutterRoot", "")' <<<"$flutter_json")"
  [[ "$flutter_version" == "3.41.9" ]] ||
    fail "expected Flutter 3.41.9, got ${flutter_version:-unknown}"
  [[ "$flutter_root" == /* && -d "$flutter_root" && ! -L "$flutter_root" ]] ||
    fail "reviewed Flutter SDK root is unavailable or unsafe"
  FLUTTER_EXECUTABLE="$flutter_root/bin/flutter"
  [[ -f "$FLUTTER_EXECUTABLE" && -x "$FLUTTER_EXECUTABLE" && ! -L "$FLUTTER_EXECUTABLE" ]] ||
    fail "reviewed Flutter executable is unavailable or unsafe"
  FLUTTER_ROOT_PATH="$flutter_root"

  printf '[media-capture-ios] Flutter %s; %s\n' "$flutter_version" "$(xcodebuild -version | tr '\n' ' ')"
}

validate_reviewed_inputs() {
  stage "Validate reviewed executable build inputs"
  assert_file_digest 97d77536f4a712e0edc434520cf5b482a572a9864144abf1ad11944cbadf83e7 \
    "$CORE/Package.swift"
  assert_file_digest 1a711e736d41f6233f84176708de5698894650d3a8b7dcaf7464445c973bc570 \
    "$UI/Package.swift"
  assert_file_digest 228bb4d2af645fc0808e431cb089df25aebf8552960991c50035807034b095c7 \
    "$ADAPTER/Package.swift"
  assert_file_digest 45083c7e8012d3b91ac8c05f17702c8961d62862715a9be2433d3c5df1b3d97f \
    "$ADAPTER_TOOL/verify-core-tests.sh"
  assert_file_digest a590b38d5c3300aa3442ba512184c1c054311430776d663c2439fd9f556f1fcb \
    "$ADAPTER_TOOL/verify-host-route.sh"
  assert_file_digest 885ad48d3e82467b9d470ca59dfe59a993221041eee6cf86704f18b656ca009c \
    "$ADAPTER_TOOL/test-safe-workspace-copy.sh"
  assert_file_digest 31b87766922dbe7645e79e34bfa6f99dc536acfc932f9cec2959b5e0c9629aab \
    "$ADAPTER_TOOL/copy-safe-workspace.sh"
  assert_file_digest 8c3b52f4ba8b6ac41d9f3083e4628cedb6859d77748b9c328bac8d6ae5df374f \
    "$ADAPTER_TOOL/safe-rsync-copy.sh"
  assert_file_digest a036e93056061c5789da0d020d8b4835c89cb7c18e4915ec822bb42f0c3a8d20 \
    "$ADAPTER_TOOL/Package.core-tests.swift"
  printf '%s\n' '[media-capture-ios] Reviewed manifest and helper digests passed.'
}

validate_package_graph() {
  stage "Validate Swift Package graph and import boundaries"

  assert_exact_package_graph

  assert_import_allowlist \
    "$CORE/Sources/MediaCapture" \
    'AVFoundation,CoreGraphics,Darwin,Foundation,ImageIO,MobileCoreServices,Security'
  assert_import_allowlist \
    "$CORE/Sources/MediaCaptureAppleRendering" \
    'AVFoundation,Foundation,MediaCapture,UIKit'
  assert_import_allowlist \
    "$UI/Sources/MediaCaptureUI" \
    'Foundation,MediaCapture,MediaCaptureAppleRendering,UIKit'
  assert_import_allowlist \
    "$ADAPTER/Sources/MediaCaptureBridgeCore" \
    'AVFoundation,CoreFoundation,Darwin,Foundation,MediaCapture,MediaCaptureUI,Security,UIKit'
  assert_import_allowlist \
    "$ADAPTER/Sources/app_media_capture_bridge" \
    'Flutter,MediaCaptureBridgeCore,UIKit'

  printf '%s\n' '[media-capture-ios] Package graph and import allowlists passed.'
}

validate_contract_vectors() {
  stage "Validate Wire V3 transfer limits and shared file URI vectors"
  ruby -rjson - "$CONTRACT" "$VECTOR_TEST" <<'RUBY'
contract = JSON.parse(File.read(ARGV.fetch(0)))
source = File.read(ARGV.fetch(1))

abort "unexpected Wire version" unless contract.fetch("wireVersion") == 3
capability = contract.fetch("capability")
abort "unexpected Capability compatibility" unless capability.fetch("compatibleCapabilityVersions") == [4]
store = contract.fetch("transferStore")
limits = store.fetch("limits")
result = store.fetch("resultPolicy")
uri_policy = store.fetch("fileUriPolicy")

expected_limits = {
  "maxFileBytes" => 52_428_800,
  "ttlSeconds" => 300,
  "maxActiveExportsPerEngineAttachment" => 4,
  "maxActiveBytesPerEngineAttachment" => 104_857_600,
  "releaseTombstoneSeconds" => 300,
  "maxReleaseTombstones" => 4_096,
}
expected_limits.each do |key, value|
  abort "unexpected transfer limit #{key}" unless limits.fetch(key) == value
end
abort "result byte limit drift" unless result.fetch("maxByteLength") == limits.fetch("maxFileBytes")
abort "unexpected file URI length limit" unless uri_policy.fetch("maxLength") == 4_096
abort "file URI must be ASCII percent encoded" unless uri_policy.fetch("serialization") == "ascii_percent_encoded"

vectors = store.fetch("fileUriGoldenVectors")
abort "expected 18 file URI vectors" unless vectors.length == 18
abort "duplicate file URI vector id" unless vectors.map { |item| item.fetch("id") }.uniq.length == vectors.length
expected = vectors.map { |item| [item.fetch("uri"), item.fetch("valid")] }
match = source.match(/func testCanonicalFileURIMatchesSharedGoldenVectors\(\)(?: throws)? \{(?<body>.*?)\n    \}\n\n    func/m)
abort "Swift golden vector test body is missing" unless match
actual = match[:body].scan(/\("([^"]*)", (true|false)\)/).map { |uri, valid| [uri, valid == "true"] }
abort "Swift file URI vectors drifted from the shared Contract" unless actual == expected

length_vectors = store.fetch("fileUriLengthGoldenVectors")
expected_lengths = length_vectors.map { |item| [item.fetch("totalLength"), item.fetch("valid")] }
abort "unexpected file URI length vectors" unless expected_lengths == [[4_096, true], [4_097, false]]
abort "Swift maximum URI construction drifted" unless source.include?('String(repeating: "a", count: 4_088)')
abort "Swift maximum URI assertion drifted" unless source.include?('maximum.utf8.count, 4_096')
abort "Swift over-maximum URI assertion drifted" unless source.include?('maximum + "a"')

puts "[media-capture-ios] Wire V3/Capability V4 limits and 20 shared URI vectors passed."
RUBY
}

validate_test_matrix() {
  stage "Validate lifecycle, rendering, UI and Adapter regression matrix"

  bash "$ADAPTER_TOOL/verify-core-tests.sh" --self-test-result-policy

  local core_tests="$CORE/Tests"
  local ui_tests="$UI/Tests"
  local adapter_tests="$ADAPTER/Tests"

  require_test "$core_tests" testSingleActiveSessionAndIdempotentCancellation
  require_test "$core_tests" testOperationCompletionIsExactlyOnce
  require_test "$core_tests" testConcreteSurfacePipelineReplacesAndRejectsStaleGeneration
  require_test "$core_tests" testBackgroundRevokesBothAttachmentKinds
  require_test "$core_tests" testRotationInvalidatesPendingLiveMountBeforeSurfaceMutation
  require_test "$core_tests" testLiveOwnerDestroyRevokesAndDetachesBinding
  require_test "$core_tests" testLiveSourceMountsPreviewLayerAndCleanupDisconnectsIt
  require_test "$core_tests" testLiveSourceConvertsViewPointThroughPreviewLayer
  require_test "$core_tests" testPhotoSourceMountsDecodedContentAndCleanupClearsIt
  require_test "$core_tests" testVideoSourceMountsPlayerLayerAndCleanupClearsPlayer
  require_test "$core_tests" testBoundsAndCallerCopySurviveSourceRelease
  require_test "$core_tests" testVideoThumbnailReceivesBoundedDecodeRequestAndDeterministicPosterTarget
  require_test "$core_tests" testRecordingStartFailureReleasesConfiguredMicrophoneInput
  require_test "$core_tests" testCancellingRecordingStartReleasesMicrophoneInputOnce
  require_test "$core_tests" testStopRecordingFailureReleasesMicrophoneInputOnce
  require_test "$core_tests" testConcurrentCancelAndStopReleaseMicrophoneInputOnce
  require_test "$core_tests" testRetakeCommitsReadyStateBeforeAsynchronousFileDeletion

  require_test "$ui_tests" testPresentationRegistryRejectsConcurrentOwnerAndAdvancesGeneration
  require_test "$ui_tests" testStartPermissionFailureIsNotReportedAsCancellation
  require_test "$ui_tests" testSessionFailureIsNotReportedAsCancellation
  require_test "$ui_tests" testDismissIsCancelledAndExactlyOnce
  require_test "$ui_tests" testViewControllerDeinitTriggersSystemInterruptionCleanup
  require_test "$ui_tests" testRotationAndForegroundUseStrictlyNewSurfaceGenerations
  require_test "$ui_tests" testPhotoPreviewConfirmCompletesAfterSurfaceCleanup
  require_test "$ui_tests" testFocusUsesRenderDevicePointConversion

  require_test "$adapter_tests" testDirectOperationsCoverFullBaseLifecycleOnMainActor
  require_test "$adapter_tests" testPresentationThreeOutcomesConflictAndDismissAreDistinct
  require_test "$adapter_tests" testEngineDetachDeletesActiveTransferBeforeCompletingBoundary
  require_test "$adapter_tests" testOwnerBoundaryReleasesControllerWhenPresentationAwaitNeverSettles
  require_test "$adapter_tests" testTransferTTLDeletesFileAndInvalidatesHandle
  require_test "$adapter_tests" testRootReplacementCannotRedirectCommitOrURI

  local core_count
  local ui_count
  local adapter_count
  core_count="$(rg -n '^[[:space:]]{4}func test[A-Za-z0-9_]+\(' "$core_tests" --glob '*.swift' | wc -l | tr -d ' ')"
  ui_count="$(rg -n '^[[:space:]]{4}func test[A-Za-z0-9_]+\(' "$ui_tests" --glob '*.swift' | wc -l | tr -d ' ')"
  adapter_count="$(rg -n '^[[:space:]]{4}func test[A-Za-z0-9_]+\(' "$adapter_tests" --glob '*.swift' | wc -l | tr -d ' ')"
  [[ "$core_count" -eq 107 ]] || fail "expected exactly 107 Core/Rendering XCTest methods"
  [[ "$ui_count" -eq 52 ]] || fail "expected exactly 52 UI XCTest methods"
  [[ "$adapter_count" -eq 69 ]] || fail "expected exactly 69 Bridge Core XCTest methods"

  printf '[media-capture-ios] XCTest source matrix: Core/Rendering %s, UI %s, Bridge Core %s.\n' \
    "$core_count" "$ui_count" "$adapter_count"
}

run_generic_compile() {
  local package="$1"
  local scheme="$2"
  local slug="$3"
  local log="$TEMP_ROOT/generic-$slug.log"
  local status

  set +e
  (cd "$package" && xcodebuild \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' \
    -sdk iphonesimulator \
    -configuration Debug \
    -derivedDataPath "$TEMP_ROOT/DerivedData-$slug" \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_STRICT_CONCURRENCY=complete \
    build) >"$log" 2>&1
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    show_failure "$log"
    fail "$scheme generic iOS Simulator SDK compile failed"
  fi
  assert_no_concurrency_warnings "$log"
  rg -q '\*\* BUILD SUCCEEDED \*\*' "$log" || fail "$scheme did not report BUILD SUCCEEDED"
  printf '[media-capture-ios] %s generic iOS Simulator SDK compile passed.\n' "$scheme"
}

run_generic_compiles() {
  stage "Compile every iOS package product against the generic Simulator SDK"
  run_generic_compile "$CORE" MediaCapture core
  run_generic_compile "$CORE" MediaCaptureAppleRendering rendering
  run_generic_compile "$UI" MediaCaptureUI ui
  run_generic_compile "$ADAPTER" MediaCaptureBridgeCore adapter
}

run_runtime_xcodebuild() {
  local package="$1"
  local scheme="$2"
  local slug="$3"
  local simulator_id="$4"
  local log="$TEMP_ROOT/runtime-$slug.log"
  local result_bundle="$TEMP_ROOT/runtime-$slug.xcresult"

  (cd "$package" && xcodebuild \
    test \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -destination-timeout 120 \
    -derivedDataPath "$TEMP_ROOT/RuntimeDerivedData-$slug" \
    -resultBundlePath "$result_bundle" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_STRICT_CONCURRENCY=complete) >"$log" 2>&1
}

runtime_result_has_test_failure() {
  local result_bundle="$1"
  local summary
  [[ -d "$result_bundle" ]] || return 1
  summary="$(xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --compact 2>/dev/null)" || return 1
  SUMMARY_JSON="$summary" ruby -rjson -e '
    summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
    exit(summary.fetch("failedTests", 0).to_i.positive? ? 0 : 1)
  ' >/dev/null 2>&1
}

emit_sanitized_runtime_failure_summary() {
  local result_bundle="$1"
  local scheme="$2"
  local summary
  if [[ ! -d "$result_bundle" ]]; then
    printf '[media-capture-ios] %s failure category: xcodebuild_or_simulator; no result bundle.\n' \
      "$scheme" >&2
    return
  fi
  if ! summary="$(xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --compact 2>/dev/null)"; then
    printf '[media-capture-ios] %s failure category: unreadable_result_bundle.\n' \
      "$scheme" >&2
    return
  fi
  SCHEME="$scheme" SUMMARY_JSON="$summary" ruby -rjson -e '
    summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
    scheme = ENV.fetch("SCHEME")
    scheme = "NativePackage" unless scheme.match?(/\A[A-Za-z0-9_.-]{1,80}\z/)
    result = summary.fetch("result", "Unknown").to_s
    result = "Unknown" unless result.match?(/\A[A-Za-z]+\z/)
    counts = %w[totalTestCount passedTests failedTests skippedTests expectedFailures].to_h do |key|
      value = summary.fetch(key, -1)
      [key, value.is_a?(Integer) ? value : -1]
    end
    warn "[media-capture-ios] #{scheme} failure category: test_result; result=#{result}; " \
         "total=#{counts.fetch("totalTestCount")}; passed=#{counts.fetch("passedTests")}; " \
         "failed=#{counts.fetch("failedTests")}; skipped=#{counts.fetch("skippedTests")}; " \
         "expected_failures=#{counts.fetch("expectedFailures")}."
  '
}

run_runtime_test() {
  local package="$1"
  local scheme="$2"
  local slug="$3"
  local simulator_id="$4"
  local expected_count="$5"
  local log="$TEMP_ROOT/runtime-$slug.log"
  local result_bundle="$TEMP_ROOT/runtime-$slug.xcresult"
  local status

  set +e
  run_runtime_xcodebuild "$package" "$scheme" "$slug" "$simulator_id"
  status=$?
  set -e

  if [[ "$status" -ne 0 ]] && ! runtime_result_has_test_failure "$result_bundle"; then
    printf '[media-capture-ios] %s infrastructure-class failure; retrying once.\n' \
      "$scheme" >&2
    if [[ -d "$result_bundle" ]]; then
      find -P "$result_bundle" -depth -delete
    fi
    set +e
    run_runtime_xcodebuild "$package" "$scheme" "$slug" "$simulator_id"
    status=$?
    set -e
  fi

  if [[ "$status" -ne 0 ]]; then
    emit_sanitized_runtime_failure_summary "$result_bundle" "$scheme"
    show_failure "$log"
    fail "$scheme Simulator runtime tests failed"
  fi
  assert_no_concurrency_warnings "$log"
  rg -q '\*\* TEST SUCCEEDED \*\*' "$log" || fail "$scheme did not report TEST SUCCEEDED"
  assert_xcresult_counts "$result_bundle" "$expected_count" "$scheme"
  printf '[media-capture-ios] %s Simulator runtime tests passed (%s tests, 0 skipped).\n' \
    "$scheme" "$expected_count"
}

assert_xcresult_counts() {
  local result_bundle="$1"
  local expected_count="$2"
  local scheme="$3"
  local summary
  if ! summary="$(xcrun xcresulttool get test-results summary --path "$result_bundle" --compact)"; then
    fail "$scheme xcresult summary could not be read"
  fi
  if ! SUMMARY_JSON="$summary" ruby -rjson - "$expected_count" "$scheme" <<'RUBY'
expected = Integer(ARGV.fetch(0), 10)
scheme = ARGV.fetch(1)
summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
valid = summary.fetch("result") == "Passed" &&
  summary.fetch("totalTestCount") == expected &&
  summary.fetch("passedTests") == expected &&
  summary.fetch("failedTests") == 0 &&
  summary.fetch("skippedTests") == 0 &&
  summary.fetch("expectedFailures") == 0
abort "#{scheme} test result counts drifted" unless valid
RUBY
  then
    fail "$scheme did not execute the exact reviewed test matrix"
  fi
}

run_simulator_tests() {
  stage "Run Simulator lifecycle and UI tests when an iPhone Simulator is available"
  local simulator_id
  simulator_id="$(xcrun simctl list devices available -j | ruby -rjson -e '
    devices = JSON.parse($stdin.read).fetch("devices").values.flatten
    device = devices.find { |item| item.fetch("name", "").start_with?("iPhone") }
    puts device.fetch("udid", "") if device
  ')"
  if [[ -z "$simulator_id" ]]; then
    printf '%s\n' '[media-capture-ios] No available iPhone Simulator; runtime XCTest layers were skipped.'
    return
  fi

  printf '%s\n' '[media-capture-ios] An available iPhone Simulator was selected; its identifier is intentionally redacted.'
  run_runtime_test "$CORE" MediaCapture-Package core-package "$simulator_id" 107
  run_runtime_test "$UI" MediaCaptureUI ui "$simulator_id" 52

  local adapter_log="$TEMP_ROOT/runtime-adapter.log"
  local adapter_result="$TEMP_ROOT/runtime-adapter.xcresult"
  local status
  set +e
  MEDIA_CAPTURE_CORE_TEST_RESULT_BUNDLE="$adapter_result" \
    MEDIA_CAPTURE_SIMULATOR_ID="$simulator_id" \
    bash "$ADAPTER_TOOL/verify-core-tests.sh" >"$adapter_log" 2>&1
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    show_failure "$adapter_log"
    fail "MediaCaptureBridgeCore Simulator runtime tests failed"
  fi
  assert_no_concurrency_warnings "$adapter_log"
  assert_xcresult_counts "$adapter_result" 69 MediaCaptureBridgeCore
  rg -q 'Bridge Core Simulator runtime tests passed with an exact 69-test result\.' "$adapter_log" ||
    fail "MediaCaptureBridgeCore helper did not confirm its reviewed result"
  printf '%s\n' '[media-capture-ios] MediaCaptureBridgeCore Simulator runtime tests passed (69 tests).'
}

verify_temporary_host_route() {
  stage "Verify safe-copy policy and temporary Flutter SwiftPM Host route"
  bash "$ADAPTER_TOOL/test-safe-workspace-copy.sh"

  local host_before
  local flutter_settings_before
  local host_after
  local flutter_settings_after
  host_before="$(path_digest "$REAL_HOST_IOS" "$REAL_HOST_PUBSPEC")"
  flutter_settings_before="$(path_digest "$HOME/.flutter_settings")"

  local host_log="$TEMP_ROOT/temporary-host.log"
  local status
  set +e
  MEDIA_CAPTURE_FLUTTER_EXECUTABLE="$FLUTTER_EXECUTABLE" \
    MEDIA_CAPTURE_FLUTTER_ROOT="$FLUTTER_ROOT_PATH" \
    bash "$ADAPTER_TOOL/verify-host-route.sh" >"$host_log" 2>&1
  status=$?
  set -e

  host_after="$(path_digest "$REAL_HOST_IOS" "$REAL_HOST_PUBSPEC")"
  flutter_settings_after="$(path_digest "$HOME/.flutter_settings")"
  [[ "$host_after" == "$host_before" ]] || fail "temporary Host verification changed the real Demo Host"
  [[ "$flutter_settings_after" == "$flutter_settings_before" ]] ||
    fail "temporary Host verification changed the user Flutter configuration"

  if [[ "$status" -ne 0 ]]; then
    show_failure "$host_log"
    fail "temporary Flutter SwiftPM Host verification failed"
  fi
  assert_no_concurrency_warnings "$host_log"
  rg -q 'Media Capture temporary Flutter Host route verified\.' "$host_log" ||
    fail "temporary Host route did not confirm plugin discovery"
  printf '%s\n' '[media-capture-ios] Temporary Flutter Host no-codesign build and plugin discovery passed.'
  printf '%s\n' '[media-capture-ios] Real Demo Host and user Flutter configuration remained unchanged.'
}

main() {
  validate_toolchain
  validate_reviewed_inputs
  validate_package_graph
  validate_contract_vectors
  validate_test_matrix
  run_generic_compiles
  run_simulator_tests
  verify_temporary_host_route

  stage "Result"
  printf '%s\n' '[media-capture-ios] PASS'
  printf '%s\n' '[media-capture-ios] Remaining device-only checks: live camera frames, system permission UI, microphone, hardware interruption and performance.'
  printf '%s\n' '[media-capture-ios] The temporary Host route does not claim that the real Demo Runner is integrated.'
}

main "$@"
