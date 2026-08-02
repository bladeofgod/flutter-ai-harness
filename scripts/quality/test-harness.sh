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
  "$FIXTURE_ROOT/.claude/skills/kotlin-android-standards" \
  "$FIXTURE_ROOT/.claude/skills/native-testing-strategy" \
  "$FIXTURE_ROOT/.claude/skills/sample-skill" \
  "$FIXTURE_ROOT/.claude/skills/swift-ios-standards" \
  "$FIXTURE_ROOT/.github/workflows" \
  "$FIXTURE_ROOT/app/apps/demo/android/app/src/main" \
  "$FIXTURE_ROOT/app/apps/demo/android/app/src/main/kotlin/com/example/demo_app" \
  "$FIXTURE_ROOT/app/apps/demo/ios/Runner.xcodeproj" \
  "$FIXTURE_ROOT/app/apps/demo/ios/Runner" \
  "$FIXTURE_ROOT/app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture" \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests" \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/ios/tool" \
  "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/test/contracts" \
  "$FIXTURE_ROOT/app/lib" \
  "$FIXTURE_ROOT/app" \
  "$FIXTURE_ROOT/docs/tasks/done" \
  "$FIXTURE_ROOT/docs/reviews/test-evidence" \
  "$FIXTURE_ROOT/docs/bridge" \
  "$FIXTURE_ROOT/docs/bridge/contracts" \
  "$FIXTURE_ROOT/docs/infrastructure/contracts" \
  "$FIXTURE_ROOT/docs/native/contracts" \
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
      - run: make media-capture-android
      - run: TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
  ios-build:
    runs-on: macos-15
    steps:
      - run: make media-capture-ios
      - run: TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
YAML
cat > "$FIXTURE_ROOT/app/pubspec.yaml" <<'YAML'
name: fixture
environment:
  sdk: ^3.9.0
dependencies:
  collection: ^1.19.0
YAML
printf '%s\n' '# Readme' '[Guide](docs/guide.md "Guide")' > "$FIXTURE_ROOT/README.md"
printf '%s\n' '# Guide' > "$FIXTURE_ROOT/docs/guide.md"
printf '\211PNG\r\n\032\n' > "$FIXTURE_ROOT/docs/image.png"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' > "$FIXTURE_ROOT/scripts/check.sh"
printf '%s\n' 'plugins {}' > "$FIXTURE_ROOT/app/apps/demo/android/app/build.gradle.kts"
cat > "$FIXTURE_ROOT/app/apps/demo/android/app/src/main/AndroidManifest.xml" <<'XML'
<manifest>
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
</manifest>
XML
printf '%s\n' 'class MainActivity : FlutterActivity()' \
  > "$FIXTURE_ROOT/app/apps/demo/android/app/src/main/kotlin/com/example/demo_app/MainActivity.kt"
cat > "$FIXTURE_ROOT/Makefile" <<'MAKE'
media-capture-android:
	bash scripts/quality/media-capture-android.sh
media-capture-ios:
	bash scripts/quality/media-capture-ios.sh
MAKE
cat > "$FIXTURE_ROOT/app/apps/demo/pubspec.yaml" <<'YAML'
name: demo_fixture
flutter:
  config:
    enable-swift-package-manager: true
YAML
cat > "$FIXTURE_ROOT/app/apps/demo/ios/Runner.xcodeproj/project.pbxproj" <<'TEXT'
FlutterGeneratedPluginSwiftPackage in Frameworks
XCLocalSwiftPackageReference "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"
productName = FlutterGeneratedPluginSwiftPackage;
TEXT
cat > "$FIXTURE_ROOT/app/apps/demo/ios/Runner/Info.plist" <<'XML'
<plist><dict>
<key>NSCameraUsageDescription</key><string>Camera</string>
<key>NSMicrophoneUsageDescription</key><string>Microphone</string>
</dict></plist>
XML
cat > "$FIXTURE_ROOT/app/apps/demo/ios/Runner/AppDelegate.swift" <<'SWIFT'
GeneratedPluginRegistrant.register(with: self)
SWIFT
printf '%s\n' 'Flutter/ephemeral/' > "$FIXTURE_ROOT/app/apps/demo/ios/.gitignore"

write_security_target() {
  printf '%s\n' 'const secureValue = true;' \
    > "$FIXTURE_ROOT/app/lib/security_target.dart"
}
write_security_target

write_native_architecture_documents() {
  cat > "$FIXTURE_ROOT/CLAUDE.md" <<'MARKDOWN'
# Contract
`/sample-command`
## 重要参考
[Native architecture](./docs/native-architecture.md)
## Other
Other references.
MARKDOWN
  cat > "$FIXTURE_ROOT/docs/architecture.md" <<'MARKDOWN'
# Architecture
[Native architecture](./native-architecture.md)
MARKDOWN
  cat > "$FIXTURE_ROOT/docs/infrastructure-modules.md" <<'MARKDOWN'
# Infrastructure modules
[Native architecture](./native-architecture.md)
| 原生媒体拍摄 | Android `app/native/android/media_capture/`；iOS `app/native/ios/MediaCapture/` | Android/iOS Media Capture Native Module | 已批准 | 已实现 | Customer Support 媒体消息与 Shoppe 订单评价 | [media-capture.md](./infrastructure/media-capture.md) |
MARKDOWN
  cat > "$FIXTURE_ROOT/docs/bridge/README.md" <<'MARKDOWN'
# Bridge
[Native architecture](../native-architecture.md)
MARKDOWN
  cat > "$FIXTURE_ROOT/docs/native-architecture.md" <<'MARKDOWN'
# Native architecture
The repository currently contains Host projects but no implemented Native Module.
<!-- native-architecture-contract:start -->
```json
{
  "schemaVersion": 1,
  "hosts": [
    {
      "platform": "android",
      "path": "app/apps/demo/android/",
      "status": "implemented"
    },
    {
      "platform": "ios",
      "path": "app/apps/demo/ios/",
      "status": "implemented"
    }
  ],
  "nativeModules": [],
  "bridgePackages": [],
  "layoutTemplates": {
    "androidNativeModule": "app/native/android/<module>/",
    "iosNativeModule": "app/native/ios/<Module>/",
    "flutterBridgePackage": "app/packages/app_<capability>_bridge/"
  },
  "components": [
    "host",
    "native_module",
    "dart_client",
    "android_bridge_adapter",
    "ios_bridge_adapter"
  ],
  "dependencyEdges": [
    {"from": "android_native_consumer", "to": "android_native_module"},
    {"from": "ios_native_consumer", "to": "ios_native_module"},
    {"from": "flutter_consumer", "to": "dart_client"},
    {"from": "dart_client", "to": "channel"},
    {"from": "channel", "to": "android_bridge_adapter"},
    {"from": "channel", "to": "ios_bridge_adapter"},
    {"from": "android_bridge_adapter", "to": "android_native_module"},
    {"from": "ios_bridge_adapter", "to": "ios_native_module"},
    {"from": "host", "to": "native_module"},
    {"from": "host", "to": "bridge_adapter_registration"}
  ],
  "forbiddenDependencyEdges": [
    {"from": "native_module", "to": "flutter"}
  ]
}
```
<!-- native-architecture-contract:end -->
MARKDOWN
}

write_native_architecture_documents

write_capability_contract_documents() {
  cp "$ROOT/docs/native/contracts/capability.schema.json" \
    "$FIXTURE_ROOT/docs/native/contracts/capability.schema.json"
  cp "$ROOT/docs/infrastructure/contracts/media-capture.capability.json" \
    "$FIXTURE_ROOT/docs/infrastructure/contracts/media-capture.capability.json"
  cp "$ROOT/docs/infrastructure/media-capture.md" \
    "$FIXTURE_ROOT/docs/infrastructure/media-capture.md"
}

write_capability_contract_documents

write_wire_contract_documents() {
  cp "$ROOT/docs/bridge/contracts/wire.schema.json" \
    "$FIXTURE_ROOT/docs/bridge/contracts/wire.schema.json"
  cp "$ROOT/docs/bridge/contracts/media-capture.wire.json" \
    "$FIXTURE_ROOT/docs/bridge/contracts/media-capture.wire.json"
  cp "$ROOT/docs/bridge/media-capture.md" \
    "$FIXTURE_ROOT/docs/bridge/media-capture.md"
  cp "$ROOT/app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json" \
    "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json"
  cp "$ROOT/app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart" \
    "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart"
  cp "$ROOT/app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt" \
    "$FIXTURE_ROOT/app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt"
  cp "$ROOT/app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift" \
    "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift"
  cp "$ROOT/app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh" \
    "$FIXTURE_ROOT/app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh"
}

write_wire_contract_documents

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
cat > "$FIXTURE_ROOT/.claude/agents/android-engineer.md" <<'MARKDOWN'
---
name: android-engineer
description: Android engineer
tools: Read, Write, Edit, Bash, Grep, Glob
skills: [kotlin-android-standards, native-testing-strategy]
---
不 commit、push、发布或读取凭据；不使用无约束外部网络。
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/agents/ios-engineer.md" <<'MARKDOWN'
---
name: ios-engineer
description: iOS engineer
tools: Read, Write, Edit, Bash, Grep, Glob
skills: [swift-ios-standards, native-testing-strategy]
---
不 commit、push、发布或读取凭据；不使用无约束外部网络。
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/agents/bridge-engineer.md" <<'MARKDOWN'
---
name: bridge-engineer
description: Bridge engineer
tools: Read, Write, Edit, Bash, Grep, Glob
---
Bridge engineer.
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/agents/reviewer.md" <<'MARKDOWN'
---
name: reviewer
description: Reviewer
tools: Read, Grep, Glob
---
Reviewer.
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
cat > "$FIXTURE_ROOT/.claude/skills/kotlin-android-standards/SKILL.md" <<'MARKDOWN'
---
name: kotlin-android-standards
description: "适用：Android Fixture。不适用：iOS。触发词：Kotlin。"
paths: ["app/native/android/**", "app/apps/*/android/**", "app/packages/*/android/**"]
---
Android.
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/skills/swift-ios-standards/SKILL.md" <<'MARKDOWN'
---
name: swift-ios-standards
description: "适用：iOS Fixture。不适用：Android。触发词：Swift。"
paths: ["app/native/ios/**", "app/apps/*/ios/**", "app/packages/*/ios/**"]
---
iOS.
MARKDOWN
cat > "$FIXTURE_ROOT/.claude/skills/native-testing-strategy/SKILL.md" <<'MARKDOWN'
---
name: native-testing-strategy
description: "适用：Native test Fixture。不适用：Dart。触发词：JUnit、XCTest。"
paths: ["app/native/android/**/src/test/**", "app/native/ios/**/Tests/**"]
---
Native tests.
MARKDOWN

run_dart_script() {
  bash "$ROOT/scripts/dart-tool.sh" \
    --packages=.dart_tool/package_config.json "$@"
}

run_check() {
  run_dart_script tool/harness_check.dart \
    --root "$FIXTURE_ROOT"
}

sync_adapters() {
  run_dart_script tool/sync_codex_adapters.dart \
    --root "$FIXTURE_ROOT"
}

write_valid_task() {
  cat > "$FIXTURE_ROOT/docs/tasks/sample-task.md" <<'MARKDOWN'
---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy: []
---
# Sample task
MARKDOWN
}

