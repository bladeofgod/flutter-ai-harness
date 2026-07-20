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
mkdir -p lib scripts/git-hooks custom-hooks
cp "$ROOT/scripts/git-hooks/pre-commit" scripts/git-hooks/pre-commit
cp "$ROOT/scripts/git-hooks/pre-push" scripts/git-hooks/pre-push
cp "$ROOT/scripts/git-hooks/install.sh" scripts/git-hooks/install.sh
cp "$ROOT/scripts/git-hooks/uninstall.sh" scripts/git-hooks/uninstall.sh
printf '%s\n' '#!/usr/bin/env bash' 'exec dart "$@"' > scripts/dart-tool.sh
printf '%s\n' '.PHONY: proto-check' 'proto-check:' $'\t@true' > Makefile

printf '%s\n' 'void main() {' '  print(1);' '}' > lib/example.dart
git add .
git commit -qm initial

bash scripts/git-hooks/install.sh >/dev/null
[[ "$(git config --local --get core.hooksPath)" == "scripts/git-hooks" ]]
bash scripts/git-hooks/install.sh >/dev/null
bash scripts/git-hooks/uninstall.sh >/dev/null
if git config --local --get core.hooksPath >/dev/null 2>&1; then
  echo "错误：Git Hook 卸载后仍保留仓库 core.hooksPath。" >&2
  exit 1
fi

git config --local core.hooksPath custom-hooks
if bash scripts/git-hooks/install.sh >/dev/null 2>&1; then
  echo "错误：Git Hook 安装覆盖了已有 core.hooksPath。" >&2
  exit 1
fi
if [[ "$(git config --local --get core.hooksPath)" != "custom-hooks" ]]; then
  echo "错误：Git Hook 安装修改了已有 core.hooksPath。" >&2
  exit 1
fi
git config --local --unset core.hooksPath

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

echo "[hook-test] Git Hook 安装冲突与 pre-commit 暂存内容检查通过。"
