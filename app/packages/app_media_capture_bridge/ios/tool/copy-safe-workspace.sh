#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf '%s\n' 'Usage: copy-safe-workspace.sh <source-workspace> <target-workspace>' >&2
  exit 64
fi

SOURCE_WORKSPACE=$1
TARGET_WORKSPACE=$2
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for file in .fvmrc analysis_options.yaml pubspec.yaml pubspec.lock; do
  source="$SOURCE_WORKSPACE/$file"
  if [[ -L "$source" ]]; then
    printf 'Refusing symlinked workspace manifest: %s\n' "$file" >&2
    exit 1
  fi
  if [[ -f "$source" ]]; then
    cp -p "$source" "$TARGET_WORKSPACE/$file"
  fi
done

for directory in apps packages native; do
  bash "$SCRIPT_DIR/safe-rsync-copy.sh" \
    "$SOURCE_WORKSPACE/$directory/" \
    "$TARGET_WORKSPACE/$directory/"
done

ruby -e '
  root = File.realpath(ARGV.fetch(0))
  Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |entry|
    next unless File.symlink?(entry)
    target = File.realpath(entry)
    unless target.start_with?(root + File::SEPARATOR)
      abort "copied workspace contains an escaping symlink"
    end
  rescue Errno::ENOENT, Errno::ELOOP
    abort "copied workspace contains an invalid symlink"
  end
' "$TARGET_WORKSPACE"
