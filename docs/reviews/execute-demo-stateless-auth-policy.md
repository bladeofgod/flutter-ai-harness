---
task: demo-stateless-auth-policy
status: passed
p0: 0
p1: 0
---

# Demo 无状态 Auth 规则执行审查

## 审查结论

- P0：0
- P1：0
- P2：0
- 状态：通过，可以归档。

## 已确认边界

- `FixtureApiTransport` 不再持有账号 Map 或注册密码记录。账号查询和登录只依据规范化 Email 生成稳定 User/Session；相同 Email 跨 Transport 结果一致，不同 Email 的 ID 不冲突。
- `romina@example.com` 保持原设计名称、ID 和头像基准。其他有效 Email 可直接登录；`00000000` 只承担确定性错误密码演示，其他恰好 8 位的密码成功，密码仍通过 `Secret` 传输且诊断输出脱敏。
- 注册每次根据当次 Email、区号、Phone 和 Avatar 创建独立 `AuthResult`，不写入账号状态。重复注册不会产生本地唯一性假象，后续账号查询和登录使用默认合成资料。
- 注册头像链路保持完整：Picker 结果由 Registration Controller 转成 `UserAvatar.memory`，LocalDataSource/Mapper 防御性往返字节，`AuthStateCoordinator` 保存同一注册快照，Profile 最终创建 `MemoryImage` 展示该头像。
- `accountNotFound`、`duplicateAccount` 公共业务失败及 Controller 映射仍保留，未来真实 API 或测试 Fake 可以产生；只是当前无状态 Fixture 不产生这两类失败。
- 未引入 Drift、SecureStorage、文件缓存、远程 API、Proto 或新的跨包依赖；现有 Controller、ApiClient、LocalDataSource、Registry、Coordinator 和 Router 边界未改变。

## Review 修正

首轮检查发现 Demo 路由测试仍只使用初始 Romina 账号，不能直接证明“未注册 Email 可登录”，错误密码页面也主要依赖 Fake API。已将真实 Registry 的路由回归改为未注册 Email，并补充保留密码进入 Wrong Password/Recovery 入口的测试；聚焦测试通过，问题已关闭。

## 验证与剩余风险

- [`test-evidence/demo-stateless-auth-policy.log`](test-evidence/demo-stateless-auth-policy.log) 记录的 `make analyze`、`make test`、`make lint`、最终 `make harness-check`、`git diff --check` 和补强后的 Demo Router 聚焦测试均退出 0，证据脱敏检查通过。日志同时保留了任务归档后相对链接失效导致的一次 Harness 失败；修正归档路径后复跑已通过。
- Transport 重建测试覆盖“不保存注册资料”，但没有执行真实 App 进程杀死/重启；本任务没有任何持久化写入路径，该缺口不阻断无状态 Demo 验收。
- 本任务不改变原生宿主或依赖配置，因此未重复执行 Android/iOS Build。UI Spec、Audit 和 App Operator 未运行，符合人工独立安排边界。
