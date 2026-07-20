#!/usr/bin/env bash
set -euo pipefail

current="$(git config --local --get core.hooksPath || true)"
if [[ "$current" == "scripts/git-hooks" ]]; then
  git config --local --unset core.hooksPath
  echo "Git hooks 已卸载。"
else
  echo "当前 core.hooksPath 不是本仓库配置，未修改。"
fi
