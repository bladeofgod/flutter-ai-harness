#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ai-harness-check.XXXXXX")"
FIXTURE_ROOT="$FIXTURE_PARENT/repo with spaces"
cleanup() {
  rm -r -- "$FIXTURE_PARENT"
}
trap cleanup EXIT

mkdir -p "$FIXTURE_ROOT"
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
  "$FIXTURE_ROOT/docs/reviews/test-evidence" \
  "$FIXTURE_ROOT/docs" \
  "$FIXTURE_ROOT/scripts"

cat > "$FIXTURE_ROOT/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Read(**)"],
    "deny": [
      "Bash(git reset *)",
      "Bash(git clean *)",
      "Bash(git checkout -- *)",
      "Bash(git restore *)"
    ]
  }
}
JSON
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
  android-build:
    runs-on: ubuntu-latest
    steps:
      - run: TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
  ios-build:
    runs-on: macos-15
    steps:
      - run: TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
YAML
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  collection: ^1.19.0
YAML
printf '%s\n' '# Contract' '`/sample-command`' > "$FIXTURE_ROOT/CLAUDE.md"
printf '%s\n' '# Readme' '[Guide](docs/guide.md "Guide")' > "$FIXTURE_ROOT/README.md"
printf '%s\n' '# Guide' > "$FIXTURE_ROOT/docs/guide.md"
printf '\211PNG\r\n\032\n' > "$FIXTURE_ROOT/docs/image.png"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' > "$FIXTURE_ROOT/scripts/check.sh"
printf '%s\n' 'plugins {}' > "$FIXTURE_ROOT/app/apps/demo/android/app/build.gradle.kts"
printf '%s\n' '<manifest />' > "$FIXTURE_ROOT/app/apps/demo/android/app/src/main/AndroidManifest.xml"
printf '%s\n' '// project' > "$FIXTURE_ROOT/app/apps/demo/ios/Runner.xcodeproj/project.pbxproj"
printf '%s\n' '<plist />' > "$FIXTURE_ROOT/app/apps/demo/ios/Runner/Info.plist"

write_security_target() {
  printf '%s\n' 'const secureValue = true;' \
    > "$FIXTURE_ROOT/app/lib/security_target.dart"
}
write_security_target

cat > "$FIXTURE_ROOT/.claude/agents/sample-agent.md" <<'MARKDOWN'
---
name: sample-agent
description: Sample agent
tools: Read
skills: [sample-skill]
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
cat > "$FIXTURE_ROOT/.claude/agents/security-reviewer.md" <<'MARKDOWN'
---
name: security-reviewer
description: Security reviewer
tools: Read, Grep, Glob
---
Security reviewer.
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/commands/sample-command.md" <<'MARKDOWN'
---
description: Sample command
argument-hint: "<target>... [scope]"
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

sync_adapters() {
  bash "$ROOT/scripts/dart-tool.sh" run tool/sync_codex_adapters.dart \
    --root "$FIXTURE_ROOT"
}

write_valid_task() {
  cat > "$FIXTURE_ROOT/docs/tasks/sample-task.md" <<'MARKDOWN'
---
executor: task-executor
blockedBy: []
---
# Sample task
MARKDOWN
}

write_valid_done_task() {
  cat > "$FIXTURE_ROOT/docs/tasks/done/complete-task.md" <<'MARKDOWN'
---
executor: task-executor
blockedBy: []
---
# Complete task
MARKDOWN
  cat > "$FIXTURE_ROOT/docs/reviews/execute-complete-task.md" <<'MARKDOWN'
---
task: complete-task
status: passed
p0: 0
p1: 0
---
# Review
MARKDOWN
  cat > "$FIXTURE_ROOT/docs/reviews/test-evidence/complete-task.log" <<'LOG'
## Command

Exit code: 0
LOG
}

write_valid_security_review() {
  local digest
  digest="$(bash "$ROOT/scripts/dart-tool.sh" run \
    tool/implementation_digest.dart --root "$FIXTURE_ROOT" \
    app/lib/security_target.dart)"
  cat > "$FIXTURE_ROOT/docs/reviews/security-complete-task.md" <<MARKDOWN
---
task: complete-task
status: passed
p0: 0
p1: 0
implementationFiles:
  - app/lib/security_target.dart
implementationDigest: $digest
---
# Security Review
MARKDOWN
}