write_scoped_task() {
  local executor="$1"
  local platforms="$2"
  local work_kinds="$3"
  cat > "$FIXTURE_ROOT/docs/tasks/sample-task.md" <<MARKDOWN
---
executor: $executor
platforms: $platforms
workKinds: $work_kinds
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
  digest="$(run_dart_script tool/implementation_digest.dart \
    --root "$FIXTURE_ROOT" \
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
platforms: []
workKinds: [harness]
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

for platform_agent_fixture in \
  "android-engineer:kotlin-android-standards:swift-ios-standards:Android" \
  "ios-engineer:swift-ios-standards:kotlin-android-standards:iOS"; do
  IFS=: read -r agent_name platform_skill wrong_skill platform_label \
    <<< "$platform_agent_fixture"
  platform_agent="$FIXTURE_ROOT/.claude/agents/$agent_name.md"
  valid_platform_agent="$FIXTURE_ROOT/$agent_name.valid"
  cp "$platform_agent" "$valid_platform_agent"

  sed -i.bak '/^skills:/d' "$platform_agent"
  rm -f -- "$platform_agent.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝缺少 skills 的 $platform_label Engineer。" >&2
    exit 1
  fi

  cp "$valid_platform_agent" "$platform_agent"
  sed -i.bak "s/$platform_skill/$wrong_skill/" "$platform_agent"
  rm -f -- "$platform_agent.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 $platform_label Engineer 引用错误平台 Skill。" >&2
    exit 1
  fi

  cp "$valid_platform_agent" "$platform_agent"
  sed -i.bak 's/, native-testing-strategy//' "$platform_agent"
  rm -f -- "$platform_agent.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 $platform_label Engineer 缺少原生测试 Skill。" >&2
    exit 1
  fi

  mv "$valid_platform_agent" "$platform_agent"
done
run_check >/dev/null

for generated_agent in android-engineer ios-engineer; do
  generated_agent_adapter="$FIXTURE_ROOT/.codex/agents/$generated_agent.toml"
  if [[ ! -f "$generated_agent_adapter" ]] ||
    rg -F 'sandbox_mode = "read-only"' "$generated_agent_adapter" >/dev/null; then
    echo "错误：Codex 平台 Engineer 适配缺失或被错误设为 read-only：$generated_agent。" >&2
    exit 1
  fi
done
for generated_skill in \
  kotlin-android-standards \
  swift-ios-standards \
  native-testing-strategy; do
  if [[ ! -f "$FIXTURE_ROOT/.agents/skills/$generated_skill/SKILL.md" ]]; then
    echo "错误：缺少新增原生 Skill 的 Codex 适配：$generated_skill。" >&2
    exit 1
  fi
done
if ! rg -F 'description = "Android engineer"' \
  "$FIXTURE_ROOT/.codex/agents/android-engineer.toml" >/dev/null ||
  ! rg -F 'description: "适用：Android Fixture。不适用：iOS。触发词：Kotlin。"' \
  "$FIXTURE_ROOT/.agents/skills/kotlin-android-standards/SKILL.md" >/dev/null; then
  echo "错误：新增 Agent/Skill 的 description 未同步到 Codex 适配。" >&2
  exit 1
fi

for read_only_agent in reviewer security-reviewer; do
  if ! rg -F 'sandbox_mode = "read-only"' \
    "$FIXTURE_ROOT/.codex/agents/$read_only_agent.toml" >/dev/null; then
    echo "错误：Codex 只读 Reviewer 适配缺少 read-only sandbox：$read_only_agent。" >&2
    exit 1
  fi
done

sed -i.bak 's/Bash, Grep, Glob/Bash, Grep, Glob, WebFetch/' \
  "$FIXTURE_ROOT/.claude/agents/android-engineer.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/android-engineer.md.bak"
sync_adapters >/dev/null
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝平台 Engineer 的外部网络工具。" >&2
  exit 1
fi
sed -i.bak 's/Bash, Grep, Glob, WebFetch/Bash, Grep, Glob/' \
  "$FIXTURE_ROOT/.claude/agents/android-engineer.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/android-engineer.md.bak"
sync_adapters >/dev/null
run_check >/dev/null

sed -i.bak 's#app/packages/\*/android/\*\*#app/packages/*/ios/**#' \
  "$FIXTURE_ROOT/.claude/skills/kotlin-android-standards/SKILL.md"
rm -f -- "$FIXTURE_ROOT/.claude/skills/kotlin-android-standards/SKILL.md.bak"
sync_adapters >/dev/null
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Kotlin Skill 越界覆盖 iOS。" >&2
  exit 1
fi
sed -i.bak 's#app/packages/\*/ios/\*\*#app/packages/*/android/**#' \
  "$FIXTURE_ROOT/.claude/skills/kotlin-android-standards/SKILL.md"
rm -f -- "$FIXTURE_ROOT/.claude/skills/kotlin-android-standards/SKILL.md.bak"
sync_adapters >/dev/null
run_check >/dev/null

sed -i.bak 's/Android engineer/Changed Android engineer/' \
  "$FIXTURE_ROOT/.claude/agents/android-engineer.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/android-engineer.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝新增 Agent description 造成的适配漂移。" >&2
  exit 1
fi
sync_adapters >/dev/null
if ! rg -F 'description = "Changed Android engineer"' \
  "$FIXTURE_ROOT/.codex/agents/android-engineer.toml" >/dev/null; then
  echo "错误：Codex Adapter 未同步新增 Agent description。" >&2
  exit 1
fi
sed -i.bak 's/Changed Android engineer/Android engineer/' \
  "$FIXTURE_ROOT/.claude/agents/android-engineer.md"
rm -f -- "$FIXTURE_ROOT/.claude/agents/android-engineer.md.bak"
sync_adapters >/dev/null
run_check >/dev/null

rm -f -- "$FIXTURE_ROOT/.codex/agents/android-engineer.toml"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的 Android Engineer Codex 适配。" >&2
  exit 1
fi
sync_adapters >/dev/null
rm -f -- "$FIXTURE_ROOT/.agents/skills/kotlin-android-standards/SKILL.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的 Kotlin Skill Codex 适配。" >&2
  exit 1
fi
sync_adapters >/dev/null
mkdir -p "$FIXTURE_ROOT/.agents/skills/stale-native-skill"
cp "$FIXTURE_ROOT/.agents/skills/native-testing-strategy/SKILL.md" \
  "$FIXTURE_ROOT/.agents/skills/stale-native-skill/SKILL.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝过期的原生 Codex Skill 适配。" >&2
  exit 1
fi
sync_adapters >/dev/null
run_check >/dev/null

rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的原生架构文档。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak '/docs\/native-architecture.md/d' "$FIXTURE_ROOT/CLAUDE.md"
rm -f -- "$FIXTURE_ROOT/CLAUDE.md.bak"
printf '%s\n' '[Native architecture](./docs/native-architecture.md)' \
  >> "$FIXTURE_ROOT/CLAUDE.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 CLAUDE.md 重要参考缺失原生架构入口。" >&2
  exit 1
fi
write_native_architecture_documents

for native_architecture_entry in \
  docs/architecture.md \
  docs/infrastructure-modules.md \
  docs/bridge/README.md; do
  sed -i.bak '/native-architecture.md/d' \
    "$FIXTURE_ROOT/$native_architecture_entry"
  rm -f -- "$FIXTURE_ROOT/$native_architecture_entry.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 $native_architecture_entry 缺失原生架构入口。" >&2
    exit 1
  fi
  write_native_architecture_documents
done

sed -i.bak \
  '/native-architecture-contract:start/,/native-architecture-contract:end/d' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的原生架构 JSON 契约块。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak 's/"schemaVersion": 1/"schemaVersion":/' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝无效的原生架构 JSON 契约块。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak \
  's#"nativeModules": \[\]#"nativeModules": [{"platform":"android","path":"app/native/android/missing_module/","status":"implemented"}]#' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝虚构为已实现的 Native Module。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak \
  's#"bridgePackages": \[\]#"bridgePackages": [{"path":"app/packages/app_missing_bridge/","status":"implemented"}]#' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝虚构为已实现的 Bridge Package。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak '/"native_module",/d' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 Native Module 组件的架构契约。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak \
  '/"from": "android_bridge_adapter", "to": "android_native_module"/d' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 Bridge 到 Native Module 的依赖边。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak \
  '/"from": "dart_client", "to": "channel"/a\
    {"from": "dart_client", "to": "android_native_module"},' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝额外的 Dart Client 到 Native Module 反向边。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak '/"from": "native_module", "to": "flutter"/d' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 Native Module 禁止边的架构契约。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak \
  '/"from": "native_module", "to": "flutter"/i\
    {"from": "dart_client", "to": "flutter"},' \
  "$FIXTURE_ROOT/docs/native-architecture.md"
rm -f -- "$FIXTURE_ROOT/docs/native-architecture.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝额外的禁止依赖边。" >&2
  exit 1
fi
write_native_architecture_documents
run_check >/dev/null

capability_schema="$FIXTURE_ROOT/docs/native/contracts/capability.schema.json"
capability_contract="$FIXTURE_ROOT/docs/infrastructure/contracts/media-capture.capability.json"
capability_detail="$FIXTURE_ROOT/docs/infrastructure/media-capture.md"
cp "$capability_schema" "$FIXTURE_ROOT/capability.schema.valid"
cp "$capability_contract" "$FIXTURE_ROOT/media-capture.capability.valid"
cp "$capability_detail" "$FIXTURE_ROOT/media-capture.valid"

assert_capability_contract_mutated() {
  local fixture_name="$1"
  if cmp -s \
    "$FIXTURE_ROOT/media-capture.capability.valid" \
    "$capability_contract"; then
    echo "错误：Capability Fixture 未实际命中：${fixture_name}。" >&2
    exit 1
  fi
}

assert_capability_contract_rejected() {
  local fixture_name="$1"
  assert_capability_contract_mutated "${fixture_name}"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 Capability ${fixture_name}。" >&2
    exit 1
  fi
  cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"
}

assert_capability_contract_rejected_with_diagnostic() {
  local fixture_name="$1"
  local expected_diagnostic="$2"
  local output
  local status
  assert_capability_contract_mutated "${fixture_name}"
  set +e
  output="$(run_check 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "错误：Harness Check 未拒绝 Capability ${fixture_name}。" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_diagnostic"* ]]; then
    echo "错误：Capability ${fixture_name} 未命中指定诊断：${expected_diagnostic}。" >&2
    exit 1
  fi
  cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"
}

mutate_capability_with_jq() {
  local filter="$1"
  local temporary="$capability_contract.jq.tmp"
  jq "$filter" "$capability_contract" > "$temporary"
  mv "$temporary" "$capability_contract"
}

# The Harness validates embedded non-media render-surface, bounded-copy, and
# bounded-stream fixtures so the Base Schema does not force Media Capture roles.
if ! run_check >/dev/null 2>&1; then
  echo "错误：通用 Capability Schema 未通过非媒体 surface/copy/stream 正例。" >&2
  exit 1
fi

