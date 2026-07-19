#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "错误：当前目录不在 Git 仓库中。" >&2
  exit 1
}

cd "$ROOT"
git config core.hooksPath scripts/git-hooks
chmod +x scripts/git-hooks/pre-commit scripts/git-hooks/pre-push

echo "Git hooks 已安装："
echo "  pre-commit：Dart 格式 + Proto 生成同步"
echo "  pre-push：静态分析 + 仓库边界 lint"