write_task_with_security_review_value() {
  local value="$1"
  cat > "$FIXTURE_ROOT/docs/tasks/sample-task.md" <<MARKDOWN
---
executor: task-executor
blockedBy: []
securityReview: $value
---
# Sample task
MARKDOWN
}

write_valid_task
write_valid_done_task
sync_adapters >/dev/null
run_check >/dev/null

security_agent_adapter="$FIXTURE_ROOT/.codex/agents/security-reviewer.toml"
if ! rg -F 'sandbox_mode = "read-only"' "$security_agent_adapter" >/dev/null; then
  echo "错误：Codex Security Reviewer 适配缺少 read-only sandbox。" >&2
  exit 1
fi

sed -i.bak 's/tools: Read, Grep, Glob/tools: Read, Bash, Grep, Glob/' \
  "$FIXTURE_ROOT/.claude/agents/security-reviewer.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/security-reviewer.md.bak"
sync_adapters >/dev/null
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Security Reviewer 的 Bash 权限。" >&2
  exit 1
fi
sed -i.bak 's/tools: Read, Bash, Grep, Glob/tools: Read, Grep, Glob/' \
  "$FIXTURE_ROOT/.claude/agents/security-reviewer.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/security-reviewer.md.bak"
sync_adapters >/dev/null
run_check >/dev/null

write_task_with_security_review_value required
run_check >/dev/null
write_valid_task

sed -i.bak '/blockedBy:/a\
securityReview: required' \
  "$FIXTURE_ROOT/docs/tasks/done/complete-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/done/complete-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 Security Review 的归档任务卡。" >&2
  exit 1
fi
write_valid_security_review
run_check >/dev/null

sed -i.bak \
  -e '/implementationFiles:/d' \
  -e '/app\/lib\/security_target.dart/d' \
  -e '/implementationDigest:/d' \
  "$FIXTURE_ROOT/docs/reviews/security-complete-task.md"
rm -f -- "$FIXTURE_ROOT/docs/reviews/security-complete-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少实现绑定的 Security Review。" >&2
  exit 1
fi
write_valid_security_review

printf '%s\n' 'const changedAfterReview = true;' \
  >> "$FIXTURE_ROOT/app/lib/security_target.dart"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝实现摘要过期的 Security Review。" >&2
  exit 1
fi
write_security_target
write_valid_security_review
run_check >/dev/null

sed -i.bak 's/status: passed/status: failed/' \
  "$FIXTURE_ROOT/docs/reviews/security-complete-task.md"
rm -f -- "$FIXTURE_ROOT/docs/reviews/security-complete-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝未通过的归档 Security Review。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/reviews/security-complete-task.md"
write_valid_done_task
run_check >/dev/null

command_adapter="$FIXTURE_ROOT/.agents/skills/sample-command/SKILL.md"
if ! rg -F '参数提示：`<target>... [scope]`' "$command_adapter" >/dev/null ||
  ! rg -F '显式调用 `$sample-command ...`' "$command_adapter" >/dev/null ||
  ! rg -F '其余用户输入作为 `$ARGUMENTS`' "$command_adapter" >/dev/null ||
  ! rg -F '由语义匹配触发时' "$command_adapter" >/dev/null; then
  echo "错误：Command 适配未保留 argument-hint 或参数提取契约。" >&2
  exit 1
fi

while IFS= read -r line; do
  printf '%s\r\n' "$line"
done < "$command_adapter" > "$command_adapter.crlf"
mv "$command_adapter.crlf" "$command_adapter"
if ! run_check >/dev/null 2>&1; then
  echo "错误：Codex 适配检查未兼容 CRLF 工作区换行。" >&2
  exit 1
fi
sync_adapters >/dev/null
if rg -U $'\r' "$command_adapter" >/dev/null; then
  echo "错误：Codex 适配同步未恢复 LF 换行。" >&2
  exit 1
fi

outside_agents="$FIXTURE_PARENT/outside-agents"
mkdir -p "$outside_agents"
mv "$FIXTURE_ROOT/.agents" "$FIXTURE_ROOT/.agents.valid"
ln -s "$outside_agents" "$FIXTURE_ROOT/.agents"
if sync_adapters >/dev/null 2>&1 || run_check >/dev/null 2>&1; then
  echo "错误：Codex 适配未拒绝受管目录符号链接。" >&2
  exit 1
fi
if [[ -e "$outside_agents/skills/sample-command/SKILL.md" ]]; then
  echo "错误：Codex 适配通过符号链接写入了仓库外路径。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/.agents"