sed -i.bak \
  's#urn:flutter-ai-harness:schema:native-capability:4#https://example.com/capability.schema.json#' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema 的占位网络 \$id。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/"streamingCopies": {/"missingStreamingCopies": {/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema 缺少通用 streaming copy 结构。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's|"items": {"$ref": "#/$defs/streamingCopyPolicy"}|"items": {"$ref": "#/$defs/boundedCopyPolicy"}|' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema streaming copy item 引用漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak 's/^  "additionalProperties": false/  "additionalProperties": true/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema 顶层自由结构。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/^    "capabilityVersion",/    "missing_capability_version",/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema 缺少必需版本字段。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's|"#/$defs/operation"|"#/$defs/dataShape"|' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema 损坏的 operation item 引用。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/^        "validFrom"$/        "missingValidFrom"/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema nested required 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/"recoverable": {"type": "boolean"}/"recoverable": {"type": "string"}/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema failure.recoverable nested 类型漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/"requiredForOperations": {/"requiredForOperationsMissing": {/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema permission resource nested 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/"multiplicity": {"$ref": "#\/$defs\/stableId"}/"multiplicity": {"type": "integer"}/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema state multiplicity nested 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/"expiresAfterSeconds": {"type": \["integer", "null"\], "minimum": 1}/"expiresAfterSeconds": {"type": "string"}/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema ownership nested 类型漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's/"renderSurfaces": {/"missingRenderSurfaces": {/' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema 缺少通用 render surface 结构。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

sed -i.bak \
  's|"items": {"$ref": "#/$defs/renderSurfacePolicy"}|"items": {"$ref": "#/$defs/attachmentPolicy"}|' \
  "$capability_schema"
rm -f -- "$capability_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability Schema render surface item 引用漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/capability.schema.valid" "$capability_schema"

for capability_field in \
  capabilityVersion \
  versionHistory \
  platform \
  operation \
  field \
  request \
  result \
  event \
  stateMachines \
  failure \
  permission \
  lifecycle \
  resourcePolicy; do
  cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"
  sed -i.bak \
    "s/^  \"$capability_field\":/  \"missing_$capability_field\":/" \
    "$capability_contract"
  rm -f -- "$capability_contract.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 Capability 缺少 $capability_field。" >&2
    exit 1
  fi
done
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/^  "contractId":/a\
  "extraField": true,' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability 未声明自由结构。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

for forbidden_capability_term in \
  Flutter \
  MethodChannel \
  'Wire DTO' \
  Proto \
  CameraX \
  AVFoundation; do
  cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"
  sed -i.bak \
    "s/Creates a cancellable session immediately/Uses $forbidden_capability_term in a cancellable session/" \
    "$capability_contract"
  rm -f -- "$capability_contract.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 Capability 中的 $forbidden_capability_term。" >&2
    exit 1
  fi
done
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  's/"supported": \["android", "ios"\]/"supported": ["android"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_mutated "iOS platform support"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability 缺少 iOS 支持。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  's/"ios_private_cache_mapping"/"ios_private_cache_mapping_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability 缺少 iOS 平台差异。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  -e 's/"android_private_cache_mapping"/"temporary_private_cache_mapping"/' \
  -e 's/"ios_private_cache_mapping"/"android_private_cache_mapping"/' \
  -e 's/"temporary_private_cache_mapping"/"ios_private_cache_mapping"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝平台差异 ID 与 platform 交换。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak 's/"take_photo"/"take-photo"/g' "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不稳定的 Capability 语义 ID。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  's#../../native/contracts/capability.schema.json#../../native/contracts/missing.schema.json#' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝错误的 Capability Schema 引用。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  's/^  "capabilityVersion":/  "wireVersion":/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝用 wireVersion 替代 capabilityVersion。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak 's/^  "capabilityVersion": 4/  "capabilityVersion": 5/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "未批准的 capabilityVersion 5"

sed -i.bak \
  '/"version": 2/,/"description":/ s/"changeKind": "additive"/"changeKind": "breaking"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "V2 缺少 additive 兼容历史"

sed -i.bak \
  '/"version": 1/,/"description":/ s/Established capture sessions/Overwritten legacy session semantics/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "V1 history description 被覆盖"

sed -i.bak \
  '/"version": 2/,/"description":/ s/Adds native-only render attachments/Overwrites the Version 2 render contract/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "V2 history description 被覆盖"

sed -i.bak \
  '/"version": 3/,/"description":/ s/"compatibleWith": \[1, 2, 3\]/"compatibleWith": [2, 3]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "V3 缩窄 V1/V2 兼容历史"

sed -i.bak \
  '/"version": 4/,/"description":/ s/"compatibleWith": \[1, 2, 3, 4\]/"compatibleWith": [2, 3, 4]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "V4 缩窄 V1-V3 兼容历史"

duplicate_surface_filter='
  .resourcePolicy.renderSurfaces as $surfaces
  | ($surfaces[0]
      | .mountSourceKindIds += ["external_unbounded_source"]
      | .platformImplementations[0] |= (
          .publicSurfaceType = "AnyObject"
          | .factoryOutputType = "AnyObject"
          | .targetConformance.factoryOutputType = "AnyObject"
          | .actualMountTargetIds += ["arbitrary_ui_target"]
          | .targetConformance.acceptedTargetKindIds += ["arbitrary_ui_target"]
          | .moduleOwnedRendererIds += ["external_unbounded_source"]
        )
    ) as $evil
  | .resourcePolicy.renderSurfaces = [$evil] + $surfaces
'
mutate_capability_with_jq "$duplicate_surface_filter"
assert_capability_contract_rejected \
  "前置恶意重复 surface policy 不得被后置正确项覆盖"

duplicate_surface_filter='
  .resourcePolicy.renderSurfaces as $surfaces
  | ($surfaces[0]
      | .mountSourceKindIds += ["external_unbounded_source"]
      | .platformImplementations[0] |= (
          .publicSurfaceType = "AnyObject"
          | .factoryOutputType = "AnyObject"
          | .targetConformance.factoryOutputType = "AnyObject"
          | .actualMountTargetIds += ["arbitrary_ui_target"]
          | .targetConformance.acceptedTargetKindIds += ["arbitrary_ui_target"]
          | .moduleOwnedRendererIds += ["external_unbounded_source"]
        )
    ) as $evil
  | .resourcePolicy.renderSurfaces = $surfaces + [$evil]
'
mutate_capability_with_jq "$duplicate_surface_filter"
assert_capability_contract_rejected \
  "后置恶意重复 surface policy 不得覆盖前置正确项"

duplicate_android_filter='
  .resourcePolicy.renderSurfaces[0].platformImplementations as $implementations
  | ($implementations[0]
      | .publicSurfaceType = "AnyObject"
      | .factoryOutputType = "AnyObject"
      | .targetConformance.factoryOutputType = "AnyObject"
      | .actualMountTargetIds += ["arbitrary_ui_target"]
      | .targetConformance.acceptedTargetKindIds += ["arbitrary_ui_target"]
        | .moduleOwnedRendererIds += ["external_unbounded_source"]
    ) as $evil
  | .resourcePolicy.renderSurfaces[0].platformImplementations =
      [$evil, $implementations[0]]
'
mutate_capability_with_jq "$duplicate_android_filter"
assert_capability_contract_rejected_with_diagnostic \
  "前置恶意重复 Android implementation 不得被正确项覆盖" \
  "包含重复 platform：android"

duplicate_android_filter='
  .resourcePolicy.renderSurfaces[0].platformImplementations as $implementations
  | ($implementations[0]
      | .publicSurfaceType = "AnyObject"
      | .factoryOutputType = "AnyObject"
      | .targetConformance.factoryOutputType = "AnyObject"
      | .actualMountTargetIds += ["arbitrary_ui_target"]
      | .targetConformance.acceptedTargetKindIds += ["arbitrary_ui_target"]
      | .moduleOwnedRendererIds += ["external_unbounded_source"]
    ) as $evil
  | .resourcePolicy.renderSurfaces[0].platformImplementations =
      [$implementations[0], $evil]
'
mutate_capability_with_jq "$duplicate_android_filter"
assert_capability_contract_rejected_with_diagnostic \
  "后置恶意重复 Android implementation 不得覆盖正确项" \
  "包含重复 platform：android"

duplicate_attachment_filter='
  .resourcePolicy.attachments as $attachments
  | ($attachments[0]
      | .description = "Malicious duplicate attachment policy."
    ) as $duplicate
  | .resourcePolicy.attachments = [$duplicate] + $attachments
'
mutate_capability_with_jq "$duplicate_attachment_filter"
assert_capability_contract_rejected_with_diagnostic \
  "重复 attachment policy ID" \
  "attachment policy 包含重复 id：live_preview_attachment_policy"

mutate_capability_with_jq '
  .resourcePolicy.renderSurfaces[1].attachmentPolicyId =
    .resourcePolicy.renderSurfaces[0].attachmentPolicyId
'
assert_capability_contract_rejected_with_diagnostic \
  "两个 render surface 引用同一 attachment policy" \
  "多个 render surface policy 不得引用同一 attachment policy：live_preview_attachment_policy"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/"diagnosticPolicy": {/"missingDiagnosticPolicy": {/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "live render surface 缺少结构化日志策略"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/"allowedFieldIds": \["record_kind", "operation_id", "lifecycle_state", "redacted_status", "stable_failure_id"\]/"allowedFieldIds": ["record_kind", "operation_id", "lifecycle_state", "redacted_status", "stable_failure_id", "surface_description"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render 日志白名单允许 surface description"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/, "owner_generation"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render 日志未禁止 owner generation"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/"valuePolicy": "stable_enum_or_redacted_status_only"/"valuePolicy": "arbitrary_description_allowed"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render 日志允许任意实例描述"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/"exceptionPolicy": "stable_failure_id_only_no_raw_exception"/"exceptionPolicy": "raw_exception_allowed"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render 日志允许 raw exception"

mutate_capability_with_jq '
  (.resourcePolicy.renderSurfaces[0].diagnosticPolicy.fieldValueSources[]
    | select(.fieldId == "operation_id").sourceKind) = "unbound_text"
'
assert_capability_contract_rejected_with_diagnostic \
  "operation 日志值来源类型漂移" \
  "diagnostic value source 必须逐字段绑定实际 Capability operation/state/failure 或声明 enum"

mutate_capability_with_jq '
  (.resourcePolicy.renderSurfaces[0].diagnosticPolicy.fieldValueSources[]
    | select(.fieldId == "lifecycle_state").reference.collectionId) = "operation"
'
assert_capability_contract_rejected_with_diagnostic \
  "lifecycle state 日志值引用漂移" \
  "diagnostic value source 必须逐字段绑定实际 Capability operation/state/failure 或声明 enum"

mutate_capability_with_jq '
  (.resourcePolicy.renderSurfaces[0].diagnosticPolicy.fieldValueSources[]
    | select(.fieldId == "operation_id").allowedValueIds) += ["undeclared_operation"]
'
assert_capability_contract_rejected_with_diagnostic \
  "日志允许伪 operation ID" \
  "diagnostic value source 必须逐字段绑定实际 Capability operation/state/failure 或声明 enum"

mutate_capability_with_jq '
  (.resourcePolicy.renderSurfaces[0].diagnosticPolicy.fieldValueSources[]
    | select(.fieldId == "lifecycle_state").allowedValueIds) += ["undeclared_state"]
'
assert_capability_contract_rejected_with_diagnostic \
  "日志允许伪 lifecycle state" \
  "diagnostic value source 必须逐字段绑定实际 Capability operation/state/failure 或声明 enum"

mutate_capability_with_jq '
  (.resourcePolicy.renderSurfaces[0].diagnosticPolicy.fieldValueSources[]
    | select(.fieldId == "stable_failure_id").allowedValueIds) += ["undeclared_failure"]
'
assert_capability_contract_rejected_with_diagnostic \
  "日志允许伪 stable Failure ID" \
  "diagnostic value source 必须逐字段绑定实际 Capability operation/state/failure 或声明 enum"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"actualMountRequired": true/"actualMountRequired": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render surface 缺少 actual mount"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/"nullable": false/"nullable": true/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "factory output 可为空但旧 actual-mount 标签不变"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"platformImplementations"/ s/"freshInstancePerInvocation": true/"freshInstancePerInvocation": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "factory output 可复用 identity adapter"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"closed": true/"closed": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "target conformance 非闭合集合但旧标签不变"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"acceptedTargetKindIds": \["android_preview_view", "android_surface_provider"\]/"acceptedTargetKindIds": ["android_preview_view", "android_surface_provider", "arbitrary_ui_target"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "closed conformance 接受 arbitrary target"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"endpointVisibility": "module_internal"/"endpointVisibility": "consumer_public"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "mount endpoint 泄漏给 consumer"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"backingTargetOwnerRoleId": "native_module"/"backingTargetOwnerRoleId": "native_consumer"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "backing target ownership 泄漏给 consumer"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"lifecycleOwnershipPhaseId": "live_render_surface_owner_scope"/"lifecycleOwnershipPhaseId": "media_consumer_lease"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "mount binding lifecycle 与 factory input 漂移"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"identityPolicy": "concrete_surface_instance_identity_not_token"/"identityPolicy": "identity_only_opaque_token"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render surface 退化为 identity-only opaque token"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"factoryPolicy": "module_defined_concrete_surface_factory_non_empty"/"factoryPolicy": "empty_factory"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render surface 使用空 factory"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"publicSurfaceType": "MediaCaptureRenderView"/"publicSurfaceType": "AnyObject"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render surface 公开 AnyObject"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"ownerAccessPolicy": "outer_surface_lifecycle_only_no_backing_source_renderer_or_binding_access"/"ownerAccessPolicy": "arbitrary_ui_and_sdk_source_access"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "surface owner 可持有裸 UI 或 SDK source"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"ownerAccessibleIds": \["concrete_outer_surface", "surface_lifecycle"\]/"ownerAccessibleIds": ["concrete_outer_surface", "capture_session_object", "preview_layer", "surface_provider", "path"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "surface owner 持有 Session layer provider 或 path"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"sourceOwner": "native_module"/"sourceOwner": "native_consumer"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render source ownership 泄漏给 UI"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"mountSourceKindIds"/ s/"platform": "ios"/"platform": "android"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "V3 render surface 缺少 iOS 实现"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"forbiddenRepresentationIds"/ s/"invalidate_callback_gate", "disconnect_source_session_or_player"/"disconnect_source_session_or_player", "invalidate_callback_gate"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render surface cleanup 未先 invalidate callback gate"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"forbiddenRepresentationIds"/ s/"compare_and_advance_high_watermark", "invalidate_callback_gate"/"invalidate_callback_gate", "compare_and_advance_high_watermark"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "fresh replacement 未先推进 generation high-watermark"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"forbiddenRepresentationIds"/ s/"staleMutationPolicy": "drop_without_surface_mutation"/"staleMutationPolicy": "allow_current_surface_mutation"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "旧 generation 可修改当前 surface"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"forbiddenRepresentationIds"/ s/"passiveFramePolicy": "framework_pipeline_without_synthetic_per_hardware_frame_callback"/"passiveFramePolicy": "synthetic_callback_for_each_hardware_frame"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "被动 pipeline 伪造逐硬件帧 callback"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"forbiddenRepresentationIds"/ s/"crossRuntimeProjection": "forbidden_native_only"/"crossRuntimeProjection": "encodable_surface_token"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "platform surface 可跨 Runtime 编码"

sed -i.bak \
  '/"id": "live_platform_render_surface_policy"/,/"forbiddenRepresentationIds"/ s/, "platform_sdk_source"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "render surface 未禁止 platform SDK source"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"consumerScope": "native_consumer_only"/"consumerScope": "cross_runtime"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "live preview 非 native_consumer_only"

sed -i.bak \
  '/"id": "unconfirmed_preview_render_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"consumerScope": "native_consumer_only"/"consumerScope": "cross_runtime"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "unconfirmed preview 非 native_consumer_only"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"maxConcurrentAttachments": 1/"maxConcurrentAttachments": 2/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "live preview 允许多个 attachment"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"sameGenerationSameTarget": "idempotent_only_while_current_binding_matches"/"sameGenerationSameTarget": "replace"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "同 generation attach 非幂等"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"freshGenerationPolicy": "strictly_greater_than_high_watermark"/"freshGenerationPolicy": "any_different_generation"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "不同 generation 未先 revoke"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"generationHighWatermark": "per_scope_monotonic_high_watermark"/"generationHighWatermark": "last_active_only"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "attachment 缺少 per-scope generation high-watermark"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"generationLinearization": "compare_and_advance_before_binding_mutation"/"generationLinearization": "advance_after_attach"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "stale attach 可在 binding mutation 后竞争"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"highWatermarkRetention": "until_scope_terminal_or_registry_invalidation"/"highWatermarkRetention": "until_detach"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "detach 提前丢失 generation high-watermark"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"retiredGenerationPolicy": "never_accept_below_high_watermark_or_detached_at_high_watermark"/"retiredGenerationPolicy": "accept_when_detached"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "retired generation 可重新 attach"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"sameGenerationDifferentTarget": "reject_without_binding_change"/"sameGenerationDifferentTarget": "replace_binding"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "same generation 可更换 target"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"staleAttachFailureId": "attachment_generation_retired"/"staleAttachFailureId": "invalid_state"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "stale attach 缺少稳定 Failure"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"staleAttachEffect": "reject_without_revoke_detach_callback_or_binding_change"/"staleAttachEffect": "revoke_then_reject"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "stale attach 影响当前 binding"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"staleDetachBehavior": "no_op_preserve_current_binding"/"staleDetachBehavior": "detach_current"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "旧 generation detach 拆除当前 binding"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"mismatchedDetachBehavior": "no_op_preserve_current_binding"/"mismatchedDetachBehavior": "detach_current"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "mismatched target detach 拆除当前 binding"

sed -i.bak \
  '/"id": "live_preview_detach_request"/ s/, "render_target_adapter"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "live detach request 缺少 adapter identity"

sed -i.bak \
  '/"id": "unconfirmed_preview_detach_request"/ s/, "render_target_adapter"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "unconfirmed detach request 缺少 adapter identity"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"detachMatchPolicy": "require_owner_generation_and_adapter_instance_identity"/"detachMatchPolicy": "require_owner_generation_only"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "adapter B 同 generation attach 冲突后可 detach adapter A"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"compare_and_advance_high_watermark", "revoke_old_callbacks", "detach_old_target", "attach_new_target", "commit_result"/"attach_new_target", "compare_and_advance_high_watermark", "revoke_old_callbacks", "detach_old_target", "commit_result"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "fresh generation replacement 先 attach new target"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"callbackThread": "owner_ui_thread"/"callbackThread": "arbitrary_thread"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "Render callback thread 漂移"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"callbackValidation": "active_scope_and_owner_generation_required"/"callbackValidation": "active_scope_only"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "旧 owner generation callback 可重新渲染"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"cleanupOrder": "invalidate_generation_stop_callbacks_detach_before_state_cleanup"/"cleanupOrder": "state_cleanup_before_detach"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "live preview cleanup 顺序漂移"

sed -i.bak \
  '/"id": "live_preview_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"resumePolicy": "explicit_attach_with_new_owner_generation"/"resumePolicy": "automatic_reuse_owner"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "前台恢复复用已销毁 owner"

sed -i.bak \
  '/"id": "unconfirmed_preview_render_attachment_policy"/,/"forbiddenRepresentationIds"/ s/"allowedStateIds": \["preview"\]/"allowedStateIds": ["leased"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "确认前 render scope 允许 leased"

sed -i.bak \
  '/"id": "unconfirmed_preview_render_attachment_policy"/,/"forbiddenRepresentationIds"/ s/, "confirm"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "confirm 遗漏 render revoke"

sed -i.bak \
  '/"id": "unconfirmed_preview_confirm_revoke"/ s/"order": "before_media_transfer"/"order": "after_media_transfer"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "confirm 未在 transfer 前清理 render scope"

sed -i.bak \
  '/"id": "render_target_adapter"/,/^    }/ s/"valueType": "callback_resource"/"valueType": "string"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "RenderTarget Adapter 退化为普通传输值"

sed -i.bak \
  '/"id": "owner_generation"/,/^    }/ s/"minimum": 1/"minimum": 0/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "owner generation 边界漂移"

sed -i.bak \
  '/"id": "read_media_thumbnail"/,/^    }/ s/"states": \["leased"\]/"states": ["preview"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "preview 状态读取 thumbnail"

sed -i.bak \
  '/"id": "read_media_thumbnail"/,/^    }/ s/"media_invalid"/"session_invalid"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 未知 handle Failure 漂移"

sed -i.bak \
  '/"id": "max_pixel_edge"/,/^    }/ s/"maximum": 512/"maximum": 513/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 512px 上限漂移"

sed -i.bak \
  '/"id": "thumbnail_byte_length"/,/^    }/ s/"maximum": 524288/"maximum": 524289/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 512KiB 上限漂移"

sed -i.bak 's/"image_jpeg_only"/"image_png_allowed"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail content type 非 image/jpeg"

sed -i.bak \
  '/"id": "copy_orientation_bound"/ s/"maximum": 0/"maximum": 90/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 非 upright orientation"

sed -i.bak \
  's/"source_lease_ttl_grace_tombstone_unchanged"/"source_lease_ttl_refreshed"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 延长媒体 lease"

sed -i.bak \
  '/"privacyPolicyIds"/ s/, "strip_thumbnail_exif"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 未清理 EXIF"

sed -i.bak \
  's/"video_target_minimum_of_1000_and_floor_duration_divided_by_2"/"video_first_frame"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "video poster target policy 漂移"

sed -i.bak \
  's/"target_then_nearest_after_else_nearest_before"/"nearest_before"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "video poster frame selection 漂移"

sed -i.bak \
  '/"id": "poster_frame_millis"/,/^    }/ s/"effect": "must_be_null"/"effect": "must_be_non_null"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "photo poster_frame_millis 非 null"

sed -i.bak \
  '/"forbiddenRepresentationIds": \["source_media_bytes"/ s/"source_media_bytes"/"sanitized_bytes"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 允许 source media bytes"

sed -i.bak \
  's/"backendDetailsPolicy": "redact_backend_decoder_details"/"backendDetailsPolicy": "expose_backend_exception"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 泄漏 backend decoder details"

sed -i.bak \
  's/"winnerPolicy": "first_terminal_trigger_wins"/"winnerPolicy": "platform_selected_winner"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail release 竞态顺序漂移"

sed -i.bak \
  's/"outcomeDelivery": "exactly_once"/"outcomeDelivery": "at_least_once"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail terminal outcome 非 exactly once"

sed -i.bak \
  's/"cleanupExecution": "exactly_once_for_non_success_winner"/"cleanupExecution": "once_per_trigger"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 多 trigger 重复 cleanup"

sed -i.bak \
  's/"successCommitEffect": "caller_copy_independent_and_never_revoked_by_later_source_state"/"successCommitEffect": "revoke_copy_on_release"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "result commit 先赢后 release 撤销 caller copy"

sed -i.bak \
  '/"triggerKind": "operation", "triggerId": "release_media"/ s/"triggerId": "release_media"/"triggerId": "lease_expired"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "release 与 TTL 成对竞态缺少唯一 trigger outcome"

sed -i.bak \
  '/"failureCleanupSequenceIds"/ s/, "unregister_managed_job"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "failure cleanup 未注销 managed job"

sed -i.bak \
  '/"failureCleanupSequenceIds"/ s/"wipe_generation_buffer", "discard_partial_copy", "unregister_managed_job"/"unregister_managed_job", "wipe_generation_buffer", "discard_partial_copy"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "failure cleanup 提前注销 managed job"

sed -i.bak \
  '/"failureCleanupSequenceIds"/ s/, "wipe_generation_buffer"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "failure cleanup 未擦除 generation buffer"

sed -i.bak \
  's/"successFinalizationExecution": "exactly_once_after_atomic_transfer_before_result_delivery"/"successFinalizationExecution": "once_per_observer"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "result commit success finalization 非 exactly once"

sed -i.bak \
  '/"successFinalizationSequenceIds"/ s/, "unregister_managed_job"//' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "success finalization 未注销 managed job"

sed -i.bak \
  '/"successFinalizationSequenceIds"/ s/"wipe_decoded_pixels", "wipe_generation_buffer", "unregister_managed_job"/"unregister_managed_job", "wipe_decoded_pixels", "wipe_generation_buffer"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "success finalization 提前注销 managed job"

sed -i.bak \
  '/"successFinalizationSequenceIds"/ s/"wipe_decoded_pixels", "wipe_generation_buffer"/"wipe_generation_buffer", "wipe_decoded_pixels"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "success finalization 擦除顺序漂移"

sed -i.bak \
  '/"id": "thumbnail_success_finalization"/ s/"run_thumbnail_success_finalization_sequence"/"preserve_resources"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "success cleanup rule 未执行 finalization sequence"

sed -i.bak \
  '/^  "lifecycle": {/,/^  "resourcePolicy": {/ s/"id": "thumbnail_result_committed"/"id": "thumbnail_result_committed_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "success finalization 缺少 lifecycle trigger"

sed -i.bak \
  '/"raceArbitration": {/,/"triggerPolicies": \[/ s/"revoke_source_access", "cancel_and_await_decoder"/"cancel_and_await_decoder", "revoke_source_access"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail cleanup 未先 revoke source access"

sed -i.bak \
  '/"preAccessRegistration"/ s/"required": true/"required": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail source access 前未登记 managed job"

sed -i.bak \
  '/"scopeRoleId": "source_scope"/ s/"maximum": 1/"maximum": 2/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "同一 Media thumbnail 并发上限漂移"

sed -i.bak \
  '/"scopeRoleId": "module_scope", "maximum": 2/ s/"maximum": 2/"maximum": 3/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "同一 Module thumbnail 并发上限漂移"

sed -i.bak \
  '/"id": "decoded_pixel_budget"/ s/"maximum": 1048576/"maximum": 1048577/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail decoded pixel 预算漂移"

sed -i.bak \
  '/"id": "job_working_memory_budget"/ s/"maximum": 8388608/"maximum": 8388609/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail job working-memory 预算漂移"

sed -i.bak \
  's/"sourceReductionPolicy": "decode_time_subsample_before_full_resolution_allocation"/"sourceReductionPolicy": "decode_full_resolution_then_scale"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail 未在 decode-time subsample"

sed -i.bak \
  's/"overloadFailureId": "thumbnail_overloaded"/"overloadFailureId": "encoding_failed"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail overload Failure 漂移"

sed -i.bak \
  '/"id": "thumbnail_release_cleanup"/ s/"run_thumbnail_generation_cleanup_sequence"/"discard_partial_copy"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail cleanup 只丢弃 copy"

sed -i.bak \
  '/"id": "thumbnail_copy"/ s/"physicalOwner": "caller"/"physicalOwner": "native_module"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "commit 后 thumbnail copy 仍归 Module 所有"

sed -i.bak \
  '/"ownershipTransfer"/,/},/ s/"atomic": true/"atomic": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail ownership transfer 非原子"

sed -i.bak \
  's/"no_sensitive_thumbnail_cache_key"/"sensitive_thumbnail_cache_key_allowed"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected "thumbnail cache key 隐私策略缺失"

mutate_capability_with_jq '
  .field |= map(if .id == "media_copy_sink" then
    .valueType = "string" | .validation.format = "path"
  else . end)
'
assert_capability_contract_rejected "export sink 退化为路径字符串"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sourceRepresentations |= map(
    if .sourceValueId == "photo" then .contentType = "image/png" else . end
  )
'
assert_capability_contract_rejected "export photo MIME literal 漂移"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sourceRepresentations |= map(
    select(.sourceValueId != "video")
  )
'
assert_capability_contract_rejected "export source representation 缺项"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sourceRepresentations += [{
    "sourceValueId": "audio",
    "formatId": "audio_aac",
    "contentType": "audio/aac"
  }]
'
assert_capability_contract_rejected "export source representation 额外项"

for forbidden_export_representation in path uri file_descriptor; do
  mutate_capability_with_jq ".resourcePolicy.streamingCopies[0].forbiddenRepresentationIds -= [\"$forbidden_export_representation\"]"
  assert_capability_contract_rejected \
    "export 未禁止 $forbidden_export_representation"
done

mutate_capability_with_jq '
  .result |= map(if .id == "media_export_result" then
    .fieldIds += ["thumbnail_copy"]
  else . end)
'
assert_capability_contract_rejected "export result 返回 raw bytes copy"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sinkProtocol.serializationPolicy = "allowed"
'
assert_capability_contract_rejected "export sink 可序列化"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sinkProtocol.registryStoragePolicy = "retain_in_module_registry"
'
assert_capability_contract_rejected "export sink 可持久保存在 Module registry"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sinkProtocol.methods |= map(select(.phase != "abort"))
'
assert_capability_contract_rejected "export sink 缺少 abort"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sinkProtocol.terminalExclusivity = "commit_and_abort"
'
assert_capability_contract_rejected "export sink 允许 commit 与 abort 双终态"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].bounds |= map(
    if .id == "chunk_buffer_bound" then .maximum = null else . end
  )
'
assert_capability_contract_rejected "export sink chunk 无上限"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].bounds |= map(
    if .id == "requested_export_length_bound" then .maximum = 52428801 else . end
  )
'
assert_capability_contract_rejected "export 50 MiB 上限漂移"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.lengthCheckIds -= ["declared_length_before_copy"]
'
assert_capability_contract_rejected "export 缺少声明长度预检"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.lengthCheckIds -= ["cumulative_length_before_each_write"]
'
assert_capability_contract_rejected "export 未拒绝复制中增长"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.lengthCheckIds -= ["actual_equals_declared_before_commit"]
'
assert_capability_contract_rejected "export 未拒绝截断或最终长度不一致"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.fullBufferingPolicy = "load_complete_source_into_memory"
'
assert_capability_contract_rejected "export 允许完整视频进入内存"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.concurrencyBounds |= map(
    if .scopeRoleId == "source_scope" then .maximum = 2 else . end
  )
'
assert_capability_contract_rejected "同一 Media export job 上限漂移"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.concurrencyBounds |= map(
    if .scopeRoleId == "module_scope" then .maximum = 5 else . end
  )
'
assert_capability_contract_rejected "同一 Module export job 上限漂移"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.workBudgets |= map(
    if .id == "export_module_buffer_budget" then .maximum = 1048577 else . end
  )
'
assert_capability_contract_rejected "export Module buffer 预算漂移"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.atomicReservation = false
'
assert_capability_contract_rejected "export job/buffer 非原子预留"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.capacityPolicy = "wait_or_evict_existing_job"
'
assert_capability_contract_rejected "export overload 调用 sink 或逐出既有 job"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.deadlineSeconds = 121
'
assert_capability_contract_rejected "export 120 秒 deadline 漂移"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sinkProtocol.cancellationAware = false
'
assert_capability_contract_rejected "export sink 可忽略取消并永久不返回"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sinkProtocol.cancellationConvergenceSeconds = 6
'
assert_capability_contract_rejected "export sink 取消收敛超过 5 秒"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].execution.lateResultPolicy = "commit_late_sink_result"
'
assert_capability_contract_rejected "export 晚到 sink result 可二次完成"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].failureBehaviors |= map(
    if .failureId == "invalid_state" then .sinkActionId = "not_invoked" else . end
  )
'
assert_capability_contract_rejected "export release/expiry 赢家未 abort begun sink"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].terminalPolicy.failureCleanupSequenceIds -= ["abort_sink_once_if_begun"]
'
assert_capability_contract_rejected "export failure cleanup 缺少 abort"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].terminalPolicy.failureCleanupSequenceIds |=
    (["unregister_export_job"] + map(select(. != "unregister_export_job")))
'
assert_capability_contract_rejected "export cleanup 提前注销 job/buffer"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sourceLeasePolicy = "auto_release_after_sink_commit"
'
assert_capability_contract_rejected "export 成功自动 release source lease"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].sourceLeasePolicy = "refresh_source_ttl_and_grace"
'
assert_capability_contract_rejected "export 刷新 source TTL/grace"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].backendDetailsPolicy = "log_handle_path_sink_os_error_and_exception"
'
assert_capability_contract_rejected "export 日志泄漏敏感 details"

