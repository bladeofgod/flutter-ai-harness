#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-hook.XXXXXX")"

cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

cd "$FIXTURE_ROOT"
git init -q
git config user.name test
git config user.email test@example.com
mkdir -p lib scripts/git-hooks
cp "$ROOT/scripts/git-hooks/pre-commit" scripts/git-hooks/pre-commit
printf '%s\n' '#!/usr/bin/env bash' 'exec dart "$@"' > scripts/dart-tool.sh
printf '%s\n' '.PHONY: proto-check' 'proto-check:' $'\t@true' > Makefile

printf '%s\n' 'void main() {' '  print(1);' '}' > lib/example.dart
git add .
git commit -qm initial

printf '%s\n' 'void main(){print(2);}' > lib/example.dart
git add lib/example.dart
printf '%s\n' 'void main() {' '  print(2);' '}' > lib/example.dart
if bash scripts/git-hooks/pre-commit >/dev/null 2>&1; then
  echo "错误：pre-commit 未拒绝暂存区中的未格式化 Dart。" >&2
  exit 1
fi

git add lib/example.dart
printf '%s\n' 'void main(){print(3);}' > lib/example.dart
bash scripts/git-hooks/pre-commit >/dev/null

echo "[hook-test] pre-commit 使用 Git 暂存内容。"
