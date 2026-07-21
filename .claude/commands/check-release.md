---
description: 检查仓库是否满足发版条件，但不执行发布
argument-hint: "[版本号或发布约束]"
---

执行发版就绪检查。用户未明确要求时，不打 Tag、不上传、不发布、不 push。

## 检查项

1. 确认发布范围和基线 Commit。
2. 确认计划任务已完成或显式延后。
3. 确认 Review 报告已有完成的复审结论。
4. 运行 `make check` 和必要的代码生成同步检查。已有 UI Spec 只做 Schema 一致性检查，不要求 Audit 或 Run 齐全。
5. 只有用户把某个 UI Spec 明确列入本次发布门禁时，才检查其 Audit、实现摘要和用户指定平台的 App Operator 报告；不得从任务卡或 Spec 的存在自动推导该门禁。
6. 存在完整用户旅程或 Plugin/Bridge 改动时，使用 `make integration-test INTEGRATION_DEVICE=<device-id>` 运行集成测试，并构建受影响平台；CI 的 Android/iOS Debug Job 必须通过。
7. 检查 Bridge 契约版本和变更日志。
8. 检查生成产物、依赖锁、发布配置、签名占位和敏感信息扫描。
9. 检查用户可见变化、已知限制和回滚考虑。

## 产物

写入 `docs/reviews/release-<version>.md`，包含：

- 每个门禁的通过/失败结论。
- 精确命令证据。
- P0/P1 阻塞项。
- 延后风险和负责人。
- 本地未验证平台。
- 最终建议：可发布、有条件可发布或不可发布。
