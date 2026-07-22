# Shoppe Auth 与 Profile 规划审查

## 首轮独立审查

- P0：0
- P1：4
- P2：2
- 状态：需要修复后复审。

### P1：未经确认的 Demo 行为被标成已确认产品规则

- 位置：`docs/figma/shoppe-auth-flow-design-context.md`
- 问题：Email 派生 displayName、未知账号错误、手机号校验和输满 8 位自动提交并非 Figma 或用户原话确认。
- 修法：拆分“用户确认的产品规则”和“可替换 Demo 工程默认”，任务执行时不得把后者描述为设计事实。

### P1：Login Controller 跨 Route 生命周期未定义

- 位置：`docs/tasks/done/shoppe-login-recovery-flow.md`
- 问题：Login、Password、Recovery 共享 Email/User 状态，但 Route 级 Controller 会丢失状态；direct 子 Route 也缺少前置用户。
- 修法：使用单一 Login Flow 父级 Scope 持有 Controller，在离开整个流程时释放；缺少前置用户的 direct Route 返回 Login。

### P1：Profile 当前用户注入契约冲突

- 位置：`docs/tasks/shoppe-profile-dashboard.md`
- 问题：静态 UserEntity 快照无法满足用户变化测试，Feature 又不能反向依赖壳工程 UserService。
- 修法：由壳工程提供只读 `CurrentUserProvider`，Profile Controller 构造注入、订阅并释放；最终由统一的 `AuthStateCoordinator` 实现该契约，避免与 Router 登录态形成两个独立通知源。

### P1：密码脱敏没有覆盖持有密码的数据层与传输层

- 位置：`docs/tasks/shoppe-auth-local-foundation.md`
- 问题：只测试 Service `toString` 无法阻止 Freezed 输入、ApiRequest、Fixture Payload 或 Failure 展开密码。
- 修法：使用手写 Secret/Password Value Object 和显式传输红线，覆盖各层字符串化与异常测试。

### P2：遗漏注册表单的 Poppins 字体事实

- 位置：`docs/figma/shoppe-auth-flow-design-context.md`、`docs/tasks/done/shoppe-registration-flow.md`
- 修法：记录 Poppins Medium 约 13.8 的 Figma 事实，并要求本地字体、OFL 许可和 AssetBundle 测试。

### P2：图片选择没有解码与内存上限

- 位置：`docs/tasks/done/shoppe-registration-flow.md`
- 修法：限制 Picker 尺寸/质量和读取字节数，覆盖取消、超限、解码失败和路径不泄漏。

## 首轮验证

- `make harness-check`：通过。
- `git diff --check`：通过。
- Figma 节点、尺寸和主要视觉事实：复核一致。
- App Operator/UI Spec：未嵌入普通任务流程。

## 第二轮独立复审

- 原首轮 P1：4 项均已关闭。
- 原首轮 P2：2 项均已关闭。
- 新增 P1：1 项，登录 Session 与当前用户由两个 Service 分别通知，缺少原子提交与通知顺序约束，可能产生“已登录但用户尚未写入”的可观察中间状态。
- 修法：保留 AuthService/UserService 的独立存储职责，增加唯一写入与通知入口 `AuthStateCoordinator`。认证事务先提交匹配的 User/Session、登出事务先清空二者，再各发送一次 Router/Provider 共享通知；禁止绕过 Coordinator 的公共写入路径。
- 状态：已完成文档修正并提交最终独立复审。

## 最终独立复审

- P0：0。
- P1：0。
- P2：0。
- 第二轮新增的认证状态一致性问题已关闭：Router 与 `CurrentUserProvider` 同源于 `AuthStateCoordinator`，认证/登出只发布一次满足 Session/User 不变量的共享通知。
- 首轮 4 项 P1、2 项 P2 均未回归；四张任务卡依赖无环，普通任务仍未嵌入 UI Spec、Audit 或 App Operator 门禁。
- `make harness-check`：通过。
- `git diff --check`：通过。
- 状态：规划审查通过，可以进入任务执行。
