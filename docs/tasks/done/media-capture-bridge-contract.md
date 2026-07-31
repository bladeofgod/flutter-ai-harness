---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy:
  - media-capture-capability-contract
securityReview: required
---

# 从 Media Capture 能力派生 Flutter Bridge Contract

## 背景

Media Capture Capability Contract 已先定义模块公共语义。Flutter Bridge Contract 只负责把既有能力映射成 Channel 支持的基础类型、稳定 Wire 名称和跨 Runtime 生命周期，不得反向增加或改变 Native Module 的业务状态、权限与文件策略。

## 输入与事实来源

- `CLAUDE.md`
- `docs/native-architecture.md`
- `docs/infrastructure/media-capture.md`
- `docs/infrastructure/contracts/media-capture.capability.json`
- `docs/bridge/README.md`
- `.claude/agents/bridge-engineer.md`

## 目标

- 建立机器可校验的通用 Bridge Contract Schema。
- 从 Media Capture Capability 派生 method/event、Payload、版本和稳定错误码。
- 明确 Dart Client 与 Android/iOS Bridge Adapter 的映射、线程、生命周期和取消语义。
- 保持 Capability Contract 与 Wire Contract 的所有权、版本和演进边界分离。

## 非目标

- 不重新定义 Media Capture operation、state、permission、failure 或文件所有权。
- 不实现 Dart Client、Android/iOS Adapter、Camera Core 或 Native UI。
- 不增加平台权限、Host 注册、Route 或 Shoppe 页面。
- 不要求 Capability API 使用 Channel 字段名、裸 Map 或 Flutter 类型。

## 具体要求

1. 在固定路径新增 JSON 产物：通用 Wire Schema 为 `docs/bridge/contracts/wire.schema.json`，Media Capture Wire Contract 为 `docs/bridge/contracts/media-capture.wire.json`；使用标准 JSON Parser 和确定性结构校验，不以正则解析字段。
2. Wire Contract 逐项引用或映射 `docs/infrastructure/contracts/media-capture.capability.json` 中的稳定 operation/result/failure ID，声明独立 `wireVersion`、非空 `compatibleCapabilityVersions`、Channel、method/event 或等价异步结果模型、Payload Schema、可选字段、稳定错误码和 Android/iOS 支持矩阵。
3. 每个 Wire method/event 都必须能追溯到 Capability Contract；Bridge 不得创建 Native Module 不存在的状态、操作或文件生命周期。
4. Contract 只使用 Flutter Channel 支持的基础类型；未来 Adapter 在边界立即映射为类型化 Dart/Native Model，原始 Map 不进入 Native Core、Controller 或业务 API。
5. 媒体结果只映射 Capability 批准的受控句柄/临时文件描述与必要元数据；不得跨 Channel 传输媒体 bytes、Proto、CameraX/AVFoundation 类型或调用方任意路径。
6. 定义用户取消、系统 Failure、未知版本、非法字段、重复请求、Engine/Activity/ViewController 销毁和释放后 Callback 的 Wire 行为；异步结果只能完成一次。
7. method、event、error code 和枚举 Wire 值使用小写 `snake_case`；Payload key 风格在 Contract 中统一。
8. 新增 `docs/bridge/media-capture.md` 描述 Capability 到 Wire 的映射表、端到端顺序、线程、生命周期、平台差异、版本独立性和变更日志。
9. Wire Contract 变更不得自动修改 Capability Contract；确需新增模块能力时停止并回到 Capability 任务/后续版本决策。
10. 以 `app/tool/harness_check.dart` 为 Validator 入口、`scripts/quality/test-harness.sh` 为 Fixture 入口，验证上述固定 JSON 路径、Schema、命名、独立版本字段、兼容 Capability 版本、平台、稳定 ID 映射和文档引用；不得要求尚未存在的 Adapter 实现，也不得读取 Git 历史推断两个版本是否在同一次变更中升级。

## 同时编写的测试

- 有效 Wire Contract 通过。
- 缺少独立版本、Channel、Payload、错误码、平台或 Capability 映射时失败。
- Wire operation 无法追溯到 Capability 时失败。
- 出现媒体 bytes、Proto、原生 SDK 类型、自由结构或任意路径时失败。
- method/event/error/enum 不符合命名规则时失败。
- Wire 缺少独立 `wireVersion`、错误地只声明 `capabilityVersion`、未声明 `compatibleCapabilityVersions` 或声明不包含当前 Capability 版本时失败。
- Capability 与 Wire 版本数值相同或在同一 Commit 中合法升级不是失败条件；Fixture 只验证当前快照可观察的独立字段和兼容关系。

## 验收标准

- Native Capability 明确先于且独立于 Flutter Bridge Contract。
- Android/iOS Core 不需要读取本 Wire Contract 即可实现公共 API。
- 后续 Dart/Android/iOS Adapter 可以确定性完成 Wire/Native Model 映射。
- Capability 与 Wire 各自拥有版本和变更日志，Bridge 无法反向扩大模块能力。
- Security Review 覆盖外部输入、文件句柄、错误 details、生命周期和协议版本。
- `make harness-check`、`make harness-test` 和 `git diff --check` 通过。

## 验证命令

```bash
make harness-check
make harness-test
git diff --check
```

## 平台或环境限制

本任务不需要 Android/iOS SDK、设备、Figma 或 Marionette。本任务完成后仍不得直接创建或执行 Bridge 实现；`native-harness-bootstrap-gate` 验证全部 Bootstrap 产物后统一生成第二阶段任务。Bridge 实现不与最终 UI 设计绑定。

## 执行结果

- [实现 Review](../../reviews/execute-media-capture-bridge-contract.md)
- [Security Review](../../reviews/security-media-capture-bridge-contract.md)
- [测试证据](../../reviews/test-evidence/media-capture-bridge-contract.log)
