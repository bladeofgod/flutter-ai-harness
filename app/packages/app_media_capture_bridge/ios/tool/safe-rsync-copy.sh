#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  printf '%s\n' 'Usage: safe-rsync-copy.sh <source> <target> [additional-rsync-args...]' >&2
  exit 64
fi

SOURCE=$1
TARGET=$2
shift 2

[[ -d "$SOURCE" && ! -L "$SOURCE" ]] || {
  printf '%s\n' 'Source must be a non-symlink directory.' >&2
  exit 1
}
SOURCE_ROOT=${SOURCE%/}

SAFE_EXCLUDES=(
  --exclude=.dart_tool
  --exclude=.DS_Store
  --exclude='.env*'
  --exclude=.git
  --exclude=.hg
  --exclude=.idea
  --exclude=.netrc
  --exclude=.npmrc
  --exclude=.pypirc
  --exclude=.svn
  --exclude=.symlinks
  --exclude=build
  --exclude=DerivedData
  --exclude=ephemeral
  --exclude=Pods
  --exclude=xcuserdata
  --exclude='*.cer'
  --exclude='*.crt'
  --exclude='*.der'
  --exclude='*.jks'
  --exclude='*.key'
  --exclude='*.keychain'
  --exclude='*.keychain-db'
  --exclude='*.keystore'
  --exclude='*.mobileprovision'
  --exclude='*.p12'
  --exclude='*.p8'
  --exclude='*.pem'
  --exclude='*.pfx'
  --exclude='*.pkcs12'
  --exclude='*.provisionprofile'
  --exclude=key.properties
  --exclude=local.properties
  --safe-links
)

CASE_INSENSITIVE_EXCLUDES=()
while IFS= read -r -d '' entry; do
  relative=${entry#"$SOURCE_ROOT"/}
  leaf=${entry##*/}
  lower_leaf=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$leaf")
  sensitive=0
  case "$lower_leaf" in
    .dart_tool | .ds_store | .git | .hg | .idea | .netrc | .npmrc | .pypirc | \
      .svn | .symlinks | build | deriveddata | ephemeral | pods | xcuserdata | \
      key.properties | local.properties | .env*)
      sensitive=1
      ;;
    *.cer | *.crt | *.der | *.jks | *.key | *.keychain | *.keychain-db | \
      *.keystore | *.mobileprovision | *.p12 | *.p8 | *.pem | *.pfx | *.pkcs12 | \
      *.provisionprofile)
      sensitive=1
      ;;
    *secret*.xcconfig | *credential*.xcconfig | *signing*.xcconfig)
      sensitive=1
      ;;
  esac
  if [[ "$sensitive" -eq 1 ]]; then
    CASE_INSENSITIVE_EXCLUDES+=("--exclude=/$relative")
  fi
done < <(find -P "$SOURCE_ROOT" -mindepth 1 -print0)

if [[ "${#CASE_INSENSITIVE_EXCLUDES[@]}" -gt 0 ]]; then
  rsync -a "${SAFE_EXCLUDES[@]}" "${CASE_INSENSITIVE_EXCLUDES[@]}" \
    "$@" "$SOURCE" "$TARGET"
else
  rsync -a "${SAFE_EXCLUDES[@]}" "$@" "$SOURCE" "$TARGET"
fi