mutate_capability_with_jq '
  .resourcePolicy.streamingCopies[0].failureBehaviors |= map(
    if .failureId == "media_export_write_failed" then
      .failureId = "export_failed"
    else . end
  )
'
assert_capability_contract_rejected "export Failure taxonomy 退化为 export_failed"

mutate_capability_with_jq '
  .resourcePolicy.resources |= map(select(.id != "media_export_buffer"))
'
assert_capability_contract_rejected "export 缺少 managed buffer resource"

mutate_capability_with_jq '
  .resourcePolicy.cleanup |= map(
    if .id == "media_export_core_close_cleanup" then
      .action = "preserve_active_export"
    else . end
  )
'
assert_capability_contract_rejected "Core close 遗漏 export cleanup"

sed -i.bak \
  '/"id": "confirm"/,/^    }/ s/"resultId": "confirmed_media"/"resultId": "media_released"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Capability operation 错误的结果映射。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "confirm"/,/^    }/ s/"resultScope": "session"/"resultScope": "media"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝跨状态机 operation 错误的 resultScope。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "media"/,/^    }/ s/"triggerId": "retake", "fromStates": \["preview"\], "toState": "discarded", "outcome": "success", "emission": {"kind": "none", "id": null}/"triggerId": "retake", "fromStates": ["preview"], "toState": "discarded", "outcome": "success", "emission": {"kind": "result", "id": "retake_ready"}/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 retake companion scope 重复交付 result。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"triggerId": "retake", "fromStates": \["previewing"\]/ s/"emission": {"kind": "result", "id": "retake_ready"}/"emission": {"kind": "none", "id": null}/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 retake resultScope 零次交付 result。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "start_session"/,/^    }/ s/"session_ready", //' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 start_session 缺少 readiness event。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "stop_recording"/,/^    }/ s/"invalid_argument"/"unknown_failure"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 operation 引用未知 failureId。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/^  "event": \[/,/^  ],/ s/"id": "session_ready"/"id": "session_ready_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺失的 session_ready event 定义。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"triggerId": "start_session"/ s/"emission":/"missingEmission":/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transition 缺少 emission。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "confirmed_media"/,/^    }/ s/"media_handle"/"media_handle_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 confirmed_media 缺少 opaque media handle。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "duration_millis"/,/"enumValues":/ s/"required": true/"required": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 duration_millis 可选性漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "max_video_duration_millis"/,/^    }/ s/"maximum": 60000/"maximum": 60001/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝最大录像时长边界漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "normalized_x"/,/^    }/ s/"maximum": 1/"maximum": 2/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 focus 坐标边界漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "zoom_factor"/,/^    }/ s/"outOfRangePolicy": "reject"/"outOfRangePolicy": "clamp"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 zoom 越界策略漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "orientation_degrees"/,/^    }/ s/\[0, 90, 180, 270\]/[0, 90, 180, 270, 360]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 orientation allowed integer 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "duration_millis"/,/^    }/ s/"effect": "must_be_null"/"effect": "must_be_non_null"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝照片 duration 条件规则漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "content_type"/,/^    }/ s/"format": "mime_type"/"format": "none"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 MIME format 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "set_zoom"/,/^    }/ s/"invalid_argument", //' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝结构化 request 校验缺少 invalid_argument。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "session_ready"/,/^    }/ s/"max_zoom_factor"/"max_zoom_factor_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Session 启动能力快照字段缺失。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  's/"per_handle_multiple"/"single_active"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 Media lease 合并为单一全局状态。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "set_zoom"/,/^    }/ s/\["ready", "recording"\]/["ready"]/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_mutated "set_zoom validFrom"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 operation validFrom 与 transition 不一致。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "retake"/,/^    }/ s/"scope": "media"/"scope": "session"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 operation 缺少已声明 scope 的 validFrom。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

