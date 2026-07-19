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
  "$FIXTURE_ROOT/app/apps/demo/android/app/src/main" \
  "$FIXTURE_ROOT/app/apps/demo/ios/Runner.xcodeproj" \
  "$FIXTURE_ROOT/app/apps/demo/ios/Runner" \
  "$FIXTURE_ROOT/app" \
  "$FIXTURE_ROOT/docs" \
  "$FIXTURE_ROOT/scripts"

printf '%s\n' '{}' > "$FIXTURE_ROOT/.claude/settings.json"
printf '%s\n' '{"mcpServers":{}}' > "$FIXTURE_ROOT/.mcp.json"
printf '%s\n' '{"flutter":"3.35.7"}' > "$FIXTURE_ROOT/app/.fvmrc"
printf '%s\n' '# Contract' '`/sample-command`' > "$FIXTURE_ROOT/CLAUDE.md"
printf '%s\n' '# Agents' > "$FIXTURE_ROOT/AGENTS.md"
printf '%s\n' '# Readme' '[Guide](docs/guide.md "Guide")' > "$FIXTURE_ROOT/README.md"
printf '%s\n' '# Guide' > "$FIXTURE_ROOT/docs/guide.md"
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

run_check >/dev/null

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
