---
task: media-capture-ios-transfer-store-startup-preparation-stability-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# iOS Transfer Store 启动准备稳定性修正 Review

## 结论

独立普通 Review 通过，P0 0、P1 0、P2 0。修复只改变测试对启动 sweep 中间状态和 Store ready
终态的等待方式，未修改 Transfer Store 生产实现或对外协议。

## 根因与修复

- `prepare()` 会先删除 restart residue，再发布 `generationOpen` 和 `.ready`；文件删除不是准备完成的同步
  信号。
- 原测试观察到 residue 删除后立即断言 `isAvailable`，偶发命中两者之间的合法异步窗口。
- 修正后的有界轮询同时等待 residue 不存在和 Store 可用，仍只通过 Store 构造触发准备，没有调用
  `prepare()` 或创建 reservation。
- 循环结束后继续分别断言文件已删除和 Store 可用；准备失败不会被轮询掩盖。

## 验证

脱敏证据位于
[`media-capture-ios-transfer-store-startup-preparation-stability-correction.log`](./test-evidence/media-capture-ios-transfer-store-startup-preparation-stability-correction.log)：

- 完整 Bridge Core 69 项 Simulator XCTest 全部通过。
- `MediaCaptureBridgeCore` generic Simulator SDK Debug build 在严格并发检查下通过。
- `git diff --check` 和 `make harness-check` 均通过。

## 验证边界

Simulator 文件系统测试不替代真机 Camera、权限、硬件中断或性能验收。
