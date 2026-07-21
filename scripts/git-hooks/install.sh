#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "错误：当前目录不在 Git 仓库中。" >&2
  exit 1
}

cd "$ROOT"
current="$(git config --get core.hooksPath || true)"
if [[ -n "$current" && "$current" != "scripts/git-hooks" ]]; then
  echo "错误：当前 core.hooksPath 已配置为 $current，未覆盖现有 Git Hook 工具链。" >&2
  exit 2
fi

if [[ -z "$current" ]]; then
  git config --local core.hooksPath scripts/git-hooks
fi
chmod +x scripts/git-hooks/pre-commit scripts/git-hooks/pre-push

echo "Git hooks 已就绪："
echo "  pre-commit：Dart 格式 + Proto 生成同步"
echo "  pre-push：Codex 适配同步检查 + 静态分析 + 仓库边界 lint"
