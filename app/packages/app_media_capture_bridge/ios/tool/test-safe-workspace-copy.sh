#!/usr/bin/env bash
set -euo pipefail

umask 077
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPORARY_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/media-capture-copy-test.XXXXXX")

cleanup() {
  if [[ -d "$TEMPORARY_ROOT" ]]; then
    find -P "$TEMPORARY_ROOT" -depth -delete
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

SOURCE="$TEMPORARY_ROOT/source"
TARGET="$TEMPORARY_ROOT/target"
mkdir -p "$SOURCE/apps" "$SOURCE/packages" "$SOURCE/native" "$TARGET"
printf '%s\n' 'name: fixture' > "$SOURCE/pubspec.yaml"
printf '%s\n' 'safe' > "$SOURCE/packages/safe.txt"
ln -s safe.txt "$SOURCE/packages/safe-link"
printf '%s\n' 'fixture' > "$TEMPORARY_ROOT/outside.txt"
mkdir -p "$TEMPORARY_ROOT/outside-directory"
ln -s ../../outside.txt "$SOURCE/packages/escape-link"
ln -s "$TEMPORARY_ROOT/outside.txt" "$SOURCE/packages/absolute-escape-link"
ln -s ../../outside-directory "$SOURCE/packages/escape-directory-link"

for extension in cer crt der jks key keychain keychain-db keystore mobileprovision p12 p8 pem pfx pkcs12 provisionprofile; do
  printf '%s\n' 'fixture' > "$SOURCE/apps/credential.$extension"
done
for local_config in .netrc .npmrc .pypirc key.properties local.properties; do
  printf '%s\n' 'fixture' > "$SOURCE/apps/$local_config"
done
for environment_config in .env .env.local .envrc .envlocal; do
  printf '%s\n' 'fixture' > "$SOURCE/apps/$environment_config"
done
for mixed_case_sensitive in .ENV .Env.Local Signing.P12 Credential.PEM Secrets.xcconfig Profile.MobileProvision Export.Keychain-Db; do
  printf '%s\n' 'fixture' > "$SOURCE/apps/$mixed_case_sensitive"
done
mkdir -p "$SOURCE/packages/bridge/nested" "$SOURCE/native/Core/nested" "$SOURCE/native/UI/nested"
printf '%s\n' 'fixture' > "$SOURCE/packages/bridge/nested/.env.test"
printf '%s\n' 'fixture' > "$SOURCE/native/Core/nested/.envrc"
printf '%s\n' 'fixture' > "$SOURCE/native/UI/nested/.envlocal"

bash "$SCRIPT_DIR/copy-safe-workspace.sh" "$SOURCE" "$TARGET"

[[ -f "$TARGET/pubspec.yaml" ]]
[[ -L "$TARGET/packages/safe-link" ]]
[[ ! -e "$TARGET/packages/escape-link" ]]
[[ ! -e "$TARGET/packages/absolute-escape-link" ]]
[[ ! -e "$TARGET/packages/escape-directory-link" ]]
for extension in cer crt der jks key keychain keychain-db keystore mobileprovision p12 p8 pem pfx pkcs12 provisionprofile; do
  [[ ! -e "$TARGET/apps/credential.$extension" ]]
done
for local_config in .netrc .npmrc .pypirc key.properties local.properties; do
  [[ ! -e "$TARGET/apps/$local_config" ]]
done
for environment_config in .env .env.local .envrc .envlocal; do
  [[ ! -e "$TARGET/apps/$environment_config" ]]
done
for mixed_case_sensitive in .ENV .Env.Local Signing.P12 Credential.PEM Secrets.xcconfig Profile.MobileProvision Export.Keychain-Db; do
  [[ ! -e "$TARGET/apps/$mixed_case_sensitive" ]]
done
[[ ! -e "$TARGET/packages/bridge/nested/.env.test" ]]
[[ ! -e "$TARGET/native/Core/nested/.envrc" ]]
[[ ! -e "$TARGET/native/UI/nested/.envlocal" ]]

CHAIN_SOURCE="$TEMPORARY_ROOT/chain-source"
CHAIN_TARGET="$TEMPORARY_ROOT/chain-target"
mkdir -p "$CHAIN_SOURCE/apps" "$CHAIN_SOURCE/packages" "$CHAIN_SOURCE/native" "$CHAIN_TARGET"
printf '%s\n' 'name: chain-fixture' > "$CHAIN_SOURCE/pubspec.yaml"
ln -s ../../outside.txt "$CHAIN_SOURCE/packages/escape-link"
ln -s escape-link "$CHAIN_SOURCE/packages/chained-escape-link"
if bash "$SCRIPT_DIR/copy-safe-workspace.sh" "$CHAIN_SOURCE" "$CHAIN_TARGET" >/dev/null 2>&1; then
  printf '%s\n' 'Chained escaping symlink was not rejected.' >&2
  exit 1
fi

printf '%s\n' 'Safe workspace copy fixture passed.'
