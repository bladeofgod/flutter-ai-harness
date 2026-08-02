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

SIMULATOR_ID=$(xcrun simctl list devices available -j | ruby -rjson -e '
  devices = JSON.parse($stdin.read).fetch("devices").values.flatten
  device = devices.find { |item| item.fetch("name", "").start_with?("iPhone") }
  puts device.fetch("udid", "") if device
')

if [[ -z "$SIMULATOR_ID" ]]; then
  printf '%s\n' 'No available iPhone Simulator; Bridge Core runtime tests were skipped.'
  exit 0
fi

status=0
if (cd "$TEMPORARY_PACKAGE" && xcodebuild \
  -scheme app_media_capture_bridge_core_tests \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$TEMPORARY_ROOT/DerivedData" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test) >"$TEST_LOG" 2>&1; then
  status=0
else
  status=$?
fi

if [[ "$status" -ne 0 ]]; then
  printf '%s\n' 'Bridge Core Simulator runtime tests failed; private build output was not emitted.' >&2
  exit "$status"
fi

SUMMARY=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --compact) || {
  printf '%s\n' 'Bridge Core xcresult summary could not be read.' >&2
  exit 1
}
SUMMARY_JSON="$SUMMARY" ruby -rjson - <<'RUBY'
summary = JSON.parse(ENV.fetch("SUMMARY_JSON"))
valid = summary.fetch("result") == "Passed" &&
  summary.fetch("totalTestCount") == 69 &&
  summary.fetch("passedTests") == 69 &&
  summary.fetch("failedTests") == 0 &&
  summary.fetch("skippedTests") == 0 &&
  summary.fetch("expectedFailures") == 0
abort "Bridge Core test result counts drifted" unless valid
RUBY
printf '%s\n' 'Bridge Core Simulator runtime tests passed with an exact 69-test result.'
