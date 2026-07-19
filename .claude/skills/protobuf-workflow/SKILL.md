---
name: protobuf-workflow
description: "适用：修改 .proto、Dart 生成产物、协议 Envelope、API Endpoint 或 Proto→Entity Mapper。不适用：纯 JSON API，也不允许手工编辑生成文件。触发词：protobuf、proto、protoc、generated、mapper、wire field、API contract。"
paths: ["protos/**", "app/packages/app_data/lib/generated/**", "app/packages/app_data/lib/mappers/**", "app/packages/app_core/lib/network/**", "app/packages/app_features/lib/**/api/**"]
---

# Protobuf 工作流

当前仅保留流程占位。Demo 引入首个真实公开协议时，必须先建立可复现的 `protoc`/Plugin 版本、目录和生成检查；在此之前不得宣称 `make proto` 可用。

1. 将仓库内 `.proto` 定义及注释视为 wire 事实源。
2. 先改协议，再改消费者。
3. 通过仓库生成器更新代码，禁止手工编辑生成 Dart 文件。
4. 在 `app_data` 或私有 Adapter 中将 Proto Message 映射为包自有 Domain Entity。
5. 公共 API、Controller、Route 参数和 UI 状态不得出现 Proto 类型。
6. 使用 Domain Entity 定义 Feature 侧抽象 API。
7. 在归属 Feature/基础设施模块中使用 Mapper 实现 API。
8. 在装配点注册实现。
9. 测试可选字段、未知 enum、默认值、Envelope、失败和必要的 Round Trip。
10. 运行 `make proto-check`、静态分析和受影响测试。

不兼容 wire 变化必须先协调版本和兼容策略。未知 enum 必须可预测降级，不得让 UI 崩溃。
