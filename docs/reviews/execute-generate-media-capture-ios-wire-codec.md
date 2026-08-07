---
task: generate-media-capture-ios-wire-codec
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：迁移 iOS Media Capture Wire 生成代码

## 结论

- `MediaCaptureWire.generated.swift` 由统一 manifest 生成并由 Bridge Core SwiftPM target 显式编译，source
  digest 为 `76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27`。
- 手写 Swift codec/controller/models 消费生成的协议标识、enum、descriptor、scalar 和 envelope primitive；
  Capability mapping、MainActor、controller、transfer/presentation、文件 cleanup 与 lifecycle 继续手写。
- Swift escaping、Int64、NSNumber/Bool、NSNull/nullable、Data/Flutter bytes 和闭合 enum 均 fail-closed；错误与
  日志不回显原始 payload、URI、handle、bytes 或平台对象 description。
- iOS 文档和 Bridge Core reviewed test count 已同步生成边界。

## 验证

- iOS generator drift check、Package graph、import allowlist、20 个共享 URI vector：通过。
- 四个 Swift Package product 的 generic iOS Simulator SDK compile：通过。
- Simulator XCTest：Core/Rendering 107、Native UI 52、Bridge Core 70，合计 229，0 skipped。
- safe-copy、临时 Flutter SwiftPM Host 无签名构建与 plugin discovery：通过；真实 Demo Host和用户 Flutter
  配置摘要前后不变。
- 首次证据采集在隔离 Host build 出现瞬时失败；单独复跑 Host helper 成功后，完整门禁从头复跑并退出 0，
  最终证据已覆盖失败记录。
- 真机 live camera、系统权限 UI、麦克风、硬件中断和性能仍未验证，不由 Simulator 结果替代。

完整命令摘要见[测试证据](test-evidence/generate-media-capture-ios-wire-codec.log)。复审未发现 P0/P1/P2。