mv "$FIXTURE_ROOT/.agents.valid" "$FIXTURE_ROOT/.agents"

outside_codex_agents="$FIXTURE_PARENT/outside-codex-agents"
mkdir -p "$outside_codex_agents"
mv "$FIXTURE_ROOT/.codex/agents" "$FIXTURE_ROOT/.codex/agents.valid"
ln -s "$outside_codex_agents" "$FIXTURE_ROOT/.codex/agents"
if sync_adapters >/dev/null 2>&1 || run_check >/dev/null 2>&1; then
  echo "错误：Codex 适配未拒绝 Agent 输出目录符号链接。" >&2
  exit 1
fi
if [[ -e "$outside_codex_agents/sample-agent.toml" ]]; then
  echo "错误：Codex Agent 适配通过符号链接写入了仓库外路径。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/.codex/agents"
mv "$FIXTURE_ROOT/.codex/agents.valid" "$FIXTURE_ROOT/.codex/agents"

outside_entry="$FIXTURE_PARENT/outside-AGENTS.md"
printf '%s\n' 'outside entry' > "$outside_entry"
mv "$FIXTURE_ROOT/AGENTS.md" "$FIXTURE_ROOT/AGENTS.md.valid"
ln -s "$outside_entry" "$FIXTURE_ROOT/AGENTS.md"
if sync_adapters >/dev/null 2>&1 || run_check >/dev/null 2>&1; then
  echo "错误：Codex 适配未拒绝受管文件符号链接。" >&2
  exit 1
fi
if [[ "$(cat "$outside_entry")" != 'outside entry' ]]; then
  echo "错误：Codex 适配修改了符号链接指向的仓库外文件。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/AGENTS.md"
mv "$FIXTURE_ROOT/AGENTS.md.valid" "$FIXTURE_ROOT/AGENTS.md"

mkdir -p "$FIXTURE_ROOT/.agents/skills/stale-before-failure"
cp "$FIXTURE_ROOT/.agents/skills/sample-skill/SKILL.md" \
  "$FIXTURE_ROOT/.agents/skills/stale-before-failure/SKILL.md"
mv "$command_adapter" "$FIXTURE_ROOT/sample-command-adapter.valid"
mkdir "$command_adapter"
if sync_adapters >/dev/null 2>&1; then
  echo "错误：Codex 适配同步未拒绝文件路径上的目录节点。" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_ROOT/.agents/skills/stale-before-failure/SKILL.md" ]]; then
  echo "错误：Codex 适配预检失败前删除了过期适配。" >&2
  exit 1
fi
rmdir "$command_adapter"
mv "$FIXTURE_ROOT/sample-command-adapter.valid" "$command_adapter"
sync_adapters >/dev/null
if [[ -e "$FIXTURE_ROOT/.agents/skills/stale-before-failure/SKILL.md" ]]; then
  echo "错误：恢复有效布局后未清理过期适配。" >&2
  exit 1
fi

transaction_snapshot="$FIXTURE_PARENT/transaction-snapshot"
mkdir -p "$transaction_snapshot"
printf '%s\n' 'transaction drift' >> "$FIXTURE_ROOT/AGENTS.md"
mkdir -p "$FIXTURE_ROOT/.agents/skills/stale-before-runtime-failure"
cp "$FIXTURE_ROOT/.agents/skills/sample-skill/SKILL.md" \
  "$FIXTURE_ROOT/.agents/skills/stale-before-runtime-failure/SKILL.md"
cp "$FIXTURE_ROOT/AGENTS.md" "$transaction_snapshot/AGENTS.md"
cp -R "$FIXTURE_ROOT/.agents" "$transaction_snapshot/.agents"
cp -R "$FIXTURE_ROOT/.codex" "$transaction_snapshot/.codex"
chmod 0555 "$FIXTURE_ROOT/.agents/skills/sample-skill"
set +e
sync_adapters > "$transaction_snapshot/error.log" 2>&1
runtime_failure_status=$?
set -e
chmod 0755 "$FIXTURE_ROOT/.agents/skills/sample-skill"
if [[ "$runtime_failure_status" -eq 0 ]]; then
  echo "错误：Codex 适配事务 Fixture 未触发中途写入失败。" >&2
  exit 1