awk '
  { print }
  !inserted && $0 == "      \"transitions\": [" {
    print "        {"
    print "          \"triggerKind\": \"operation\","
    print "          \"triggerId\": \"start_session\","
    print "          \"fromStates\": ["
    print "            \"idle\""
    print "          ],"
    print "          \"toState\": \"requesting_permission\","
    print "          \"outcome\": \"success\","
    print "          \"emission\": {\"kind\": \"result\", \"id\": \"session_created\"}"
    print "        },"
    inserted = 1
  }
' "$capability_contract" > "$capability_contract.tmp"
mv "$capability_contract.tmp" "$capability_contract"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝重复的 Capability state transition。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"triggerId": "permission_resolved"/,/"outcome":/ s/"toState": "preparing"/"toState": "requesting_permission"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝包含不可达状态的 Session 状态机。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "completed"/,/^        }/ s/"terminal": true/"terminal": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 state terminal 标记与列表不一致。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"triggerId": "video_duration_reached"/ s/"media_preview_ready"/"session_ready"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝自动录像时长 transition 错误的 event。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "session_timeout"/ s/"terminal": true/"terminal": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 terminal_failure_id 与 Failure terminal 标记不一致。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/^  "lifecycle": {/,/^  "resourcePolicy": {/ s/"id": "permission_resolved"/"id": "permission_rule_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝未在 lifecycle.rules 声明的状态 trigger。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "media"/,/^    }/ s/"triggerId": "preview_timed_out"/"triggerId": "capability_failure"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝未闭合的预览超时清理状态。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "microphone"/,/"requestPolicy":/ s/"start_recording"/"take_photo"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Microphone 权限与录像操作关联漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "session_handle_policy"/ s/"pathDerived": false/"pathDerived": true/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝从文件路径派生 opaque handle。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak 's/"format": "opaque_handle"/"format": "file_path"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝用文件路径替代 opaque media handle。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  's/"generationStrategy": "cryptographically_secure_random"/"generationStrategy": "sequential_counter"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_mutated "predictable Handle generation"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝可预测的 Handle generation strategy。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "media_handle_policy"/ s/"minimumEntropyBits": 128/"minimumEntropyBits": 64/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Handle 最小熵位数漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "session_handle_policy"/ s/"strictRegistryLookup": true/"strictRegistryLookup": false/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝非严格 Handle registry lookup。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "session_handle_policy"/ s/"tombstoneTtlSeconds": 300/"tombstoneTtlSeconds": 301/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Session tombstone TTL 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "session_handle_policy"/ s/"expiredFailureId": "session_invalid"/"expiredFailureId": "invalid_state"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 tombstone 到期映射为 invalid_state。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "media_preview"/ s/"expiresAfterSeconds": 600/"expiresAfterSeconds": 1/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_mutated "media preview TTL"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝预览 TTL 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "confirmed_media_lease"/ s/"ttlSeconds": 86400/"ttlSeconds": 1/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_mutated "confirmed media lease TTL"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝确认租约 TTL 与文档不一致。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"id": "confirmed_media_lease"/ s/"activeReadGraceSeconds": 60/"activeReadGraceSeconds": 61/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝读取 grace 超过 60 秒。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak '/"id": "session_handle_policy"/p' "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝重复的 Handle policy。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak '/"id": "retake_cleanup"/p' "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝重复的 cleanup rule。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak 's/"cancel_cleanup"/"cancel_cleanup_missing"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不完整的取消清理策略。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak \
  '/"triggerId": "cancel"/,/"outcome":/ s/"outcome": "cancelled"/"outcome": "failure"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把用户取消映射为 Failure。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

sed -i.bak '/media-capture.md/d' \
  "$FIXTURE_ROOT/docs/infrastructure-modules.md"
rm -f -- "$FIXTURE_ROOT/docs/infrastructure-modules.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝基础模块索引缺少 Media Capture。" >&2
  exit 1
fi
write_native_architecture_documents

sed -i.bak '/Capability JSON Schema/d' "$capability_detail"
rm -f -- "$capability_detail.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Media Capture 详情缺少 Schema 链接。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.valid" "$capability_detail"

sed -i.bak \
  '/"id": "live_platform_render_surface"/,/"storageScope"/ s/"id": "live_platform_render_surface"/"id": "live_platform_render_surface_delta_drift"/' \
  "$capability_contract"
rm -f -- "$capability_contract.bak"
assert_capability_contract_rejected_with_diagnostic \
  "Capability V3 additive surface resource delta drift" \
  "Capability V3 additive transport delta 必须精确包含 2 个 surface resource"
cp "$FIXTURE_ROOT/media-capture.capability.valid" "$capability_contract"

if ! run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未通过 Wire V2 对 Capability V2/V3 的双 projection 正例。" >&2
  exit 1
fi

projection_mutant_dir="$FIXTURE_PARENT/projection-mutant"
projection_mutant="$projection_mutant_dir/harness_check.dart"
mkdir -p "$projection_mutant_dir"
cp "$ROOT/app/tool/codex_adapters.dart" "$projection_mutant_dir/"
cp "$ROOT/app/tool/implementation_digest.dart" "$projection_mutant_dir/"

prepare_projection_mutant() {
  cp "$ROOT/app/tool/harness_check.dart" "$projection_mutant"
}

assert_projection_mutant_rejected() {
  local fixture_name="$1"
  local output
  local status
  if cmp -s "$ROOT/app/tool/harness_check.dart" "$projection_mutant"; then
    echo "错误：V4 projection Fixture 未实际命中：${fixture_name}。" >&2
    exit 1
  fi
  set +e
  output="$(run_dart_script "$projection_mutant" --root "$FIXTURE_ROOT" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "错误：Harness Check 未拒绝 ${fixture_name}。" >&2
    exit 1
  fi
  if [[ "$output" != *"Capability V3 transport projection"* ]]; then
    echo "错误：${fixture_name} 未命中 V3 projection 隔离诊断。" >&2
    exit 1
  fi
}

prepare_projection_mutant
sed -i.bak \
  "s/removeIds(projection, 'operation', const {'copy_confirmed_media_to_sink'});/removeIds(projection, 'operation', const {});/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export operation 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/removeIds(projection, 'field'/,/});/ s/'media_copy_sink'/'media_copy_sink_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 sink field 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "s/removeIds(projection, 'request', const {'media_export_request'});/removeIds(projection, 'request', const {});/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export request 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "s/removeIds(projection, 'result', const {'media_export_result'});/removeIds(projection, 'result', const {});/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export result 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/removeIds(projection, 'failure'/,/});/ s/'media_export_conflict'/'media_export_conflict_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export failure 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/removeIds(lifecycle/,/});/ s/'media_export_cancel_requested'/'media_export_cancel_requested_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export lifecycle rule 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "s/transition\['triggerId'\] != 'copy_confirmed_media_to_sink'/transition['triggerId'] != 'copy_confirmed_media_to_sink_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export transition 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/'resources', const {/,/});/ s/'media_export_job'/'media_export_job_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export resource 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/'ownershipPhases', const {/,/});/ s/'media_export_job_scope'/'media_export_job_scope_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export ownership 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/'cleanup', const {/,/});/ s/'media_export_release_cleanup'/'media_export_release_cleanup_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export cleanup 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/'privacy', const {/,/});/ s/'media_export_sink_native_only'/'media_export_sink_native_only_projection_guard_disabled'/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 export privacy policy 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "s/resourcePolicy?\['streamingCopies'\] = <Object?>\[\];/resourcePolicy?['streamingCopies'] = resourcePolicy?['streamingCopies'];/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 streaming policy 泄漏到 V3/V2 projection"

prepare_projection_mutant
sed -i.bak \
  "/_buildMediaCaptureV3TransportProjection/,/return projection;/ s/if (entry\['version'\] != 4) entry/if (entry['version'] != 5) entry/" \
  "$projection_mutant"
rm -f -- "$projection_mutant.bak"
assert_projection_mutant_rejected "V4 history 泄漏到 V3/V2 projection"

rm -f -- \
  "$FIXTURE_ROOT/capability.schema.valid" \
  "$FIXTURE_ROOT/media-capture.capability.valid" \
  "$FIXTURE_ROOT/media-capture.valid"

wire_schema="$FIXTURE_ROOT/docs/bridge/contracts/wire.schema.json"
wire_contract="$FIXTURE_ROOT/docs/bridge/contracts/media-capture.wire.json"
wire_detail="$FIXTURE_ROOT/docs/bridge/media-capture.md"
cp "$wire_schema" "$FIXTURE_ROOT/wire.schema.valid"
cp "$wire_contract" "$FIXTURE_ROOT/media-capture.wire.valid"
cp "$wire_detail" "$FIXTURE_ROOT/media-capture.bridge.valid"

assert_wire_contract_mutated() {
  local fixture_name="$1"
  if cmp -s "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"; then
    echo "错误：Wire Fixture 未实际命中：${fixture_name}。" >&2
    exit 1
  fi
}

assert_wire_contract_rejected_with_diagnostic() {
  local fixture_name="$1"
  local expected_diagnostic="$2"
  local output
  local status
  assert_wire_contract_mutated "${fixture_name}"
  set +e
  output="$(run_check 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "错误：Harness Check 未拒绝 ${fixture_name}。" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_diagnostic"* ]]; then
    echo "错误：Wire ${fixture_name} 未命中指定诊断：${expected_diagnostic}。" >&2
    exit 1
  fi
}

mutate_wire_with_jq() {
  local filter="$1"
  local temporary="$wire_contract.jq.tmp"
  jq "$filter" "$wire_contract" > "$temporary"
  mv "$temporary" "$wire_contract"
}

assert_wire_schema_mutated() {
  local fixture_name="$1"
  if cmp -s "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"; then
    echo "错误：Wire Schema Fixture 未实际命中：${fixture_name}。" >&2
    exit 1
  fi
}

assert_wire_schema_rejected_with_diagnostic() {
  local fixture_name="$1"
  local expected_diagnostic="$2"
  local output
  local status
  assert_wire_schema_mutated "${fixture_name}"
  set +e
  output="$(run_check 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "错误：Harness Check 未拒绝 Wire Schema ${fixture_name}。" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected_diagnostic"* ]]; then
    echo "错误：Wire Schema ${fixture_name} 未命中指定诊断：${expected_diagnostic}。" >&2
    exit 1
  fi
}

sed -i.bak \
  '/"capabilityFieldId": "enabled_media_types"/,/"conditionalRules"/ s/"wireType": "list_string"/"wireType": "string"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Capability V2 existing field mapping drift" \
  "Capability V2 transport projection fieldMapping enabled_media_types 必须完整保留 Capability 类型、可选性与 validation"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

awk '
  { print }
  $0 == "  \"fieldMappings\": [" {
    print "    {\"capabilityFieldId\": \"render_target_adapter\", \"key\": \"renderTargetAdapter\", \"wireType\": \"bytes\", \"required\": true, \"nullable\": false, \"enumValues\": [], \"validation\": {\"finite\": false, \"minimum\": null, \"maximum\": null, \"allowedIntegers\": [], \"minItems\": null, \"maxItems\": null, \"format\": \"none\", \"boundarySource\": null, \"outOfRangePolicy\": \"not_applicable\", \"conditionalRules\": []}},"
  }
' "$wire_contract" > "$wire_contract.tmp"
mv "$wire_contract.tmp" "$wire_contract"
assert_wire_contract_rejected_with_diagnostic \
  "Native Render target bytes field mapping" \
  "fieldMappings 必须精确映射可跨 Channel 的 Capability fields"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

awk '
  { print }
  $0 == "  \"payloads\": [" {
    print "    {\"id\": \"live_preview_attachment_request_payload\", \"kind\": \"request\", \"capabilityShapeId\": \"live_preview_attachment_request\", \"fieldIds\": [\"session_handle\", \"render_target_adapter\", \"owner_generation\"], \"unknownFieldPolicy\": \"reject\"},"
  }
' "$wire_contract" > "$wire_contract.tmp"
mv "$wire_contract.tmp" "$wire_contract"
assert_wire_contract_rejected_with_diagnostic \
  "Native Render payload insertion" \
  "live_preview_attachment_request_payload 引用了未映射或不存在的 Capability shape"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

awk '
  { print }
  $0 == "  \"events\": [" {
    print "    {\"id\": \"render_attachment_revoked\", \"channelId\": \"events\", \"capabilityEventId\": \"render_attachment_revoked\", \"payloadId\": \"render_attachment_revoked_event_payload\", \"platformSupport\": {\"android\": \"supported\", \"ios\": \"supported\"}},"
  }
' "$wire_contract" > "$wire_contract.tmp"
mv "$wire_contract.tmp" "$wire_contract"
assert_wire_contract_rejected_with_diagnostic \
  "Native Render event insertion" \
  "events 必须映射全部可跨 Channel 的 Capability events"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

