---
name: dart-coding-standards
description: "适用：编写或审查 Dart/Flutter 生产代码，尤其是 Controller、Service、Stream、异步任务和依赖注入。不适用：Kotlin、Swift 或生成代码规范。触发词：Dart、Controller、Service、StreamSubscription、unawaited、dynamic、DI、重构。"
paths: ["app/**/*.dart"]
---

# Dart 编码规范

## 边界

- 公共接口和跨包调用只使用 Domain Entity。
- 必需协作者通过构造函数注入。
- 依赖只在装配点解析；Controller 内只允许访问显式全局 Service。
- UI、业务编排和 Adapter 留在各自所属层。

## 类型

- 禁止显式 `dynamic`；使用具体类型、`Object?`、密封结果类型或带类型的 Map Adapter。
- 有限状态使用 enum 或 sealed type。
- 业务阈值和重复视觉值使用具名常量。
- 公共 API 不得暴露生成类型、协议类型、数据库类型或 SDK 类型。

## 异步与生命周期

- 影响正确性的 Future 必须 await。
- Fire-and-forget 必须有显式错误处理和诊断上下文。
- Subscription、Timer、Worker 和 Listener 必须由生命周期所有者保存并释放。
- 转换异常时保留 Stack Trace。
- 只有明确兜底边界才允许宽捕获；详见 `.claude/memories/catch-type-selection.md`。

## Flutter

- `build` 保持声明式，业务编排进入 Controller/Use Case。
- 按职责拆 Widget，不按任意行数拆分。
- 响应式 Builder 只包裹实际读取状态的最小子树。

## 验证

格式化触碰文件，运行受影响分析和测试；共享契约变化时扩大范围。禁止手工修改生成文件。
