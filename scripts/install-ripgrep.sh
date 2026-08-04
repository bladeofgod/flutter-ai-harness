#!/usr/bin/env bash
set -euo pipefail

umask 077

VERSION='15.1.0'
RELEASE_ROOT="https://github.com/BurntSushi/ripgrep/releases/download/$VERSION"

fail() {
  printf '[install-ripgrep] error: %s\n' "$*" >&2
  exit 1
}

for command in awk curl find install mkdir mktemp sed tar uname; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

platform="$(uname -s):$(uname -m)"
case "$platform" in
  Linux:x86_64)
    target='x86_64-unknown-linux-musl'
    expected_digest='1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599'
    ;;
  Darwin:arm64)
    target='aarch64-apple-darwin'
    expected_digest='378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715'
    ;;
  Darwin:x86_64)
    target='x86_64-apple-darwin'
    expected_digest='64811cb24e77cac3057d6c40b63ac9becf9082eedd54ca411b475b755d334882'
    ;;
  *) fail "unsupported runner platform: $platform" ;;
esac

[[ -n "${RUNNER_TEMP:-}" && "$RUNNER_TEMP" == /* && -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] ||
  fail 'RUNNER_TEMP must be an absolute, non-symlink directory'
[[ -n "${GITHUB_PATH:-}" && "$GITHUB_PATH" == /* && -f "$GITHUB_PATH" && ! -L "$GITHUB_PATH" ]] ||
  fail 'GITHUB_PATH must be an absolute, non-symlink file'

archive="ripgrep-$VERSION-$target.tar.gz"
download_root="$(mktemp -d "$RUNNER_TEMP/ripgrep-download.XXXXXX")"
install_root="$(mktemp -d "$RUNNER_TEMP/ripgrep-$VERSION.XXXXXX")"

cleanup() {
  find -P "$download_root" -depth -delete
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
  --connect-timeout 10 --max-time 90 --retry 2 --retry-all-errors --retry-delay 2 \
  --output "$download_root/$archive" \
  "$RELEASE_ROOT/$archive"

if command -v sha256sum >/dev/null 2>&1; then
  actual_digest="$(sha256sum "$download_root/$archive" | awk '{ print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
  actual_digest="$(shasum -a 256 "$download_root/$archive" | awk '{ print $1 }')"
else
  fail 'sha256sum or shasum is required'
fi
[[ "$actual_digest" == "$expected_digest" ]] || fail 'release archive SHA-256 mismatch'

tar -xzf "$download_root/$archive" -C "$download_root"
source_binary="$download_root/ripgrep-$VERSION-$target/rg"
[[ -f "$source_binary" && ! -L "$source_binary" ]] || fail 'release archive does not contain rg'

mkdir -p "$install_root/bin"
install -m 0755 "$source_binary" "$install_root/bin/rg"
[[ "$("$install_root/bin/rg" --version | sed -n '1p')" == "ripgrep $VERSION"* ]] ||
  fail 'installed ripgrep version mismatch'

printf '%s\n' "$install_root/bin" >> "$GITHUB_PATH"
printf '[install-ripgrep] ripgrep %s installed for %s\n' "$VERSION" "$target"