fi
if ! cmp -s "$transaction_snapshot/AGENTS.md" "$FIXTURE_ROOT/AGENTS.md" ||
  ! /usr/bin/diff -r "$transaction_snapshot/.agents" "$FIXTURE_ROOT/.agents" >/dev/null ||
  ! /usr/bin/diff -r "$transaction_snapshot/.codex" "$FIXTURE_ROOT/.codex" >/dev/null; then
  echo "错误：Codex 适配同步失败后未完整恢复受管输出。" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_ROOT/.agents/skills/stale-before-runtime-failure/SKILL.md" ]]; then
  echo "错误：Codex 适配中途失败时删除了过期适配。" >&2
  exit 1
fi
if compgen -G "$FIXTURE_ROOT/.codex-adapters-tmp-*" >/dev/null; then
  echo "错误：Codex 适配同步失败后残留事务临时目录。" >&2
  exit 1
fi
if rg -F "$FIXTURE_ROOT" "$transaction_snapshot/error.log" >/dev/null ||
  ! rg -F '<repo>/' "$transaction_snapshot/error.log" >/dev/null; then
  echo "错误：Codex 适配文件系统诊断泄漏本机路径或缺少仓库相对路径。" >&2
  exit 1
fi
sync_adapters >/dev/null
if [[ -e "$FIXTURE_ROOT/.agents/skills/stale-before-runtime-failure/SKILL.md" ]]; then
  echo "错误：事务恢复后未清理过期适配。" >&2
  exit 1
fi

bash "$ROOT/scripts/dart-tool.sh" run tool/sync_codex_adapters.dart \
  --check --root "$FIXTURE_ROOT" >/dev/null
bash "$ROOT/scripts/dart-tool.sh" run tool/sync_codex_adapters.dart \
  --root "$FIXTURE_ROOT" --check >/dev/null
set +e
bash "$ROOT/scripts/dart-tool.sh" run tool/sync_codex_adapters.dart \
  --root --check >/dev/null 2>&1
invalid_root_status=$?
set -e
if [[ "$invalid_root_status" -ne 64 ]]; then
  echo "错误：Codex 适配 CLI 未以 usage 状态拒绝缺失的 --root 值。" >&2
  exit 1
fi
set +e
bash "$ROOT/scripts/dart-tool.sh" run tool/sync_codex_adapters.dart \
  --root "$FIXTURE_ROOT" --root "$FIXTURE_ROOT" >/dev/null 2>&1
duplicate_root_status=$?
set -e
if [[ "$duplicate_root_status" -ne 64 ]]; then
  echo "错误：Codex 适配 CLI 未以 usage 状态拒绝重复的 --root。" >&2
  exit 1
fi

cp "$FIXTURE_ROOT/.agents/skills/sample-skill/SKILL.md" \
  "$FIXTURE_ROOT/sample-skill-adapter.valid"
cat > "$FIXTURE_ROOT/.claude/commands/sample-skill.md" <<'MARKDOWN'
---
description: Conflicting command
---
Conflict.
MARKDOWN
if sync_adapters >/dev/null 2>&1; then
  echo "错误：Codex 适配同步未拒绝 Command/Skill 名称冲突。" >&2
  exit 1
fi
if ! cmp -s \
  "$FIXTURE_ROOT/sample-skill-adapter.valid" \
  "$FIXTURE_ROOT/.agents/skills/sample-skill/SKILL.md"; then
  echo "错误：名称冲突时 Codex 适配同步修改了已有输出。" >&2
  exit 1
fi
rm -f -- \
  "$FIXTURE_ROOT/.claude/commands/sample-skill.md" \
  "$FIXTURE_ROOT/sample-skill-adapter.valid"

printf '%s\n' 'drift' >> \
  "$FIXTURE_ROOT/.agents/skills/sample-skill/SKILL.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝被篡改的 Codex Skill 适配。" >&2
  exit 1
fi
sync_adapters >/dev/null

rm -f -- "$FIXTURE_ROOT/.codex/agents/sample-agent.toml"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的 Codex Agent 适配。" >&2
  exit 1
fi
sync_adapters >/dev/null

mkdir -p "$FIXTURE_ROOT/.agents/skills/stale-skill"
cp "$FIXTURE_ROOT/.agents/skills/sample-skill/SKILL.md" \
  "$FIXTURE_ROOT/.agents/skills/stale-skill/SKILL.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝过期的 Codex Skill 适配。" >&2
  exit 1
