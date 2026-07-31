---
executor: android-engineer
platforms: [android]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-android-bridge-adapter
  - media-capture-android-export-core
  - media-capture-export-dart-client
  - media-capture-export-wire-evolution
securityReview: required
---

# 实现 Android Media Capture Transfer Bridge Adapter

## 输入与事实来源

- Wire V3 materialize/release、Capability V4 streaming sink 与 Dart Client 类型。
- 已实现 Android Bridge lifecycle coordinator、request registry、Engine attachment 和 Core 注入。
- Android App private `Context.cacheDir`，不新增共享存储或相册权限。

## 目标

- 在 Android Plugin Adapter 实现 Adapter-owned transfer store、file URI 映射和两项 Wire V3 method。
- 把 Core bounded sink 复制结果安全落到 plugin cache，再交给 Dart 立即导入 `app_media`。
- 覆盖容量、TTL、Engine detach、App restart、晚到结果、URI redaction 和 Host build。

## 非目标

- 不修改 Capability/Wire/Dart Client、Core capture 行为、Flutter Store、Feature 或 iOS。
- 不接受 Flutter 目标路径，不使用 external/shared storage、FileProvider 公网 URI或相册权限。
- 不通过 Channel 传 media bytes/chunk，不把 transfer file 视为永久消息资源。

## 实现要求

1. 在 `context.cacheDir/app_media_capture_bridge/exports`（或 Contract 固定等价目录）创建 transfer store。
   初始化与每次访问校验 canonical root、拒绝 symlink；文件名只由 CSPRNG export handle 派生。
2. materialize 入站校验后，在 lifecycle coordinator 原子预留 active count/bytes 和 completion slot，再
   创建同目录 staging file 与 Core sink。不得在容量拒绝后调用 Core。
3. sink 使用 bounded OutputStream 写 staging，commit 前校验实际长度/MIME/上限，flush/close 后原子 rename
   到 final；登记 export/TTL 成功后才能在 Android main thread 返回 result。
4. `fileUri` 只用 `Uri.fromFile(finalFile)` 或等价规范化 API生成并通过 Wire 出站校验；不得手工拼接，
   不得进入日志、PlatformException details、事件、Semantics 或 evidence。
5. release method 删除 final/staging 并登记 tombstone；重复 release 幂等。TTL、Engine detach、plugin
   detach、App restart 和 late completion 都先 abort/delete 再关闭 request；startup 清理旧 export。
6. 已交付 transfer 的 source media lease保持不变。Adapter 不因 materialize/release export 自动调用
   `release_media`；Flutter Consumer 完成 `app_media` import 后分别释放两个资源。
7. 固定 4 个 active export、100 MiB active bytes和 5 分钟 TTL；并发 reservation/commit/delete 线性化，
   失败不泄漏容量。删除失败使用有界重试/retained cleanup，不返回路径。
8. Gradle/Host 不新增权限。更新 Android Bridge 详情和专项质量脚本，证明 V3 methods、cache root、无路径
   泄漏、plugin registration 与 Debug APK 依赖图。

## 测试与验收

- Fake Core + temporary cache 测试 success/import window/release、容量、TTL、restart、Engine detach、
  malformed payload、symlink/traversal、length drift、IO failure、late result 和 exactly-once。
- 测试扫描日志/error details/result fixture，除成功 payload 的 fileUri 外不得出现 root/path；成功 URI
  必须位于 canonical plugin root。
- Android Plugin tests/lint 与 Demo Debug APK build 通过；不需要新增 Manifest 权限。

```bash
app/apps/demo/android/gradlew -p app/packages/app_media_capture_bridge/android test lint
bash scripts/quality/media-capture-android.sh
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
make analyze
make lint
make harness-check
git diff --check
```

## 环境限制

需要 Android SDK/JDK/Flutter。Fake cache 不能证明设备 Camera 内容；最终集成用用户主动拍摄的测试媒体
验证 transfer 后立即清理，证据不得保存真实文件或路径。
