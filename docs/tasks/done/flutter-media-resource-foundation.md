---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy:
  - flutter-media-resource-architecture
securityReview: required
---

# 实现 Flutter 媒体资源存储基础件

## 输入与事实来源

- `flutter-media-resource-architecture` 归档后的权威文档与依赖矩阵。
- 当前 Workspace、`app_core` Value Object 约定、`app_ui` Token 和包依赖门禁。
- 当前 gallery 使用 `image_picker` 返回临时 `XFile.path`；该路径不具备消息生命周期保证。

## 目标

- 创建 `app_media` Package 和 `MediaResourceId`，实现 App 私有、进程级的媒体导入、解析、引用计数和
  清理。
- 为 gallery 临时文件与后续 Media Capture transfer copy 提供同一套安全 import API。
- 把 Package 登记到 Workspace、依赖矩阵和结构化门禁，但本任务不实现预览 UI 或业务接入。

## 非目标

- 不实现图片/视频 Viewer、消息气泡、选择器、Camera Bridge、上传或持久化。
- 不让 `app_data` 依赖 `app_media`，不在 Store 内解析 Support/Order 等业务模型。
- 不接受网络 URL、`content:` URI、任意字节流、调用方指定目标路径或源文件名作为存储名。

## 实现要求

1. 在 `app_core` 增加不可变 `MediaResourceId` Value Object：闭合格式、长度上限、安全 redacted
   `toString`；随机创建留给 `app_media`，不得把路径/handle 编进 ID。
2. 创建 `app/packages/app_media/`，公开窄模型和接口：媒体类型、import request/result、
   `OwnedMediaResource`、`ResolvedMediaResource`、typed failure、`retain`、`release`、`dispose`。
   公共 API 不返回 `dynamic`、裸 Map 或底层 FileSystemException。
3. 使用官方 `path_provider` 获取 App cache 根；Store 在其下创建固定子目录，拒绝符号链接、越界
   canonical path 和非 `file:` 源。源只在 import 调用范围内可见，日志/错误不得输出 URI 或文件名。
4. 图片输入先做 content type、声明/实际长度和 Flutter platform image-codec decode；成功后重新编码为
   `image/jpeg` 或 `image/png` canonical copy并移除源 metadata，输出仍受 20 MiB 上限约束。无法解码的
   HEIC/WebP/其它来源返回 `unsupported_media`；不能只信扩展名或 picker MIME。
5. 视频 Foundation 只验证 `video/mp4`/`video/quicktime`、声明/实际长度、ISO BMFF 容器签名和 50 MiB
   上限，不宣称可解码。真实 decoder probe 由后置 Preview 层执行；增长、截断、替换竞态必须失败并清理
   staging。
6. 目标名由至少 128-bit CSPRNG ID 和闭合扩展生成。写入 `.part` 后 flush/close，再在同目录原子 rename
   commit；失败、取消、dispose 和晚到 completion 不得留下可解析的半文件。
7. Registry 线性化 import/retain/release/resolve/dispose。初始 import 持有一个引用；retain 只对 active
   ID 成功；最后一次 release 删除文件并写入短期 tombstone，使重复 release 幂等且 resolve 稳定失败。
8. `ResolvedMediaResource` 的 file URI 只在 active 引用期间有效；对象与 `toString` 必须脱敏。调用者
   不得修改文件；Store 在 resolve 时重新确认文件位于受控根且长度/content type 未漂移。
9. V1 不持久化 Registry。初始化清理上次进程遗留的 `.part` 和未登记媒体；Store dispose 阻止新调用、
   等待/取消在途 import、删除所有 active 文件并恰好一次完成。
10. 更新根 Workspace、`app_features`/Demo 允许依赖、`app_media -> app_core, app_ui` 依赖规则，以及
    `app/tool/check_package_dependencies.dart` 和 repository-boundary Fixture。不得修改 Capability/Wire
    Harness、`app/tool/harness_check.dart` 或 `scripts/quality/test-harness.sh`；这些共享文件由后续契约
    任务串行拥有。依赖版本由首个真实消费者加入并通过 Flutter 3.35.7 解析，不手工编辑 lockfile。

## 测试与验收

- 单测使用窄 FileSystem/Clock/Random Fake，覆盖图片 canonicalization、视频容器检查、MIME/签名/长度错误、文件替换、取消、并发、
  retain/release、重复释放、晚到、启动清理和 dispose exactly once。
- 安全测试证明 traversal、symlink、非 file URI、超长名称、伪扩展、超限文件和异常信息不会越界或泄漏。
- Package 公共 API/日志/错误/Value Object 不包含绝对路径、Native handle、原始异常或媒体 bytes。
- Workspace 依赖门禁允许既定边，仍拒绝 `app_data -> app_media` 与反向 Feature 依赖。

```bash
TOOL_WORKDIR=app bash scripts/flutter-tool.sh pub get
TOOL_WORKDIR=app/packages/app_media bash scripts/flutter-tool.sh test
make format
make analyze
make test
make lint
make harness-check
git diff --check
```

## 环境限制

测试可以使用生成的无敏感小文件 Fixture，不读取用户照片。此任务只证明 Flutter 文件资源生命周期，
不证明真实 picker、Camera transfer 或视频解码；视频解码结论只由后置 Preview 任务给出。

## 执行结果

- [实现 Review](../../reviews/execute-flutter-media-resource-foundation.md)
- [Security Review](../../reviews/security-flutter-media-resource-foundation.md)
- [测试证据](../../reviews/test-evidence/flutter-media-resource-foundation.log)