fi
sync_adapters >/dev/null
if [[ -e "$FIXTURE_ROOT/.agents/skills/stale-skill/SKILL.md" ]]; then
  echo "错误：Codex 适配同步未清理生成器管理的过期文件。" >&2
  exit 1
fi

cp "$command_adapter" "$FIXTURE_ROOT/sample-command-adapter.valid"
printf '%s\n' '# Hand-written Codex skill' > "$command_adapter"
if sync_adapters >/dev/null 2>&1; then
  echo "错误：Codex 适配同步覆盖了同名非生成文件。" >&2
  exit 1
fi
if [[ "$(cat "$command_adapter")" != '# Hand-written Codex skill' ]]; then
  echo "错误：Codex 适配同步修改了同名非生成文件。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/sample-command-adapter.valid" "$command_adapter"

printf '%s\n' 'drift' >> "$FIXTURE_ROOT/AGENTS.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝漂移的 AGENTS.md。" >&2
  exit 1
fi
sync_adapters >/dev/null

cp "$FIXTURE_ROOT/AGENTS.md" "$FIXTURE_ROOT/AGENTS.md.valid"
printf '%s\n' '# Hand-written agent entry' > "$FIXTURE_ROOT/AGENTS.md"
if sync_adapters >/dev/null 2>&1; then
  echo "错误：Codex 适配同步覆盖了非生成 AGENTS.md。" >&2
  exit 1
fi
if [[ "$(cat "$FIXTURE_ROOT/AGENTS.md")" != '# Hand-written agent entry' ]]; then
  echo "错误：Codex 适配同步修改了非生成 AGENTS.md。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/AGENTS.md.valid" "$FIXTURE_ROOT/AGENTS.md"

sed -i.bak 's/Sample command/Changed command/' \
  "$FIXTURE_ROOT/.claude/commands/sample-command.md"
rm -f -- "$FIXTURE_ROOT/.claude/commands/sample-command.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝未同步的 Claude Command 元数据。" >&2
  exit 1
fi
sync_adapters >/dev/null
sed -i.bak 's/Changed command/Sample command/' \
  "$FIXTURE_ROOT/.claude/commands/sample-command.md"
rm -f -- "$FIXTURE_ROOT/.claude/commands/sample-command.md.bak"
sync_adapters >/dev/null

sed -i.bak 's/skills: \[sample-skill\]/skills: [missing-skill]/' \
  "$FIXTURE_ROOT/.claude/agents/sample-agent.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/sample-agent.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Agent 引用不存在的 Skill。" >&2
  exit 1
fi
sed -i.bak 's/skills: \[missing-skill\]/skills: [sample-skill]/' \
  "$FIXTURE_ROOT/.claude/agents/sample-agent.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/sample-agent.md.bak"

rm -f -- "$FIXTURE_ROOT/docs/reviews/execute-complete-task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 Review 的归档任务卡。" >&2
  exit 1
fi
write_valid_done_task

sed -i.bak 's/status: passed/status: failed/' \
  "$FIXTURE_ROOT/docs/reviews/execute-complete-task.md"
rm -f -- "$FIXTURE_ROOT/docs/reviews/execute-complete-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝未通过的归档 Review。" >&2
  exit 1
fi
write_valid_done_task

rm -f -- "$FIXTURE_ROOT/docs/reviews/test-evidence/complete-task.log"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少测试证据的归档任务卡。" >&2
  exit 1
fi
write_valid_done_task

sed -i.bak 's/blockedBy: \[\]/blockedBy: [sample-task]/' \
  "$FIXTURE_ROOT/docs/tasks/done/complete-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/done/complete-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝依赖活动任务的归档任务卡。" >&2
  exit 1
fi
write_valid_done_task

cp "$FIXTURE_ROOT/.claude/settings.json" \
  "$FIXTURE_ROOT/.claude/settings.json.valid"
sed -i.bak 's/"Read(\*\*)"/"Read(**)", "Bash(git *)"/' \
  "$FIXTURE_ROOT/.claude/settings.json"
rm -f -- "$FIXTURE_ROOT/.claude/settings.json.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝无条件 Git 权限。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/.claude/settings.json.valid" \
  "$FIXTURE_ROOT/.claude/settings.json"

cp "$FIXTURE_ROOT/.claude/settings.json" \
  "$FIXTURE_ROOT/.claude/settings.json.valid"
