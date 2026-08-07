---
task: generate-media-capture-android-wire-codec
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：迁移 Android Media Capture Wire 生成代码

## 结论

- `MediaCaptureWire.g.kt` 由统一 manifest 生成并由 Adapter source set 直接编译，source digest 为
  `76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27`。
- 手写 Kotlin codec 消费生成的 channel/method/event/result/error、enum、descriptor、scalar 和 envelope
  primitive；Capability mapping、main-thread dispatch、controller/plugin、transfer/presentation、lifecycle 与
  exactly-once completion 仍保持手写。
- Kotlin escaping、Int64、nullable/unknown key、ByteArray 和闭合 enum 均 fail-closed，wire 值不依赖 enum
  name 或平台对象 description。
- Android 文档已明确生成边界和仍需真机验证的范围。

## 验证

- Android generator drift check：通过。
- Core Debug/Release：各 88 tests；Native UI Debug/Release：各 42 tests；Bridge Adapter Debug/Release：各
  75 tests，均 0 skipped/0 failures/0 errors。
- Core、Native UI、Bridge Adapter 的 lint、AAR assembly、依赖图和 Android contract vector gate：通过。
- 当前无 ready emulator，`connectedDebugAndroidTest` 未执行；该缺口不由 JVM/Robolectric 结果替代。

完整命令摘要见[测试证据](test-evidence/generate-media-capture-android-wire-codec.log)。复审未发现 P0/P1/P2。
