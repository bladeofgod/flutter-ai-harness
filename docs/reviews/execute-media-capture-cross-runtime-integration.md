---
task: media-capture-cross-runtime-integration
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：Media Capture 跨 Runtime 最终集成

## 结论

独立普通 Review 与修复复审通过，P0 0、P1 0、P2 0，可以归档。首轮审查发现 P1 4 项、P2 1 项；
实现修复后，Reviewer 重新只读核对任务、共享契约、三端消费者、Harness、Host 接线、文档和原始
evidence，确认问题全部关闭。

## 已关闭问题

- Capability V4/Wire V3 golden 已覆盖当前 methods/events/failures、Capability 与 Wire failure 来源、
  transfer 限额/MIME/signed-64/URI/长度、lifecycle、cleanup、redaction 和历史投影，不再只校验文件名。
- Dart/Kotlin/Swift 三端消费者逐段断言同一份 golden；golden 同时绑定消费者实现摘要，Harness 会在消费者
  漂移或遗漏字段时失败。
- Harness 对 Wire/Capability failure 分区、方法数量、MIME、signed-64、consumer path/digest 和 Info.plist
  结构执行精确校验；fixture 覆盖空权限说明、错误类型、注释伪装、重复 key 和三端弱消费者。
- Android/iOS、Bridge、基础能力、媒体资源与中英文入口文档已按真实实现状态对齐；Bridge 当前方法数为
  17，设备运行缺口没有被构建或 Simulator 证据替代。

## 验证与边界

[测试证据](test-evidence/media-capture-cross-runtime-integration.log) 记录了 root `make check` 退出 0、Android
Core/UI/Bridge 88/42/71、iOS Core/UI/Bridge 101/51/69、Android Debug APK、真实 Demo iOS Debug
no-codesign Host build、三端 contract vectors、Harness fixture 和文档门禁。iOS Gate 的隔离临时 Host 曾因
网络 clone 挂起而中止，随后同一 Host helper 在已审查环境中单独通过；代码与契约检查没有失败。

Android 当前没有 ready emulator/device，因此 API 23 instrumented 和主动 Camera/Gallery 流程未运行；iOS
真机 Camera/Microphone、系统权限 UI、硬件中断、真实帧与性能也保留给人工验收。上述缺口已在共享文档
中明确保留，不能由 Fake、Simulator 或另一平台代替。