sed -i.bak '/Bash(git reset/d' "$FIXTURE_ROOT/.claude/settings.json"
rm -f -- "$FIXTURE_ROOT/.claude/settings.json.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的破坏性 Git 规则。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/.claude/settings.json.valid" \
  "$FIXTURE_ROOT/.claude/settings.json"

sed -i.bak '/blockedBy:/a\
uiSpec: required' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝已废弃的 uiSpec 任务元数据。" >&2
  exit 1
fi
write_valid_task

for invalid_security_review in '' true '[]' optional; do
  write_task_with_security_review_value "$invalid_security_review"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝无效的 securityReview 任务元数据：${invalid_security_review:-null}。" >&2
    exit 1
  fi
done
write_valid_task

sed -i.bak 's/blockedBy: \[\]/blockedBy: [sample-task]/' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝任务自依赖。" >&2
  exit 1
fi
write_valid_task

cat > "$FIXTURE_ROOT/docs/tasks/cycle-task.md" <<'MARKDOWN'
---
executor: task-executor
blockedBy: [sample-task]
---
# Cycle task
MARKDOWN
sed -i.bak 's/blockedBy: \[\]/blockedBy: [cycle-task]/' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝循环任务依赖。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/cycle-task.md"
write_valid_task

sed -i.bak 's/executor: task-executor/executor: sample-agent/' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝无效任务 executor。" >&2
  exit 1
fi
write_valid_task

sed -i.bak '/blockedBy:/d' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 blockedBy 的任务卡。" >&2
  exit 1
fi
write_valid_task

sed -i.bak 's/blockedBy: \[\]/blockedBy: [missing-task]/' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不存在的 blockedBy 任务。" >&2
  exit 1
fi
write_valid_task

mkdir -p "$FIXTURE_ROOT/docs/tasks/group"
cp "$FIXTURE_ROOT/docs/tasks/sample-task.md" \
  "$FIXTURE_ROOT/docs/tasks/group/misplaced-task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝多余的任务子目录。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/group/misplaced-task.md"
rmdir "$FIXTURE_ROOT/docs/tasks/group"

cp "$FIXTURE_ROOT/docs/tasks/sample-task.md" \
  "$FIXTURE_ROOT/docs/tasks/Invalid_Task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝非法任务 slug。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/Invalid_Task.md"

sed -i.bak 's/# Sample task/## Sample task/' \
  "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少一级标题的任务卡。" >&2
  exit 1
fi
write_valid_task

cp "$FIXTURE_ROOT/docs/tasks/sample-task.md" \
  "$FIXTURE_ROOT/docs/tasks/done/sample-task.md"
cat > "$FIXTURE_ROOT/docs/reviews/execute-sample-task.md" <<'MARKDOWN'
---
task: sample-task
status: passed
p0: 0
p1: 0
---
# Review
MARKDOWN
cat > "$FIXTURE_ROOT/docs/reviews/test-evidence/sample-task.log" <<'LOG'
## Command

Exit code: 0
LOG
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝重复任务 slug。" >&2
  exit 1
fi
rm -f -- \
  "$FIXTURE_ROOT/docs/tasks/done/sample-task.md" \
  "$FIXTURE_ROOT/docs/reviews/execute-sample-task.md" \
  "$FIXTURE_ROOT/docs/reviews/test-evidence/sample-task.log"

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
  get: ^4.7.3
YAML
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 pub.dev 官方 GetX。" >&2
  exit 1
fi
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  get:
    git:
      url: https://github.com/bladeofgod/getx.git
      ref: 7bfcd9c3711c8880ee730579724dabe54f4e2598
YAML
run_check >/dev/null
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

cp "$FIXTURE_ROOT/.github/workflows/ci.yml" \
  "$FIXTURE_ROOT/.github/workflows/ci.yml.valid"
sed -i.bak '/build ios --debug --no-codesign/d' \
  "$FIXTURE_ROOT/.github/workflows/ci.yml"
rm -f -- "$FIXTURE_ROOT/.github/workflows/ci.yml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 iOS 构建命令的 CI。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/.github/workflows/ci.yml.valid" \
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
argument-hint: "<target>... [scope]"
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
argument-hint: "<target>... [scope]"
---
使用 `sample-agent`。
MARKDOWN

rm -f -- "$FIXTURE_ROOT/app/apps/demo/ios/Runner/Info.plist"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失平台宿主。" >&2
  exit 1
fi

echo "[harness-test] Harness 配置与失败 Fixture 通过。"