awk '
  { print }
  $0 == "  \"methods\": [" {
    print "    {\"id\": \"attach_live_preview\", \"kind\": \"direct_operation\", \"channelId\": \"commands\", \"capabilityOperationId\": \"attach_live_preview\", \"requestPayloadId\": \"live_preview_attachment_request_payload\", \"resultPayloadId\": \"render_attachment_attached_result_payload\", \"resultType\": \"render_attachment_attached\", \"errorCodes\": [\"invalid_wire_payload\"], \"completion\": \"exactly_once\", \"platformSupport\": {\"android\": \"supported\", \"ios\": \"supported\"}},"
  }
' "$wire_contract" > "$wire_contract.tmp"
mv "$wire_contract.tmp" "$wire_contract"
assert_wire_contract_rejected_with_diagnostic \
  "Native Render method insertion" \
  "methods 必须精确包含可传输 Capability operation 与 presentation"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "live_platform_render_surface_policy"/d' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "missing Capability V3 surface policy coverage" \
  "native artifact coverage 必须逐项对照 Capability V3"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "surface_instance"/,/"reason"/ s/"native_consumer_only"/"intentionally_not_exposed"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Capability V3 factory output disposition drift" \
  "factory_output|live_platform_render_surface_policy|shared|surface_instance 必须保持 Native-only"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "ios_player_layer"/,/"reason"/ s/"platform": "ios"/"platform": "android"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Capability V3 Native artifact platform drift" \
  "native artifact coverage 必须逐项对照 Capability V3"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "live_platform_render_surface"/d' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "missing Capability V3 surface resource coverage" \
  "resource coverage 必须逐项覆盖 Capability resource ownership 集合"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "live_render_surface_owner_scope"/d' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "missing Capability V3 surface ownership coverage" \
  "ownership scope coverage 必须逐项覆盖 Capability resource ownership 集合"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak 's/^  "wireVersion": 3,/  "wireVersion": 2,/' "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Wire Version downgraded below Capability V4 transfer" \
  "必须独立声明 wireVersion 3"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"compatibleCapabilityVersions": \[/,/^    \]/ s/4/3/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Capability V4 compatibility omitted" \
  "Wire V3 必须精确兼容 Capability V4"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"wireVersion": 1/,/"description"/ s/"wireVersion": 1/"wireVersion": 2/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Wire V1 history compatibility rewritten" \
  "changeLog 必须保留 Wire V1 history"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"no_native_render_path_bytes_fallback"/"native_render_path_bytes_fallback_allowed"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_rejected_with_diagnostic \
  "Native Render path bytes fallback" \
  "security policies 不完整"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"nativeArtifactCoverageEntry": {/,/"platformContract": {/ s/"wireId": {"type": "null"}/"wireId": {"$ref": "#\/$defs\/nullableStableId"}/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
assert_wire_schema_rejected_with_diagnostic \
  "Native artifact wireId 放宽为 nullableStableId" \
  "Base Native artifact wireId 必须固定为 null"
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  '/"nativeArtifactCoverageEntry": {/,/"platformContract": {/ s/"reason": {"$ref": "#\/$defs\/nonEmptyString"}/"reason": {"$ref": "#\/$defs\/nullableString"}/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
assert_wire_schema_rejected_with_diagnostic \
  "Native artifact reason 放宽为 nullableString" \
  "Base Native artifact reason 必须引用 nonEmptyString"
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's#urn:flutter-ai-harness:schema:bridge-wire:2#https://example.com/wire.schema.json#' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Wire Schema 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's/"opaqueHandles": {"type": "array", "uniqueItems"/"opaqueHandles": {"type": "array", "minItems": 1, "uniqueItems"/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Base Wire Schema 强制 opaque handle 非空集合。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's/"signedInteger": {"oneOf": \[{"$ref": "#\/$defs\/signedIntegerConstraint"}, {"type": "null"}\]}/"signedInteger": {"$ref": "#\/$defs\/signedIntegerConstraint"}/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Base Wire Schema 强制所有契约声明整数边界。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's/"required": \["dataClassifications", "policies"\]/"required": ["mediaTransfer", "pathTransfer"]/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Base Wire Schema 内置 Media 专属安全字段。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's/"required": \["requestEnvelope", "resultEnvelope", "methodCompletion", "callbackThread"\]/"required": ["requestEnvelope", "resultEnvelope", "eventEnvelope", "failureEnvelope", "listenerPolicy", "boundaries", "methodCompletion", "callbackThread"]/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Base lifecycle 强制 Event/Failure/listener/boundary。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's/"required": \["requestEnvelope", "resultEnvelope", "methodCompletion", "callbackThread"\]/"required": ["requestEnvelope", "resultEnvelope", "resourceAdoptionPolicies", "linearizationPolicy", "methodCompletion", "callbackThread"]/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Base lifecycle 强制资源 adoption/linearization。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"

sed -i.bak \
  's/"required": \["id", "description", "actions"\]/"required": ["id", "description", "activeSession", "confirmedMedia", "actions"]/' \
  "$wire_schema"
rm -f -- "$wire_schema.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Base boundary 强制 Session/Media 资源字段。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/wire.schema.valid" "$wire_schema"
run_check >/dev/null

for wire_field in \
  wireVersion \
  capability \
  channels \
  fieldMappings \
  transportConstraints \
  payloads \
  failurePayloads \
  methods \
  failureDelivery \
  events \
  asyncFailures \
  errors \
  errorDetailFields \
  coverage \
  platform \
  lifecycle \
  security; do
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
  sed -i.bak \
    "s/^  \"$wire_field\":/  \"missing_$wire_field\":/" \
    "$wire_contract"
  rm -f -- "$wire_contract.bak"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 Wire 缺少 $wire_field。" >&2
    exit 1
  fi
done
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/^  "wireVersion":/  "capabilityVersion":/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝只声明 capabilityVersion 的 Wire。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"compatibleCapabilityVersions": \[/,/^    \]/ s/4/1/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "compatible Capability version"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Wire V3 扩大到 Capability V1。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"compatibleCapabilityVersions": \[/,/^    \]/ s/4/3/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "越界 staged compatible Capability versions"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 把 V3→V4 transfer 兼容窗口泛化到了任意落后/未来版本。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/^  "contractId":/a\
  "freeForm": {},' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Wire 顶层自由结构。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "commands"/,/"name"/ s/"id": "commands"/"id": "commands_missing"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少固定 commands Channel。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "media_preview_result_payload"/,/"unknownFieldPolicy"/ { /"byte_length"/d; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Payload 缺少 Capability field 映射。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"capabilityOperationId": "take_photo"/"capabilityOperationId": "unknown_operation"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝无法追溯的 Wire operation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

for forbidden_wire_type in \
  uint8_list \
  proto \
  camerax \
  avfoundation \
  map \
  file_path; do
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
  sed -i.bak \
    "/\"capabilityFieldId\": \"media_handle\"/,/\"conditionalRules\"/ s/\"wireType\": \"string\"/\"wireType\": \"$forbidden_wire_type\"/" \
    "$wire_contract"
  rm -f -- "$wire_contract.bak"
  assert_wire_contract_mutated "$forbidden_wire_type wire type"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝 Wire 类型：$forbidden_wire_type。" >&2
    exit 1
  fi
done
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "media_handle"/,/"conditionalRules"/ s/"key": "mediaHandle"/"key": "filePath"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把任意 path 当作媒体字段。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "take_photo"/,/"platformSupport"/ s/"id": "take_photo"/"id": "take-photo"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不符合 snake_case 的 method。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "session_ready"/,/"platformSupport"/ s/"id": "session_ready"/"id": "session-ready"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不符合 snake_case 的 event。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"code": "invalid_wire_payload"/"code": "invalid-wire-payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不符合 snake_case 的 error code。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "media_type"/,/"validation"/ s/"photo"/"Photo"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不符合 snake_case 的 enum wire value。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "take_photo"/,/"ios"/ s/"android": "supported"/"android": "unsupported"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "take_photo platform support"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Android/iOS method 支持矩阵漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "open_media_read"/,/"reason"/ s/"disposition": "native_consumer_only"/"disposition": "exposed_method"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "open_media_read exposure"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝跨 Channel 暴露 callback-scoped media read。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "max_video_duration_millis"/,/"conditionalRules"/ s/"maximum": 60000/"maximum": 60001/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Wire validation 与 Capability 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "take_photo"/,/"platformSupport"/ s/"resultType": "media_preview"/"resultType": "confirmed_media"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 method resultType 与 Capability resultId 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityOperationId": "start_session"/,/"deferredFailureIds"/ s/"invalid_argument",/"invalid_argument", "permission_denied",/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "start_session Failure delivery"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 start_session direct/deferred Failure 重叠。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"eventListenEnvelope"/,/]/ s/"wireVersion"/"wireVersion", "payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 EventChannel listen envelope 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "session_timeout"/,/"ios"/ s/"capabilityTriggerId": "preview_timed_out"/"capabilityTriggerId": "capability_failure"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 async Failure 脱离 Capability failure emission。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "session_timeout"/,/"ios"/ s/"sinkBehavior": "continue"/"sinkBehavior": "terminate"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 session_timeout Failure 终止 event sink。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "session_timeout_failure_payload"/,/"unknownFieldPolicy"/ s/"session_handle"/"media_handle"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 async Failure 错误的 Session context。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"sessionFailedEventCorrelation"/,/"listenerPolicy"/ s/"independent_session_terminal_notification_never_method_completion"/"deduplicate_against_method_error"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝猜测 session_failed 与 method 的 correlation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"listenerPolicy"/,/"boundaries"/ s/"reject_new_listener_keep_existing_sink"/"replace_existing_sink"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝第二个 listener 替换现有 sink。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "engine_detach"/,/"id": "ui_owner_destroy"/ s/"release_attachment_leases"/"retain_engine_attachment_leases"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Engine detach 遗留 confirmed lease。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "engine_detach"/,/"id": "ui_owner_destroy"/ s/"release_after_cleanup_if_owned"/"retain_if_owned"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "boundary retains presentation slot"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Engine boundary 遗留 active presentation slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "engine_detach"/,/"id": "ui_owner_destroy"/ s/"order": 10/"order": 3/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "boundary releases presentation slot before cleanup"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 boundary 在 Session/Preview/lease cleanup 前释放 slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "ui_owner_destroy"/,/"linearizationPolicy"/ s/"capability_failure_system_interrupted"/"user_cancel"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 UI owner destroy 伪装成用户取消。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "session_created_adoption"/,/"ordering"/ s/"register_active_session_before_flutter_completion"/"register_active_session_after_flutter_completion"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝在 Flutter completion 后登记 active Session。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"id": "confirmed_media_adoption"/"id": "confirmed_media_adoption_missing"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 confirmed media lease adoption。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"linearizationPolicy"/,/"methodCompletion"/ { /"generation_open_check"/d; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 linearization 缺少 generation open check。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "engine_detach"/,/"actions"/ s/"coordinatorId": "bridge_lifecycle_coordinator"/"coordinatorId": "boundary_only_coordinator"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 boundary 脱离共同 linearization coordinator。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "control_applied"/,/"cleanupBeforeDrop"/ s/"bridge_lifecycle_coordinator"/"non_resource_only_coordinator"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝非资源结果脱离共同 coordinator。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "session_created"/d' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 late session_created cleanup。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "session_created"/,/"cleanupBeforeDrop"/ s/"capability_failure_system_interrupted_returned_session"/"drop_without_terminating_session"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝替换 late Session 终止动作。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "confirmed_media"/,/"cleanupBeforeDrop"/ s/"release_media_returned_lease"/"drop_without_releasing_lease"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 late confirmed_media lease 泄漏。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "media_preview"/,/"cleanupBeforeDrop"/ s/"cleanupBeforeDrop": true/"cleanupBeforeDrop": false/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝在 late Preview cleanup 前 drop callback。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"duplicateRequests"/,/"eventEncodingFailureBehavior"/ s/"reserve_before_invoking_capability"/"reserve_after_completion"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝在 Capability 执行后才预留 tombstone 槽。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "media_handle"/,/"conditionalRules"/ s/"outboundOutOfRange": "wire_encoding_failed"/"outboundOutOfRange": "invalid_wire_payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 Handle 出站失败当作入站 payload 错误。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"key": "operation"/,/"validation"/ s/"unknown_operation"/"attacker_supplied_operation"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 error details 回显未知 operation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"key": "field"/,/"validation"/ s/"unknown_field"/"attackerControlledField"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 error details 回显未知 field。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"key": "reason"/,/"validation"/ s/"closed_reason_code"/"raw_exception"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 error details 使用原始异常来源。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"key": "reason"/,/"validation"/ s/"maxLength": 64/"maxLength": 1024/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝超长 error detail。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"key": "actualWireVersion"/,/"validation"/ s/"maximum": 9223372036854775807/"maximum": 9223372036854775808/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 error detail version 超出 signed-64。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"caller_path_forbidden"/"caller_path_allowed"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "caller path transfer policy"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Media Profile 放宽 path transfer。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"methodCompletion": "exactly_once"/"methodCompletion": "at_least_once"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Wire 多次完成语义。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "media_handle"/,/"conditionalRules"/ s/"maxLength": 128/"maxLength": 129/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 opaque handle 超出 Capability policy 长度。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"requestIdPolicy"/,/"duplicateRequests"/ s/"pattern": "[^"]*"/"pattern": ".*"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "requestId pattern"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝宽松 requestId pattern。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"signedInteger"/,/"mediaTransfer"/ s/"bits": 64/"bits": 32/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝非共同 signed-64 Wire int。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"signedInteger"/,/"mediaTransfer"/ s/"outboundOutOfRange": "wire_encoding_failed"/"outboundOutOfRange": "encoding_failed"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 Wire 出站溢出伪装为 Capability Failure。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"duplicateRequests"/,/"eventEncodingFailureBehavior"/ s/"maxPendingRequests": 32/"maxPendingRequests": 0/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝无效 pending request 容量。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"duplicateRequests"/,/"eventEncodingFailureBehavior"/ s/"maxCompletedRequestTombstones": 4096/"maxCompletedRequestTombstones": 4097/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 completed tombstone 容量漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"duplicateRequests"/,/"eventEncodingFailureBehavior"/ s/"completedEvictionBeforeTtl": "forbidden"/"completedEvictionBeforeTtl": "allowed"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝提前逐出 request tombstone。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"eventEncodingFailureBehavior"/,/"nativeValueTransport"/ s/"terminate_sink_wire_encoding_failed_keep_capability_owned"/"drop_event"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝不确定的 event 编码失败行为。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"capabilityOperationId": null/"capabilityOperationId": "present_capture_flow"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation masquerades as Capability operation"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 present_capture_flow 伪装成 Core operation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "attach_live_preview"/,/"reason"/ s/"disposition": "native_consumer_only"/"disposition": "exposed_method"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "Native preview scope exposure"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 Native RenderTarget scope 暴露到 Channel。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak '/"capabilityId": "detach_live_preview"/d' "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing Native-only coverage"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝遗漏 Native-only preview coverage。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "live_preview_attachment"/,/"reason"/ s/"disposition": "native_consumer_only"/"disposition": "mapped_payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "Native preview resource exposure"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝暴露 live preview attachment resource。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "unconfirmed_preview_render_attachment"/d' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing Native preview resource coverage"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝遗漏 unconfirmed preview resource coverage。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "live_preview_render_scope"/,/"reason"/ s/"disposition": "native_consumer_only"/"disposition": "mapped_payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "Native preview ownership scope exposure"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝暴露 live preview ownership scope。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityId": "unconfirmed_preview_render_scope"/d' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing Native preview ownership scope coverage"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝遗漏 unconfirmed preview ownership scope coverage。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"id": "failure"/"id": "failure_missing"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing presentation failure terminal"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 present_capture_flow 缺少 failure 终态。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ { /"reserve_active_presentation_slot"/d; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing atomic presentation slot reservation"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 presentation 缺少原子 slot reservation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"reservationOrder"/,/"conflictOutcome"/ s/"owner_generation_open_recheck"/"reserve_active_presentation_slot"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation reservation order drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 slot reservation 先于 owner generation recheck。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"scope": "attached_ui_owner_identity"/"scope": "ui_owner_generation"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation slot bound to replaceable generation"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 slot 绑定可替换的 ui_owner_generation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"preserve_owner_identity_slot_across_fresh_generation"/"release_slot_on_fresh_generation"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "fresh generation drops stable owner slot"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 fresh generation 后释放 stable owner slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "background_owner_alive"/,/"terminalAction"/ { /"preserve_attached_owner_slot"/d; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "owner-alive generation transition loses slot"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 owner-alive generation 迁移丢失 presentation slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"releaseTriggerIds"/,/"releaseOrder"/ { /"presentation_failed"/d; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation failure slot release omission"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 present failure 不释放 active slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"releaseOrder"/,/"presentOrder"/ s/"settle_confirmed_or_undelivered_lease"/"release_active_presentation_slot"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "slot released before lease settlement"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 normal/presentation_failed 在 lease cleanup 前释放 slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"linearizationPolicy"/,/"methodCompletion"/ { /"presentation_lease_settlement_if_owned"/d; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation callback order misses lease settlement"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 callback/terminal machine 遗漏 lease settlement。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"callbackWinOrder"/,/"boundaryWinOrder"/ s/"presentation_lease_settlement_if_owned"/"presentation_slot_release_if_owned"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation callback slot release before lease settlement"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 callback/terminal machine 在 lease settlement 前释放 slot。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "capture_flow_confirmed"/,/"cleanupBeforeDrop"/ s/"callbackWinOrderId": "presentation_callback_terminal_machine"/"callbackWinOrderId": null/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "capture-flow completion loses terminal machine reference"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 capture-flow completion 脱离共同 terminal machine。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"cleanup_session_preview_release_undelivered_lease_release_slot_then_complete"/"cleanup_session_preview_no_lease_release_slot_then_complete"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation failure loses undelivered lease settlement"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 presentation failure 遗漏未交付 lease settlement。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"completion": "exactly_once"/"completion": "at_least_once"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation double completion"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 presentation 多次完成。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"consume_in_presentation_do_not_emit_to_flutter"/"forward_to_event_channel"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation event leakage"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝把 presentation-owned Session event 泄漏到 Flutter。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"cleanup_session_preview_and_undelivered_lease_release_slot_then_bridge_unavailable"/"complete_success_on_destroy"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "owner destroy success"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 UI owner 销毁后成功完成 flow。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"allocate_strictly_higher_generation_on_foreground"/"reuse_current_generation_on_foreground"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "background stale owner generation reuse"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝后台恢复复用已退休 generation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"allocate_strictly_higher_generation_after_rotation"/"reuse_current_generation_after_rotation"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "rotation stale owner generation reuse"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 owner 存活旋转后复用旧 generation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"platformSupport"/ s/"reattachPolicy": "forbidden"/"reattachPolicy": "explicit_after_rotation"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "destroyed owner reattach"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝旋转销毁 owner 后自动 reattach。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"resultType": "capture_flow_confirmed"/,/"cleanupBeforeDrop"/ s/"release_lease_interrupt_session_cleanup_preview_then_drop"/"drop_without_releasing_flow_lease"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "late flow lease leak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝晚到 confirmed flow lease 泄漏。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "thumbnail_copy"/,/"conditionalRules"/ s/"wireType": "bytes"/"wireType": "string"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "thumbnail non-Uint8List mapping"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缩略图使用非 Uint8List Channel 类型。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "thumbnail_byte_length"/,/"conditionalRules"/ s/"maximum": 524288/"maximum": 524289/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "thumbnail byte limit"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缩略图超过 512KiB。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "thumbnail_orientation_degrees"/,/"conditionalRules"/ { /"allowedIntegers"/,/]/ s/0/90/; }' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "thumbnail orientation"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝非 upright 缩略图方向。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "thumbnail_content_type"/,/"conditionalRules"/ s/"image_jpeg_content_type"/"mime_type"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "thumbnail content type"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缩略图 content type 放宽。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "poster_frame_millis"/,/"capabilityFieldId": "session_handle"/ s/"effect": "must_be_null"/"effect": "must_be_non_null"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "thumbnail poster policy"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缩略图 posterFrameMillis 语义漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

