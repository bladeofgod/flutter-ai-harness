---
name: flutter-concurrency
description: "适用：导致掉帧的 CPU 密集任务、大数据解析/聚合或长期 Isolate Worker。不适用：普通 async/await、Dio 请求、Stream 或 I/O 防抖。触发词：Isolate.run、Isolate.spawn、compute、SendPort、ReceivePort、掉帧、CPU-bound。"
paths: ["app/**/*isolate*.dart", "app/**/*worker*.dart", "app/**/*_parser*.dart", "app/**/*_processor*.dart"]
---

# Dart 并发

## 先判断

- 等待 I/O：使用 `Future`/`Stream`，Isolate 不会让网络更快。
- 单次 CPU 重任务且参数可发送：使用 `Isolate.run` 或 `compute`。
- 高频 CPU 任务且启动成本明显：考虑受管理的 Worker Isolate。
- OS 后台执行：使用平台支持的后台任务 API，不假设 Dart Isolate 永久在线。

## 规则

- 引入 Isolate 前先测量 Frame Time 或 CPU 开销。
- 只传可发送的不可变数据，不传 `BuildContext`、Controller、数据库 Handle、Platform Channel 或 SDK 对象。
- 传输后在正确边界完成协议到 Entity 映射。
- 明确定义取消、Worker 关闭、错误传播和 App 生命周期归属。
- 批处理任务，避免消息成本超过计算收益。
- 主 Isolate 只发布进度和状态，并最小化 UI 重建。

先测试纯计算，再测试 Worker 成功、失败、取消和释放。
