---
task: media-capture-android-transfer-store-file-identity-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：Android Transfer Store 文件身份修正

## 结论

独立普通 Review 与修复复审通过，P0 0、P1 0、P2 0，可以归档。最终 Reviewer 只读核对任务、实现、
测试、文档和原始证据，没有修改文件。

## 已修复问题

- Store cleanup 不再持有 Store monitor 获取 Sink monitor；descriptor 先关闭，随后才进入 Store 临界区，
  并有确定性的并发 write/delete 测试证明锁顺序不会反转。
- final path 被外部 identity 或非 regular 条目替换时，只把本 reservation 的资源视为已不存在，保留外部
  条目并释放 active count/bytes；只有 identity 匹配的 regular file 删除失败才保留记录重试。
- 多 Store 使用同一 cache root 时由进程内 coordinator 串行准备；旧 generation 关闭后继续持有 root lease，
  直到既有 reservation 清理完毕，避免新 Engine startup sweep 删除仍在使用的 transfer。
- `Os.open` 成功但首次 `fstat` 失败时，raw descriptor 在对象构造边界关闭且不重试泄漏；专项单测验证
  exactly-once close。
- 新增直接使用生产 `android.system.Os` 的 instrumented suite，覆盖 symlink、hard-link、外部 length drift、
  final no-replace 和 descriptor close；Gate 同时读取 emulator SDK，非 API 23 结果不会冒充最低版本证据。

## 验证与边界

[测试证据](test-evidence/media-capture-android-transfer-store-file-identity-correction.log) 记录最终 Android
专项 Gate 退出 0：Core 88、UI 42、Bridge Adapter 71，Transfer Store 12；两个 instrumented APK 编译、
lint、Debug/Release AAR 和 Demo Debug APK 均通过。当前没有 ready emulator，因此 instrumented runtime
没有执行；API 23 的生产 `Os` 路径仍需对应 emulator/device 运行，不能宣称最低版本运行时已验证。

Android 公共 `Os` 没有 descriptor-relative `unlinkat`，identity 检查与 pathname unlink 之间仍存在同
App UID 信任域内的残余竞态。实现和文档均保留该边界，没有把它描述为抵御恶意同 UID 代码的隔离。
