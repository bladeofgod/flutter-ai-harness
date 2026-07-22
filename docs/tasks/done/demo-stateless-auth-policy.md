---
executor: task-executor
blockedBy: [shoppe-auth-local-foundation, shoppe-registration-flow, shoppe-login-recovery-flow]
---

# 调整 Demo 无状态 Auth 规则

> 状态：已完成并通过独立 Review。

## 背景

当前 `FixtureApiTransport` 只允许初始 Fixture 账号登录，并把注册账号保存在 Transport 实例的内存 Map 中。注册账号会在 App 重启后消失，导致用户随后从“已有账号”入口无法登录。Demo 不需要建立账号数据库，登录流程应对任意格式有效的 Email 可用，同时保留错误密码与 Recovery UI 的演示入口。

## 输入

- [`docs/figma/shoppe-auth-flow-design-context.md`](../../figma/shoppe-auth-flow-design-context.md)
- [`docs/api-contracts.md`](../../api-contracts.md)
- [`docs/tasks/done/shoppe-auth-local-foundation.md`](shoppe-auth-local-foundation.md)
- [`docs/tasks/done/shoppe-registration-flow.md`](shoppe-registration-flow.md)
- [`docs/tasks/done/shoppe-login-recovery-flow.md`](shoppe-login-recovery-flow.md)

## 实现要求

1. 将本地账号查询和登录改为确定性无状态规则：任意通过 `EmailAddress` 校验的 Email 都能查询到一个合成用户，不依赖注册记录或进程内账号 Map。
2. 合成用户的 ID、displayName 和 Session ID 必须由规范化 Email 稳定生成；默认使用 Romina 头像和公开 Demo 电话信息。`romina@example.com` 继续显示 Romina，避免现有设计基准漂移。
3. 登录密码仍必须由 Domain/Controller 校验为恰好 8 位。`00000000` 固定返回 `invalidCredentials`，用于进入 Wrong Password 与 Recovery 演示；其他 8 位密码登录成功。不得记录或输出密码。
4. 注册不保存账号，也不做本地重复 Email 拒绝；每次调用直接根据当次输入返回 `AuthResult`。
5. 注册结果必须完整保留当次提交的国家区号、Phone 和头像。用户选择内存头像后，返回的 `UserEntity` 必须携带防御性复制的相同图片字节，交给 `AuthStateCoordinator` 后由 Profile 在当前会话立即展示。
6. 注册头像和资料不跨 App 重启持久化，也不影响后续“已有账号”登录生成的默认用户；不引入 Drift、SecureStorage、文件缓存或账号仓库。
7. 保留 `AuthFailureCode.accountNotFound`、`duplicateAccount` 等公共失败枚举，供未来真实 API 和测试 Fake 使用；当前本地 Fixture 不必产生这些失败。
8. 更新 Auth 设计上下文、API 数据策略和已归档任务中的后续规则说明，明确本任务覆盖的 Demo 行为，避免把历史任务要求静默改写为原始事实。

## 同批测试

- `app_data`：任意有效 Email 可查询；同一 Email 跨 Transport 生成稳定用户，不同 Email 生成不同 ID；任意非保留 8 位密码成功，`00000000` 失败。
- `app_data`：注册不依赖或改变账号状态；重复注册可独立成功；注册内存头像字节防御性往返；后续查询/登录恢复默认头像。
- `app_features`：Registry 的本地 Auth API 遵循相同无状态规则，并保持 Domain 类型与稳定失败映射。
- Demo Route：注册选择的头像提交成功后，`AuthStateCoordinator.value` 与 Profile 都展示该内存头像；登录任意有效 Email 可进入 Profile；错误密码入口仍可达。
- 回归：Registration Controller、Login/Recovery、Profile、Harness 与仓库边界测试继续通过。

## 验收标准

- 用户不需要预先注册即可从“已有账号”使用任意有效 Email 和非保留 8 位密码登录。
- `00000000` 确定性触发错误密码状态，Recovery UI 仍可演示。
- 注册选择的头像在注册成功后的当前会话 Profile 中准确展示，App 重启和独立登录不保存该头像。
- Auth 链路保持 `Controller -> AuthApi -> LocalDataSource -> ApiClient -> FixtureApiTransport`，没有新增持久化或跨层数据泄漏。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
make harness-check
git diff --check
```

## 后续边界

- 真实账号存在性、注册唯一性、密码校验和资料持久化需在接入权威 API/存储契约后另立任务。
- UI Spec、Audit 和 App Operator 仍由人工独立安排，不随本任务自动执行。