for thumbnail_policy in \
  thumbnail_length_matches_bytes \
  thumbnail_exif_and_source_metadata_stripped \
  thumbnail_video_poster_deterministic \
  no_media_path_uri_fallback; do
  sed -i.bak "s/\"$thumbnail_policy\"/\"missing_$thumbnail_policy\"/" \
    "$wire_contract"
  rm -f -- "$wire_contract.bak"
  assert_wire_contract_mutated "$thumbnail_policy"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝缺少缩略图策略：$thumbnail_policy。" >&2
    exit 1
  fi
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
done

sed -i.bak '/"capabilityId": "media_thumbnail"/d' "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing thumbnail coverage"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝遗漏 thumbnail result coverage。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "materialize_media_resource"/,/"platformSupport"/ s/"requestPayloadId": "materialize_media_resource_request_payload"/"requestPayloadId": "media_export_request_payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "materialize accepts caller sink/path"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 materialize 接受 caller sink/path。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "presentation_request_id"/,/"conditionalRules"/ s/"format": "opaque_request_id"/"format": "opaque_handle"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation request id format drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 presentation request ID 退化为通用 handle。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "dismiss_capture_flow"/,/"platformSupport"/ s/"requestPayloadId": "dismiss_capture_flow_request_payload"/"requestPayloadId": "session_action_request_payload"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "dismiss capture flow accepts session handle"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 dismiss_capture_flow 接受 Session handle。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.methods[] | select(.id == "dismiss_capture_flow") | .platformSupport.ios) = "unsupported"'
assert_wire_contract_mutated "dismiss capture flow iOS support regression"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 iOS dismiss 支持矩阵回退。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"capabilityFieldId": "file_uri"/,/"conditionalRules"/ s/"format": "canonical_file_uri"/"format": "uri"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer fileUri format drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transfer fileUri canonical 规则漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"maxFileBytes": 52428800/"maxFileBytes": 52428801/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer max file bytes drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transfer 50MiB 上限漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"ttlSeconds": 300/"ttlSeconds": 301/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer TTL drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transfer TTL 漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"maxActiveExportsPerEngineAttachment": 4/"maxActiveExportsPerEngineAttachment": 5/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer active export capacity drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transfer active export 容量漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.coverage.nativeInputs[] | select(.capabilityId == "media_copy_sink") | .bindingKind) = "fixed_integer"'
assert_wire_contract_rejected_with_diagnostic \
  "transfer native sink coverage drift" \
  "native input coverage media_copy_sink 必须声明 native sink 或固定 52428800-byte Adapter binding"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.coverage.nativeInputs[] | select(.capabilityId == "media_export_max_length") | .fixedIntegerValue) = 52428801'
assert_wire_contract_rejected_with_diagnostic \
  "transfer native max length binding drift" \
  "native input coverage media_export_max_length 必须声明 native sink 或固定 52428800-byte Adapter binding"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '.transferStore.exportHandlePolicy.minimumEntropyBits = 64'
assert_wire_contract_mutated "transfer export handle entropy drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝低于 128-bit 的 export handle。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

for export_handle_mutation in \
  '.transferStore.exportHandlePolicy.ownerScope = "process"' \
  '.transferStore.exportHandlePolicy.generator = "predictable_random"' \
  '.transferStore.exportHandlePolicy.format = "uuid"' \
  '.transferStore.exportHandlePolicy.minLength = 21' \
  '.transferStore.exportHandlePolicy.maxLength = 65' \
  '.transferStore.exportHandlePolicy.lookup = "accept_if_well_formed"' \
  '.transferStore.exportHandlePolicy.reuse = "allowed"' \
  '.transferStore.exportHandlePolicy.crossAttachmentUse = "allowed"' \
  '.transferStore.exportHandlePolicy.logging = "allow"'; do
  mutate_wire_with_jq "$export_handle_mutation"
  assert_wire_contract_mutated "transfer export handle policy drift"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未锁定 export handle 的 attachment scope、CSPRNG、格式或长度。" >&2
    exit 1
  fi
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
done

mutate_wire_with_jq '.transferStore.resultPolicy.photoContentType = "image/png"'
assert_wire_contract_mutated "transfer result MIME drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 materialized photo 非 image/jpeg。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

for result_policy_mutation in \
  '.transferStore.resultPolicy.maxByteLength = 52428801' \
  '.transferStore.resultPolicy.videoContentType = "video/quicktime"' \
  '.transferStore.resultPolicy.durationFieldId = "duration_seconds"' \
  '.transferStore.resultPolicy.integrityFieldId = "checksum"' \
  '.transferStore.resultPolicy.integrityAlgorithm = "sha1"' \
  '.transferStore.resultPolicy.integrityEncoding = "base64"' \
  '.transferStore.resultPolicy.integrityRequired = true'; do
  mutate_wire_with_jq "$result_policy_mutation"
  assert_wire_contract_mutated "transfer result policy branch drift"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未锁定 materialized result 的长度、duration 或 integrity 分支。" >&2
    exit 1
  fi
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
done

mutate_wire_with_jq '.transferStore.fileUriPolicy.maxLength = 4097'
assert_wire_contract_mutated "transfer file URI maximum length drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未锁定 file URI 4096 字符上限。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

for uri_serialization_mutation in \
  '.transferStore.fileUriPolicy.serialization = "unicode"' \
  '.transferStore.fileUriPolicy.lengthUnit = "unicode_code_points"' \
  '.transferStore.fileUriPolicy.percentEncodingHexCase = "any"' \
  '.transferStore.fileUriPolicy.rejectUnescapedNonAscii = false'; do
  mutate_wire_with_jq "$uri_serialization_mutation"
  assert_wire_contract_mutated "transfer file URI serialization drift"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未固定 file URI 的 ASCII serialization 与长度计量。" >&2
    exit 1
  fi
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
done

mutate_wire_with_jq \
  '(.transferStore.fileUriLengthGoldenVectors[] | select(.id == "over_maximum_length_rejected") | .valid) = true'
assert_wire_contract_mutated "transfer file URI length vector drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 4097 字符 file URI 长度向量。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '.transferStore.limits.maxReleaseTombstones = 4097'
assert_wire_contract_mutated "transfer release tombstone capacity drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transfer release tombstone 容量漂移。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '.transferStore.limits.releaseTombstoneOverflow = "evict_oldest"'
assert_wire_contract_mutated "transfer release tombstone overflow policy drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝提前逐出未过期 release tombstone。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.errorDetailFields[] | select(.key == "capacity") | .enumValues) -= ["release_tombstones"]'
assert_wire_contract_mutated "release tombstone capacity diagnostic missing"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未要求 release_tombstones 容量诊断。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '.transferStore.lifecycle.releaseTombstoneHitOutcome = "materialized_media_invalid"'
assert_wire_contract_mutated "duplicate transfer release outcome drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 tombstone 命中时重复 release 非幂等。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '.transferStore.lifecycle.releasePendingDuplicatePolicy = "start_independent_cleanup"'
assert_wire_contract_mutated "pending duplicate release policy drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝同一 handle 的并发 release 重复预留或执行副作用。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '.transferStore.lifecycle.deleteFailurePolicy = "retain_registry_entry_only"'
assert_wire_contract_mutated "transfer delete failure ownership drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未锁定删除失败后的 registry、active 容量和 tombstone reservation。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '(.transferStore.lifecycle.materializeOrder[4:6]) |= reverse'
assert_wire_contract_mutated "transfer materialize order swap"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 export registry 早于 atomic file commit。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '.transferStore.lifecycle.releaseOrder[1] = "reserve_release_tombstone_capacity"'
assert_wire_contract_mutated "release claim is not atomic"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未要求 cleanup claim 与 release tombstone reservation 原子完成。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '(.transferStore.lifecycle.releaseOrder[2:4]) |= reverse'
assert_wire_contract_mutated "transfer release order swap"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 release 在 transfer file 删除前移除 registry entry。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '(.transferStore.lifecycle.inflightCleanupOrder[2:4]) |= reverse'
assert_wire_contract_mutated "in-flight transfer cleanup order swap"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 in-flight capacity 在 partial file 删除前释放。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '(.transferStore.lifecycle.activeExportCleanupOrder[1:3]) |= reverse'
assert_wire_contract_mutated "active transfer cleanup order swap"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 active export 在文件删除前移除 registry entry。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq '(.transferStore.lifecycle.restartSweepOrder[1:3]) |= reverse'
assert_wire_contract_mutated "transfer restart sweep order swap"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 App restart 在根目录清扫前重置 transfer 容量。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq 'del(.lifecycle.boundaries[] | select(.id == "engine_detach") | .actions[] | select(.resourceId == "inflight_transfer_exports"))'
assert_wire_contract_mutated "engine detach misses in-flight transfer cleanup"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Engine detach 遗漏 in-flight transfer cleanup。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq 'del(.lifecycle.boundaries[] | select(.id == "engine_detach") | .actions[] | select(.resourceId == "active_transfer_exports"))'
assert_wire_contract_mutated "engine detach misses active transfer cleanup"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Engine detach 遗漏 active transfer cleanup。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.platform.differences[] | select(.id == "ios_private_cache_transfer_root") | .description) = "The iOS Adapter creates transfer files under the shared temporary directory."'
assert_wire_contract_mutated "iOS private cache transfer root drift"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未锁定 iOS plugin-owned App private cache transfer root。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"redaction": {/,/"fileUriGoldenVectors"/ s/"error_details"/"error_details_removed"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer locator error detail leakage"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 transfer locator 进入 error details。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "relative_path_rejected"/,/"reason"/ s/"valid": false/"valid": true/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer relative fileUri accepted"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝相对 fileUri golden vector。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.transferStore.fileUriGoldenVectors[] | select(.id == "invalid_percent_triplet_rejected") | .uri) = "file:///data/user/0/app/cache/media-transfer/safe.bin"'
assert_wire_contract_mutated "malicious file URI vector replaced with benign URI"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未锁定 file URI 恶意向量 literal。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq \
  '(.transferStore.fileUriGoldenVectors[] | select(.id == "raw_unicode_rejected") | .valid) = true'
