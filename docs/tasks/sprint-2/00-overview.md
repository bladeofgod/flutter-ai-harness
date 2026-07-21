# Sprint 2 Demo 基础能力规划

## 范围

本 Sprint 启动 `AI Harness Shoppe` Demo 的真实迭代。`ApiClient`、`AuthService` 和 `UserService` 已批准纳入 Demo 架构；首张任务先固化三者的 Demo 化职责、数据流和实现门槛，防止在具体页面和业务流程确定前引入无消费者的网络、认证、存储或数据库复杂度。

具体 Feature、UI、Domain Entity 和运行态 Spec 在用户提供对应 Figma 页面节点后另行拆卡，不纳入本次基础能力审计。

## 输入与事实来源

- `CLAUDE.md`：Package 依赖、业务 API、Domain Entity 和按需引入依赖的权威约束。
- `docs/architecture.md`：本地与未来远程数据链路、Registry 和 Feature 边界。
- `docs/api-contracts.md`：确定性本地 Fixture，以及 Dio、Proto、Drift 的启用条件。
- `docs/figma-links.md`：Shoppe 设计来源、作者和许可。
- 已批准产品决策：Demo 名称为 `ai-harness-shoppe`；当前没有真实 API，使用本地 Mock 数据。
- 已批准架构原则：保持接口自治、构造注入、全局 Service 生命周期和分层初始化，不引入私有业务代码、协议、环境值或认证编排。

## 依赖顺序

```text
S2-001 Demo 基础 Service 设计清册
        ↓
等待具体 Auth / Catalog Figma 页面节点与首批业务流程
        ↓
ApiClient / AuthService / UserService 实现任务另行规划
```

## 里程碑

1. 完成基础 Service 候选能力的决策状态和实现状态矩阵。
2. 固化 ApiClient 的 Fixture Transport、AuthService 的内存会话和 UserService 的当前用户职责。
3. 为存储、数据库、网络监听、环境和初始化器定义真实消费者触发条件。
4. 停止在运行时代码之前，等待首批页面范围决定三个已批准 Service 的具体公共 API。

## 风险

- 三个 Service 只保留通用架构职责，不得绑定私有 Endpoint、Proto 信封、Token 刷新、IM、账号切换或平台 SDK。
- 过早创建 `ServiceInitializer`、Storage 或业务接口会产生无消费者抽象，并误导模板使用者。
- Auth、购物车持久化和异常场景会改变用户行为，必须由具体页面和 UI 行为 Spec 驱动。

## 待决事项

- 首批实现的 Figma 页面和完整业务流程。
- 登录是显式 Mock 账号、免密 Demo Session，还是直接进入本地访客态。
- 购物车、收藏是否需要跨 App 重启保留。
- 具体商品图片、字体和图标的来源与许可。
