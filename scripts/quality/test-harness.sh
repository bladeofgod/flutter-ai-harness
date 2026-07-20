#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-check.XXXXXX")"
cleanup() {
  rm -r -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$FIXTURE_ROOT/.claude/agents" \
  "$FIXTURE_ROOT/.claude/commands" \
  "$FIXTURE_ROOT/.claude/skills/sample-skill" \
  "$FIXTURE_ROOT/.github/workflows" \
  "$FIXTURE_ROOT/app/apps/demo/android/app/src/main" \
  "$FIXTURE_ROOT/app/apps/demo/ios/Runner.xcodeproj" \
  "$FIXTURE_ROOT/app/apps/demo/ios/Runner" \
  "$FIXTURE_ROOT/app/lib" \
  "$FIXTURE_ROOT/app" \
  "$FIXTURE_ROOT/docs/tasks/done" \
  "$FIXTURE_ROOT/docs/tasks/sprint-2" \
  "$FIXTURE_ROOT/docs" \
  "$FIXTURE_ROOT/scripts"

printf '%s\n' '{}' > "$FIXTURE_ROOT/.claude/settings.json"
printf '%s\n' '{"mcpServers":{}}' > "$FIXTURE_ROOT/.mcp.json"
printf '%s\n' '{"flutter":"3.35.7"}' > "$FIXTURE_ROOT/app/.fvmrc"
cat > "$FIXTURE_ROOT/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [push]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: example/flutter-action@fixture
        with:
          flutter-version: "3.35.7"
      - run: make bootstrap
      - run: make check
YAML
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  collection: ^1.19.0
YAML
printf '%s\n' '# Contract' '`/sample-command`' > "$FIXTURE_ROOT/CLAUDE.md"
printf '%s\n' '# Agents' > "$FIXTURE_ROOT/AGENTS.md"
printf '%s\n' '# Readme' '[Guide](docs/guide.md "Guide")' > "$FIXTURE_ROOT/README.md"
printf '%s\n' '# Guide' > "$FIXTURE_ROOT/docs/guide.md"
printf '%s\n' '# Sprint 2' > "$FIXTURE_ROOT/docs/tasks/sprint-2/00-overview.md"
printf '\211PNG\r\n\032\n' > "$FIXTURE_ROOT/docs/image.png"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' > "$FIXTURE_ROOT/scripts/check.sh"
printf '%s\n' 'plugins {}' > "$FIXTURE_ROOT/app/apps/demo/android/app/build.gradle.kts"
printf '%s\n' '<manifest />' > "$FIXTURE_ROOT/app/apps/demo/android/app/src/main/AndroidManifest.xml"
printf '%s\n' '// project' > "$FIXTURE_ROOT/app/apps/demo/ios/Runner.xcodeproj/project.pbxproj"
printf '%s\n' '<plist />' > "$FIXTURE_ROOT/app/apps/demo/ios/Runner/Info.plist"

cat > "$FIXTURE_ROOT/.claude/agents/sample-agent.md" <<'MARKDOWN'
---
name: sample-agent
description: Sample agent
tools: Read
---
Sample.
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/agents/task-executor.md" <<'MARKDOWN'
---
name: task-executor
description: Task executor
tools: Read
---
Task executor.
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/commands/sample-command.md" <<'MARKDOWN'
---
description: Sample command
---
使用 `sample-agent`。
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/skills/sample-skill/SKILL.md" <<'MARKDOWN'
---
name: sample-skill
description: "适用：Fixture。不适用：生产。触发词：sample。"
paths: ["app/**"]
---
Sample.
MARKDOWN

run_check() {
  bash "$ROOT/scripts/dart-tool.sh" run tool/harness_check.dart \
    --root "$FIXTURE_ROOT"
}

write_valid_task() {
  cat > "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md" <<'MARKDOWN'
---
executor: task-executor
blockedBy: []
uiSpec: not-required
---
# S2-001 Sample task
MARKDOWN
}

write_valid_task
run_check >/dev/null

sed -i.bak '/uiSpec:/d' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 uiSpec 的活动任务卡。" >&2
  exit 1
fi
write_valid_task

sed -i.bak 's/blockedBy: \[\]/blockedBy: [S2-001]/' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝任务自依赖。" >&2
  exit 1
fi
write_valid_task

cat > "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-002-cycle-task.md" <<'MARKDOWN'
---
executor: task-executor
blockedBy: [S2-001]
uiSpec: not-required
---
# S2-002 Cycle task
MARKDOWN
sed -i.bak 's/blockedBy: \[\]/blockedBy: [S2-002]/' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝循环任务依赖。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-002-cycle-task.md"
write_valid_task

sed -i.bak 's/executor: task-executor/executor: sample-agent/' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝无效任务 executor。" >&2
  exit 1
fi
write_valid_task

sed -i.bak '/blockedBy:/d' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 blockedBy 的任务卡。" >&2
  exit 1
fi
write_valid_task

sed -i.bak 's/blockedBy: \[\]/blockedBy: [S2-999]/' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不存在的 blockedBy 任务。" >&2
  exit 1
fi
write_valid_task

cp "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md" \
  "$FIXTURE_ROOT/docs/tasks/S2-002-misplaced-task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝根目录任务卡。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/S2-002-misplaced-task.md"

cp "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md" \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S3-002-wrong-sprint.md"
sed -i.bak 's/S2-001/S3-002/g' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S3-002-wrong-sprint.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S3-002-wrong-sprint.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Sprint 编号不一致的任务卡。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S3-002-wrong-sprint.md"

sed -i.bak 's/# S2-001/# S2-999/' \
  "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝标题任务 ID 不一致的任务卡。" >&2
  exit 1
fi
write_valid_task

cp "$FIXTURE_ROOT/docs/tasks/sprint-2/S2-001-sample-task.md" \
  "$FIXTURE_ROOT/docs/tasks/done/S2-001-duplicate-task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝重复任务 ID。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/done/S2-001-duplicate-task.md"

private_root="/Use""rs/example/private"
mkdir -p "$FIXTURE_ROOT/app/local_package"
cat > "$FIXTURE_ROOT/app/local_package/pubspec.yaml" <<'YAML'
name: local_package
environment:
  sdk: ^3.9.0
YAML
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  local_package:
    path: local_package
YAML
run_check >/dev/null

cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<YAML
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  private_package:
    path: $private_root/package
YAML
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝本机绝对 path 依赖。" >&2
  exit 1
fi
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  private_package:
    git:
      url: git@github.com:example/private.git
      ref: main
YAML
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不可复现 Git 依赖。" >&2
  exit 1
fi
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  collection: ^1.19.0
YAML

printf '%s\n' "const localPath = '$private_root/file';" \
  > "$FIXTURE_ROOT/app/lib/private_path.dart"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝应用源码中的本机用户路径。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/app/lib/private_path.dart"

mv "$FIXTURE_ROOT/.github/workflows/ci.yml" \
  "$FIXTURE_ROOT/.github/workflows/ci.yml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失 CI Workflow。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/.github/workflows/ci.yml.bak" \
  "$FIXTURE_ROOT/.github/workflows/ci.yml"

cat > "$FIXTURE_ROOT/.claude/skills/sample-skill/SKILL.md" <<'MARKDOWN'
---
name: sample-skill
description: "适用：Fixture。不适用：生产。触发词：sample。"
---
Sample.
MARKDOWN
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 paths 的 Skill。" >&2
  exit 1
fi
cat > "$FIXTURE_ROOT/.claude/skills/sample-skill/SKILL.md" <<'MARKDOWN'
---
name: sample-skill
description: "适用：Fixture。不适用：生产。触发词：sample。"
paths: ["app/**"]
---
Sample.
MARKDOWN

printf '%s\n' '# Readme' '[Missing](docs/missing.md)' > "$FIXTURE_ROOT/README.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝失效 Markdown 链接。" >&2
  exit 1
fi
printf '%s\n' '# Readme' '[Guide](docs/guide.md "Guide")' > "$FIXTURE_ROOT/README.md"

cat > "$FIXTURE_ROOT/.claude/commands/sample-command.md" <<'MARKDOWN'
---
description: Sample command
---
使用 `missing-agent`。
MARKDOWN
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝失效 Agent 引用。" >&2
  exit 1
fi
cat > "$FIXTURE_ROOT/.claude/commands/sample-command.md" <<'MARKDOWN'
---
description: Sample command
---
使用 `sample-agent`。
MARKDOWN

rm -f -- "$FIXTURE_ROOT/app/apps/demo/ios/Runner/Info.plist"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失平台宿主。" >&2
  exit 1
fi

echo "[harness-test] Harness 配置与失败 Fixture 通过。"
