#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
SOURCE_PACKAGE="$SCRIPT_DIR/../app_media_capture_bridge"
TEMPORARY_ROOT_ALIAS=$(mktemp -d "${TMPDIR:-/tmp}/media-capture-core-tests.XXXXXX")
TEMPORARY_ROOT=$(cd "$TEMPORARY_ROOT_ALIAS" && pwd -P)
TEMPORARY_APP="$TEMPORARY_ROOT/app"
TEMPORARY_PACKAGE="$TEMPORARY_APP/packages/app_media_capture_bridge/ios/app_media_capture_bridge"
GOLDEN_VECTORS_SOURCE="$REPOSITORY_ROOT/app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json"
TEST_LOG="$TEMPORARY_ROOT/xcodebuild-test.log"
RESULT_BUNDLE="${MEDIA_CAPTURE_CORE_TEST_RESULT_BUNDLE:-$TEMPORARY_ROOT/TestResults.xcresult}"

cleanup() {
  if [[ -d "$TEMPORARY_ROOT_ALIAS" ]]; then
    find -P "$TEMPORARY_ROOT_ALIAS" -depth -delete
  fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

chmod 700 "$TEMPORARY_ROOT"
if [[ "$RESULT_BUNDLE" != /* || -e "$RESULT_BUNDLE" || -L "$RESULT_BUNDLE" ]]; then
  printf '%s\n' 'Bridge Core result bundle path must be a new absolute path.' >&2
  exit 1
fi
RESULT_PARENT=$(dirname "$RESULT_BUNDLE")
[[ -d "$RESULT_PARENT" && ! -L "$RESULT_PARENT" ]] || {
  printf '%s\n' 'Bridge Core result bundle parent is unavailable or unsafe.' >&2
  exit 1
}
[[ -f "$GOLDEN_VECTORS_SOURCE" && ! -L "$GOLDEN_VECTORS_SOURCE" ]] || {
  printf '%s\n' 'Cross-runtime golden vectors are missing or unsafe.' >&2
  exit 1
}
mkdir -p "$TEMPORARY_PACKAGE/Sources" "$TEMPORARY_PACKAGE/Tests"

bash "$SCRIPT_DIR/safe-rsync-copy.sh" \
  "$SOURCE_PACKAGE/Sources/MediaCaptureBridgeCore/" \
  "$TEMPORARY_PACKAGE/Sources/MediaCaptureBridgeCore/"
bash "$SCRIPT_DIR/safe-rsync-copy.sh" \
  "$SOURCE_PACKAGE/Tests/MediaCaptureBridgeCoreTests/" \
  "$TEMPORARY_PACKAGE/Tests/MediaCaptureBridgeCoreTests/"
mkdir -p "$TEMPORARY_APP/native/ios"
bash "$SCRIPT_DIR/safe-rsync-copy.sh" \
  "$REPOSITORY_ROOT/app/native/ios/MediaCapture/" \
  "$TEMPORARY_APP/native/ios/MediaCapture/" \
  --exclude=.build --exclude=.swiftpm
bash "$SCRIPT_DIR/safe-rsync-copy.sh" \
  "$REPOSITORY_ROOT/app/native/ios/MediaCaptureUI/" \
  "$TEMPORARY_APP/native/ios/MediaCaptureUI/" \
  --exclude=.build --exclude=.swiftpm
mkdir -p "$TEMPORARY_APP/packages/app_media_capture_bridge/test/contracts"
bash "$SCRIPT_DIR/safe-rsync-copy.sh" \
  "$REPOSITORY_ROOT/app/packages/app_media_capture_bridge/test/contracts/" \
  "$TEMPORARY_APP/packages/app_media_capture_bridge/test/contracts/"
cp -p "$SCRIPT_DIR/Package.core-tests.swift" "$TEMPORARY_PACKAGE/Package.swift"

REQUESTED_SIMULATOR_ID="${MEDIA_CAPTURE_SIMULATOR_ID:-}"
SIMULATOR_ID=$(xcrun simctl list devices available -j | \
  REQUESTED_SIMULATOR_ID="$REQUESTED_SIMULATOR_ID" ruby -rjson -e '
  devices = JSON.parse($stdin.read).fetch("devices").values.flatten
  requested = ENV.fetch("REQUESTED_SIMULATOR_ID")
  unless requested.empty? || requested.match?(/\A[0-9A-Fa-f-]{36}\z/)
    abort "Requested iPhone Simulator identifier is invalid."
  end
  iphones = devices.select { |item| item.fetch("name", "").start_with?("iPhone") }
  device = if requested.empty?
             iphones.first
           else
             iphones.find { |item| item.fetch("udid", "") == requested }
           end
  abort "Requested iPhone Simulator is unavailable." if !requested.empty? && device.nil?
  puts device.fetch("udid", "") if device
')

run_bridge_core_tests() {
  (cd "$TEMPORARY_PACKAGE" && xcodebuild \
    -scheme app_media_capture_bridge_core_tests \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -destination-timeout 120 \
    -parallel-testing-enabled NO \
    -derivedDataPath "$TEMPORARY_ROOT/DerivedData" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    test) >"$TEST_LOG" 2>&1
}

summary_has_test_failure() {
  local summary="$1"
  SUMMARY_JSON="$summary" ruby -rjson -e '
    summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
    exit(summary.fetch("failedTests", 0).to_i.positive? ? 0 : 1)
  ' >/dev/null 2>&1
}

summary_is_exact_success() {
  local summary="$1"
  SUMMARY_JSON="$summary" ruby -rjson -e '
    summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
    valid = summary.fetch("result") == "Passed" &&
      summary.fetch("totalTestCount") == 69 &&
      summary.fetch("passedTests") == 69 &&
      summary.fetch("failedTests") == 0 &&
      summary.fetch("skippedTests") == 0 &&
      summary.fetch("expectedFailures") == 0
    exit(valid ? 0 : 1)
  ' >/dev/null 2>&1
}

result_has_test_failure() {
  local summary
  [[ -d "$RESULT_BUNDLE" ]] || return 1
  summary=$(xcrun xcresulttool get test-results summary \
    --path "$RESULT_BUNDLE" --compact 2>/dev/null) || return 1
  summary_has_test_failure "$summary"
}

emit_sanitized_summary() {
  local summary="$1"
  local tests="${2:-}"
  local fallback_category="${3:-xcodebuild_or_simulator}"
  SUMMARY_JSON="$summary" FALLBACK_CATEGORY="$fallback_category" ruby -rjson -e '
    summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
    result = summary.fetch("result", "Unknown").to_s
    result = "Unknown" unless result.match?(/\A[A-Za-z]+\z/)
    counts = %w[totalTestCount passedTests failedTests skippedTests expectedFailures].to_h do |key|
      value = summary.fetch(key, -1)
      [key, value.is_a?(Integer) ? value : -1]
    end
    category = if counts.fetch("totalTestCount").positive? || counts.fetch("failedTests").positive?
                 "test_result"
               else
                 ENV.fetch("FALLBACK_CATEGORY")
               end
    warn "Bridge Core failure category: #{category}; result=#{result}; " \
         "total=#{counts.fetch("totalTestCount")}; passed=#{counts.fetch("passedTests")}; " \
         "failed=#{counts.fetch("failedTests")}; skipped=#{counts.fetch("skippedTests")}; " \
         "expected_failures=#{counts.fetch("expectedFailures")}."
  '
  if [[ -n "$tests" ]]; then
    TESTS_JSON="$tests" ruby -rjson -e '
      root = JSON.parse(ENV.fetch("TESTS_JSON"))
      identifiers = []
      visit = lambda do |value|
        case value
        when Hash
          status = [value["testStatus"], value["status"], value["result"]]
            .compact.map(&:to_s).find { |item| item.downcase.include?("fail") }
          if status && value["nodeType"] == "Test Case"
            identifier = value["testIdentifierString"] || value["testIdentifier"] ||
              value["identifier"] || value["name"]
            if identifier.is_a?(String) &&
               identifier.match?(/\A[A-Za-z0-9_.\/()\[\]-]{1,200}\z/) &&
               identifier.downcase.include?("test")
              identifiers << identifier
            end
          end
          value.each_value { |child| visit.call(child) }
        when Array
          value.each { |child| visit.call(child) }
        end
      end
      visit.call(root)
      identifiers.uniq.first(5).each { |identifier| warn "Bridge Core failed test: #{identifier}" }
    '
  fi
}

sanitized_xcodebuild_failure_category() {
  if rg -q \
    'Testing cancelled because the build failed|The following build commands failed|\*\* BUILD FAILED \*\*' \
    "$TEST_LOG"; then
    printf '%s\n' 'test_target_build'
  elif rg -i -q \
    'failed to (boot|launch|prepare).*(simulator|test runner)|unable to (boot|launch).*(simulator|test runner)|lost connection.*simulator' \
    "$TEST_LOG"; then
    printf '%s\n' 'simulator_runtime'
  elif rg -i -q \
    'unable to find a destination|destination.*(not found|unavailable)|ineligible destinations' \
    "$TEST_LOG"; then
    printf '%s\n' 'destination_unavailable'
  else
    printf '%s\n' 'xcodebuild_or_simulator'
  fi
}

emit_sanitized_failure_summary() {
  local summary
  local tests=''
  local fallback_category
  fallback_category="$(sanitized_xcodebuild_failure_category)"
  if [[ ! -d "$RESULT_BUNDLE" ]]; then
    printf 'Bridge Core failure category: %s; no result bundle.\n' \
      "$fallback_category" >&2
    return
  fi
  if ! summary=$(xcrun xcresulttool get test-results summary \
    --path "$RESULT_BUNDLE" --compact 2>/dev/null); then
    printf '%s\n' 'Bridge Core failure category: unreadable_result_bundle.' >&2
    return
  fi
  tests=$(xcrun xcresulttool get test-results tests \
    --path "$RESULT_BUNDLE" --compact 2>/dev/null) || tests=''
  emit_sanitized_summary "$summary" "$tests" "$fallback_category"
}

verify_result_policy_fixture() {
  local passed='{"result":"Passed","totalTestCount":69,"passedTests":69,"failedTests":0,"skippedTests":0,"expectedFailures":0}'
  local drifted='{"result":"Passed","totalTestCount":69,"passedTests":68,"failedTests":0,"skippedTests":1,"expectedFailures":0}'
  local failed='{"result":"Failed","totalTestCount":69,"passedTests":68,"failedTests":1,"skippedTests":0,"expectedFailures":0}'
  local tests='{"testNodes":[{"name":"BridgeTests","nodeType":"Test Suite","result":"Failed","children":[{"name":"testSafeFailure()","nodeType":"Test Case","result":"Failed","failureText":"/private/secret 00000000-0000-0000-0000-000000000000"}]}]}'
  local output

  summary_is_exact_success "$passed" || return 1
  if summary_is_exact_success "$drifted"; then return 1; fi
  summary_has_test_failure "$failed" || return 1
  if summary_has_test_failure "$drifted"; then return 1; fi
  output=$(emit_sanitized_summary "$failed" "$tests" 2>&1)
  [[ "$output" == *'Bridge Core failed test: testSafeFailure()'* ]] || return 1
  [[ "$output" != *'/private/secret'* ]] || return 1
  [[ "$output" != *'00000000-0000-0000-0000-000000000000'* ]] || return 1
}

if [[ "${1:-}" == '--self-test-result-policy' ]]; then
  verify_result_policy_fixture || {
    printf '%s\n' 'Bridge Core result policy fixture failed.' >&2
    exit 1
  }
  printf '%s\n' 'Bridge Core result policy fixture passed.'
  exit 0
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  printf '%s\n' 'No available iPhone Simulator; Bridge Core runtime tests were skipped.'
  exit 0
fi

status=0
if run_bridge_core_tests; then
  status=0
else
  status=$?
fi

if [[ "$status" -ne 0 ]] && ! result_has_test_failure; then
  printf '%s\n' 'Bridge Core infrastructure-class failure; retrying once.' >&2
  if [[ -d "$RESULT_BUNDLE" ]]; then
    find -P "$RESULT_BUNDLE" -depth -delete
  fi
  if run_bridge_core_tests; then
    status=0
  else
    status=$?
  fi
fi

if [[ "$status" -ne 0 ]]; then
  emit_sanitized_failure_summary
  printf '%s\n' 'Bridge Core Simulator runtime tests failed; private build output was not emitted.' >&2
  exit "$status"
fi

if ! SUMMARY=$(xcrun xcresulttool get test-results summary \
  --path "$RESULT_BUNDLE" --compact 2>/dev/null); then
  emit_sanitized_failure_summary
  printf '%s\n' 'Bridge Core Simulator runtime tests failed; private build output was not emitted.' >&2
  exit 1
fi
if ! summary_is_exact_success "$SUMMARY"; then
  emit_sanitized_failure_summary
  printf '%s\n' 'Bridge Core Simulator runtime tests failed; private build output was not emitted.' >&2
  exit 1
fi
printf '%s\n' 'Bridge Core Simulator runtime tests passed with an exact 69-test result.'
