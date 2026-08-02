---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy:
  - media-capture-android-flutter-presentation-dismissal
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 提升 iOS Capture Flow Dismiss Wire 支持状态

## 输入与事实来源

- Wire V3 已定义闭合的 `dismiss_capture_flow` Adapter lifecycle method、opaque
  `presentationRequestId` 和 exactly-once 终态语义。
- Android Adapter 已实现该 method；当前 Wire JSON、变更日志和 Harness 仍把 iOS 固定为
  `unsupported`。
- `media-capture-ios-bridge-adapter` 已要求实现同一 method，但单平台任务无权修改共享 Wire Contract、
  Validator 或 Harness 负例。

## 目标

- 在不改变 Wire shape 或版本的前提下，把 `dismiss_capture_flow` 的 iOS 支持状态提升为
  `supported`。
- 让共享文档、结构化 Contract、Validator 与负例对 Android/iOS 支持状态保持一致。
- 为 iOS Bridge Adapter 提供可合法实现和验证的前置契约。

## 非目标

- 不实现或修改 Android/iOS/Dart Runtime 代码。
- 不改变 method、payload、error、Channel、request correlation、completion 或 lifecycle 顺序。
- 不新增 Wire 版本，不修改 Capability Contract、Native Module、Host、CI 或其它 method 的支持矩阵。

## 实现路径与所有权

本任务只写：

- `docs/bridge/contracts/media-capture.wire.json`
- `docs/bridge/media-capture.md`
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`
- 因上述共享文件变化而失效的既有 `docs/reviews/security-*.md`：仅追加本次独立安全影响复审结论并
  刷新各自 `implementationFiles` 对应的 `implementationDigest`
- 本任务 Review 与 evidence

## 实现要求

1. `dismiss_capture_flow.platformSupport` 精确声明 Android/iOS 均为 `supported`；其它字段保持不变。
2. Wire V3 change log 与详情文档删除“iOS 延后/unsupported”描述，明确两端都只接受 originating
   `presentationRequestId`，匹配 flow 才幂等 dismiss。
3. Harness Validator 精确要求两端 supported；错误信息与当前事实一致，不再把合法 iOS 支持误报为提前
   声明。
4. Harness 负例改为把 iOS support 从 `supported` 篡改为 `unsupported`，并证明门禁拒绝支持矩阵回退。
5. Android 既有 method 语义、Wire V1/V2 history projection、Wire V3 版本号与 Capability V4 兼容集合
   不得变化。
6. 受影响的既有 Security Review 必须重新核对各自原安全边界；只有独立 Reviewer 确认未回退后才能更新
   digest。不得只为通过 Harness 机械替换摘要，也不得改变其历史 finding 严重级别。

## 测试与验收

- Harness 正例通过，iOS support 回退、payload 漂移、request ID format 漂移等既有负例继续失败。
- 独立普通 Review 确认只有平台可用性事实变化；Security Review 确认没有放宽输入、错误或 lifecycle
  边界。
- 本任务归档后，`media-capture-ios-bridge-adapter` 才能实现并声明 iOS dismiss 支持。

## 验证命令

```bash
bash scripts/quality/test-harness.sh
make harness-check
git diff --check
```

## 环境限制

本任务只提升共享契约和确定性门禁，不证明 iOS Adapter、Flutter Plugin discovery、Host 编译或真机 UI
行为；这些分别由 iOS Adapter、iOS Quality Gate 和用户最终验收提供证据。