assert_wire_contract_mutated "raw Unicode file URI accepted"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝未 percent-encode 的 Unicode file URI。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "materialized_media_result_payload"/,/"unknownFieldPolicy"/ s/"file_uri"/"thumbnail_copy"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer raw bytes payload"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 materialize payload 传 raw bytes。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"materialize_and_release_export_do_not_release_source_media"/"release_source_media_after_materialize"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "transfer auto releases source media"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 materialize 自动 release source media。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  's/"Adds scoped one-time materialize and release methods for Capability V4 bounded export/"Missing scoped transfer history/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "missing Wire V3 changeLog"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 Wire V3 history。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

mutate_wire_with_jq 'del(.changeLog[] | select(.wireVersion == 3))'
assert_wire_contract_mutated "deleted Wire V3 changeLog entry"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝删除整个 Wire V3 changeLog entry。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

for export_error in \
  media_export_conflict \
  media_export_overloaded \
  media_export_too_large \
  media_export_sink_rejected \
  media_export_read_failed \
  media_export_write_failed \
  media_export_cancelled \
  media_export_timed_out; do
  jq --arg code "$export_error" \
    '(.errors[] | select(.code == $code) | .source) = "wire_protocol"' \
    "$wire_contract" > "$wire_contract.jq.tmp"
  mv "$wire_contract.jq.tmp" "$wire_contract"
  assert_wire_contract_rejected_with_diagnostic \
    "$export_error source taxonomy drift" \
    "error $export_error 必须原样映射 Capability Failure"
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
done

for protocol_error in \
  transfer_store_overloaded \
  transfer_store_unavailable \
  materialized_media_invalid; do
  jq --arg code "$protocol_error" \
    '(.errors[] | select(.code == $code) | .source) = "capability_failure"' \
    "$wire_contract" > "$wire_contract.jq.tmp"
  mv "$wire_contract.jq.tmp" "$wire_contract"
  assert_wire_contract_rejected_with_diagnostic \
    "$protocol_error source taxonomy drift" \
    "error $protocol_error 不是固定的 Wire protocol error"
  cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"
done

mutate_wire_with_jq \
  '(.errors[] | select(.code == "materialized_media_invalid") | .code) = "export_invalid"'
assert_wire_contract_rejected_with_diagnostic \
  "ambiguous export error code" \
  "errors 必须完整映射 Capability Failure 和固定 Wire error"
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak \
  '/"id": "present_capture_flow"/,/"ios"/ s/"android": "supported"/"android": "unsupported"/' \
  "$wire_contract"
rm -f -- "$wire_contract.bak"
assert_wire_contract_mutated "presentation platform parity"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 presentation 双平台语义缺失。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.wire.valid" "$wire_contract"

sed -i.bak '/wire.schema.json/d' "$wire_detail"
rm -f -- "$wire_detail.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Bridge 文档缺少 Wire Schema 链接。" >&2
  exit 1
fi
cp "$FIXTURE_ROOT/media-capture.bridge.valid" "$wire_detail"
run_check >/dev/null

rm -f -- \
  "$FIXTURE_ROOT/wire.schema.valid" \
  "$FIXTURE_ROOT/media-capture.wire.valid" \
  "$FIXTURE_ROOT/media-capture.bridge.valid"

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

run_dart_script tool/sync_codex_adapters.dart \
  --check --root "$FIXTURE_ROOT" >/dev/null
run_dart_script tool/sync_codex_adapters.dart \
  --root "$FIXTURE_ROOT" --check >/dev/null
set +e
run_dart_script tool/sync_codex_adapters.dart \
  --root --check >/dev/null 2>&1
invalid_root_status=$?
set -e
if [[ "$invalid_root_status" -ne 64 ]]; then
  echo "错误：Codex 适配 CLI 未以 usage 状态拒绝缺失的 --root 值。" >&2
  exit 1
fi
set +e
run_dart_script tool/sync_codex_adapters.dart \
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

valid_scopes=(
  'documentation-empty|task-executor|[]|[documentation]'
  'documentation-platforms|task-executor|[android, ios]|[documentation]'
  'planning|task-executor|[]|[planning]'
  'harness|task-executor|[]|[harness]'
  'flutter|task-executor|[flutter]|[flutter]'
  'dart-client|task-executor|[flutter]|[dart-client]'
  'capability-contract|task-executor|[android, ios]|[capability-contract]'
  'android-native|android-engineer|[android]|[native]'
  'ios-native|ios-engineer|[ios]|[native]'
  'android-bridge-adapter|android-engineer|[android]|[bridge-adapter]'
  'ios-bridge-adapter|ios-engineer|[ios]|[bridge-adapter]'
  'bridge-contract|bridge-engineer|[flutter, android, ios]|[bridge-contract]'
  'integration|bridge-engineer|[flutter, android, ios]|[integration]'
  'android-quality-gate|android-engineer|[android]|[quality-gate]'
  'ios-quality-gate|ios-engineer|[ios]|[quality-gate]'
)
for valid_scope in "${valid_scopes[@]}"; do
  IFS='|' read -r scope_label scope_executor scope_platforms scope_work_kinds \
    <<< "$valid_scope"
  write_scoped_task "$scope_executor" "$scope_platforms" "$scope_work_kinds"
  if ! run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 拒绝了合法任务范围：$scope_label。" >&2
    exit 1
  fi
done
write_valid_task

sed -i.bak '/platforms:/d' "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 platforms 的活动任务。" >&2
  exit 1
fi
write_valid_task

sed -i.bak '/workKinds:/d' "$FIXTURE_ROOT/docs/tasks/sample-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/sample-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 workKinds 的活动任务。" >&2
  exit 1
fi
write_valid_task

for invalid_scope in \
  'task-executor|[web]|[flutter]' \
  'task-executor|[flutter, flutter]|[flutter]' \
  'task-executor|[flutter]|[unknown]' \
  'task-executor|[flutter]|[flutter, flutter]' \
  'task-executor|[]|[dart-client]' \
  'task-executor|[android]|[flutter]' \
  'task-executor|[android]|[native]' \
  'android-engineer|[ios]|[native]' \
  'ios-engineer|[ios, android]|[bridge-adapter]' \
  'bridge-engineer|[flutter]|[bridge-contract]' \
  'bridge-engineer|[flutter]|[dart-client]'; do
  IFS='|' read -r scope_executor scope_platforms scope_work_kinds \
    <<< "$invalid_scope"
  write_scoped_task "$scope_executor" "$scope_platforms" "$scope_work_kinds"
  if run_check >/dev/null 2>&1; then
    echo "错误：Harness Check 未拒绝无效任务范围：$invalid_scope。" >&2
    exit 1
  fi
done
write_valid_task

sed -i.bak '/executor:/a\
platforms: [web]\
workKinds: [harness]' \
  "$FIXTURE_ROOT/docs/tasks/done/complete-task.md"
rm -f -- "$FIXTURE_ROOT/docs/tasks/done/complete-task.md.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未校验已声明新范围字段的历史归档任务。" >&2
  exit 1
fi
write_valid_done_task
run_check >/dev/null

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
platforms: []
workKinds: [planning]
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

ln -s sample-task.md "$FIXTURE_ROOT/docs/tasks/linked-task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 docs/tasks/ 内部符号链接。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks/linked-task.md"

cat > "$FIXTURE_PARENT/outside-task.md" <<'MARKDOWN'
---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy: []
---
# Outside task
MARKDOWN
ln -s "$FIXTURE_PARENT/outside-task.md" \
  "$FIXTURE_ROOT/docs/tasks/outside-task.md"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝指向仓库外的任务符号链接。" >&2
  exit 1
fi
rm -f -- \
  "$FIXTURE_ROOT/docs/tasks/outside-task.md" \
  "$FIXTURE_PARENT/outside-task.md"
run_check >/dev/null

mv "$FIXTURE_ROOT/docs/tasks" "$FIXTURE_ROOT/docs/tasks.valid"
ln -s tasks.valid "$FIXTURE_ROOT/docs/tasks"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝指向仓库内的 docs/tasks 根目录符号链接。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks"
mv "$FIXTURE_ROOT/docs/tasks.valid" "$FIXTURE_ROOT/docs/tasks"

mkdir -p "$FIXTURE_PARENT/outside-tasks"
cp -R "$FIXTURE_ROOT/docs/tasks/." "$FIXTURE_PARENT/outside-tasks/"
mv "$FIXTURE_ROOT/docs/tasks" "$FIXTURE_ROOT/docs/tasks.valid"
ln -s "$FIXTURE_PARENT/outside-tasks" "$FIXTURE_ROOT/docs/tasks"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝指向仓库外的 docs/tasks 根目录符号链接。" >&2
  exit 1
fi
rm -f -- "$FIXTURE_ROOT/docs/tasks"
mv "$FIXTURE_ROOT/docs/tasks.valid" "$FIXTURE_ROOT/docs/tasks"
rm -rf -- "$FIXTURE_PARENT/outside-tasks"
run_check >/dev/null

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

cp "$FIXTURE_ROOT/.github/workflows/ci.yml" \
  "$FIXTURE_ROOT/.github/workflows/ci.yml.valid"
sed -i.bak '/make media-capture-ios/d' \
  "$FIXTURE_ROOT/.github/workflows/ci.yml"
rm -f -- "$FIXTURE_ROOT/.github/workflows/ci.yml.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝缺少 iOS Media Capture 门禁的 CI。" >&2
  exit 1
fi
mv "$FIXTURE_ROOT/.github/workflows/ci.yml.valid" \
  "$FIXTURE_ROOT/.github/workflows/ci.yml"

golden="$FIXTURE_ROOT/app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json"
cp "$golden" "$golden.valid"
sed -i.bak 's/"maxFileBytes": 52428800/"maxFileBytes": 52428801/' "$golden"
rm -f -- "$golden.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝跨 Runtime transfer limit 漂移。" >&2
  exit 1
fi
mv "$golden.valid" "$golden"

swift_consumer="$FIXTURE_ROOT/app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift"
mv "$swift_consumer" "$swift_consumer.valid"
printf '%s\n' '// media-capture-v4-v3.golden.json' > "$swift_consumer"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝只保留 golden 文件名的 Swift 空消费者。" >&2
  exit 1
fi
mv "$swift_consumer.valid" "$swift_consumer"

dart_consumer="$FIXTURE_ROOT/app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart"
mv "$dart_consumer" "$dart_consumer.valid"
printf '%s\n' '// media-capture-v4-v3.golden.json' > "$dart_consumer"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝只保留 golden 文件名的 Dart 空消费者。" >&2
  exit 1
fi
mv "$dart_consumer.valid" "$dart_consumer"

kotlin_consumer="$FIXTURE_ROOT/app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt"
mv "$kotlin_consumer" "$kotlin_consumer.valid"
printf '%s\n' '// media-capture-v4-v3.golden.json' > "$kotlin_consumer"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝只保留 golden 文件名的 Kotlin 空消费者。" >&2
  exit 1
fi
mv "$kotlin_consumer.valid" "$kotlin_consumer"

demo_pubspec="$FIXTURE_ROOT/app/apps/demo/pubspec.yaml"
cp "$demo_pubspec" "$demo_pubspec.valid"
sed -i.bak 's/enable-swift-package-manager: true/enable-swift-package-manager: false/' \
  "$demo_pubspec"
rm -f -- "$demo_pubspec.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝 Demo Host 关闭 SwiftPM。" >&2
  exit 1
fi
mv "$demo_pubspec.valid" "$demo_pubspec"

demo_plist="$FIXTURE_ROOT/app/apps/demo/ios/Runner/Info.plist"
cp "$demo_plist" "$demo_plist.valid"
sed -i.bak 's#<string>Camera</string>#<string> </string>#' "$demo_plist"
rm -f -- "$demo_plist.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝空 Camera 权限用途说明。" >&2
  exit 1
fi
cp "$demo_plist.valid" "$demo_plist"

sed -i.bak 's#<string>Camera</string>#<true/>#' "$demo_plist"
rm -f -- "$demo_plist.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝非 String Camera 权限用途说明。" >&2
  exit 1
fi
cp "$demo_plist.valid" "$demo_plist"

sed -i.bak \
  's#<key>NSCameraUsageDescription</key>#<!-- <key>NSCameraUsageDescription</key> -->#' \
  "$demo_plist"
rm -f -- "$demo_plist.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝仅在注释中声明 Camera 权限 key。" >&2
  exit 1
fi
cp "$demo_plist.valid" "$demo_plist"

sed -i.bak \
  's#</dict>#<key>NSCameraUsageDescription</key><string>Duplicate</string></dict>#' \
  "$demo_plist"
rm -f -- "$demo_plist.bak"
if run_check >/dev/null 2>&1; then
  echo "错误：Harness Check 未拒绝重复 Camera 权限 key。" >&2
  exit 1
fi
mv "$demo_plist.valid" "$demo_plist"

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
