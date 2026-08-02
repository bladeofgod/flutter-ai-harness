#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
SOURCE_WORKSPACE="$REPOSITORY_ROOT/app"
TEMPORARY_ROOT_ALIAS=$(mktemp -d "${TMPDIR:-/tmp}/media-capture-host.XXXXXX")
TEMPORARY_ROOT=$(cd "$TEMPORARY_ROOT_ALIAS" && pwd -P)
TEMPORARY_WORKSPACE="$TEMPORARY_ROOT/app"
BUILD_LOG="$TEMPORARY_ROOT/flutter-build.log"
ISOLATED_HOME="$TEMPORARY_ROOT/home"
ISOLATED_TMP="$TEMPORARY_ROOT/tmp"
ISOLATED_PUB_CACHE="$TEMPORARY_ROOT/pub-cache"
FLUTTER_EXECUTABLE="${MEDIA_CAPTURE_FLUTTER_EXECUTABLE:-}"
FLUTTER_ROOT="${MEDIA_CAPTURE_FLUTTER_ROOT:-}"

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
[[ "$FLUTTER_EXECUTABLE" == /* && -f "$FLUTTER_EXECUTABLE" && -x "$FLUTTER_EXECUTABLE" && ! -L "$FLUTTER_EXECUTABLE" ]] || {
  printf '%s\n' 'A reviewed Flutter executable is required.' >&2
  exit 1
}
[[ "$FLUTTER_ROOT" == /* && -d "$FLUTTER_ROOT" && ! -L "$FLUTTER_ROOT" ]] || {
  printf '%s\n' 'A reviewed Flutter SDK root is required.' >&2
  exit 1
}
mkdir -p "$TEMPORARY_WORKSPACE" "$ISOLATED_HOME" "$ISOLATED_TMP" "$ISOLATED_PUB_CACHE"
chmod 700 "$ISOLATED_HOME" "$ISOLATED_TMP" "$ISOLATED_PUB_CACHE"
bash "$SCRIPT_DIR/copy-safe-workspace.sh" "$SOURCE_WORKSPACE" "$TEMPORARY_WORKSPACE"

TEMPORARY_PUBSPEC="$TEMPORARY_WORKSPACE/apps/demo/pubspec.yaml"
ruby -ryaml -e '
  path = ARGV.fetch(0)
  manifest = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
  flutter = manifest["flutter"] ||= {}
  config = flutter["config"] ||= {}
  config["enable-swift-package-manager"] = true
  File.write(path, YAML.dump(manifest))
' "$TEMPORARY_PUBSPEC"

ruby -ryaml -e '
  manifest = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
  enabled = manifest.dig("flutter", "config", "enable-swift-package-manager")
  abort "temporary SwiftPM project configuration is missing" unless enabled == true
' "$TEMPORARY_PUBSPEC"

status=0
SANITIZED_ENV=(
  "CI=true"
  "COCOAPODS_DISABLE_STATS=true"
  "DART_SUPPRESS_ANALYTICS=true"
  "FLUTTER_ROOT=$FLUTTER_ROOT"
  "FLUTTER_SUPPRESS_ANALYTICS=true"
  "HOME=$ISOLATED_HOME"
  "LANG=${LANG:-en_US.UTF-8}"
  "LC_ALL=${LC_ALL:-en_US.UTF-8}"
  "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  "PUB_CACHE=$ISOLATED_PUB_CACHE"
  "TMPDIR=$ISOLATED_TMP"
  "XDG_CACHE_HOME=$ISOLATED_HOME/.cache"
  "XDG_CONFIG_HOME=$ISOLATED_HOME/.config"
)
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  SANITIZED_ENV+=("DEVELOPER_DIR=$DEVELOPER_DIR")
fi
if (cd "$TEMPORARY_WORKSPACE/apps/demo" && \
  env -i "${SANITIZED_ENV[@]}" "$FLUTTER_EXECUTABLE" build ios --debug --no-codesign) \
  >"$BUILD_LOG" 2>&1; then
  status=0
else
  status=$?
fi

if [[ "$status" -ne 0 ]]; then
  printf '%s\n' 'Temporary Flutter Host build failed; private build output was not emitted.' >&2
  exit "$status"
fi

GENERATED_PACKAGE="$TEMPORARY_WORKSPACE/apps/demo/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [[ ! -f "$GENERATED_PACKAGE" ]] || ! rg -q 'app_media_capture_bridge' "$GENERATED_PACKAGE"; then
  printf '%s\n' 'Flutter Host build did not discover the Media Capture Swift package.' >&2
  exit 1
fi

printf '%s\n' 'Media Capture temporary Flutter Host route verified.'
