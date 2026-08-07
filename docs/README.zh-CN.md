# Flutter AI Harness

**[阅读详细指南](https://htmlpreview.github.io/?https://github.com/bladeofgod/flutter-ai-harness/blob/main/docs/zh-CN/index.html)** · [English README](../README.md)

面向生产级 Flutter 与混合移动应用仓库的 AI 原生工程 Harness。

Flutter AI Harness 帮助编码 Agent 在明确、可测试的工程边界内工作。它将仓库内的项目契约、聚焦的 Agent 角色、任务产物、审查闭环和可执行质量门禁组合成一套工程系统。本项目用于通过 AI Agent 构建应用，不是在 Flutter App 内增加 AI 功能的运行时 SDK。

这份 README 只提供项目预览和最短上手路径。[详细指南](https://htmlpreview.github.io/?https://github.com/bladeofgod/flutter-ai-harness/blob/main/docs/zh-CN/index.html)将持续承载系统模型、交付流程、安全审查、参考实现、采用方式和后续扩展内容。

## 这个仓库是什么

AI Harness 是一套运行在代码仓库之上的 AI 工程制度和执行系统。Flutter Demo 是它的第一个被治理对象和参考实现，不是 Harness 本身。

```text
AI Harness
├── 项目契约：架构边界、编码规则、安全策略
├── 工作流：规划、执行、Review、修复、归档、发版检查
├── 任务系统：任务卡、依赖、执行者、验收条件
├── Agent 系统：架构师、执行者、Reviewer、安全 Reviewer
├── 质量门禁：静态检查、测试、构建、证据、CI
├── AI 工具适配：Claude Code / Codex
└── 参考技术栈与适配
    ├── Flutter / Dart
    ├── Android / Kotlin
    └── iOS / Swift
```

真正可复用的是项目契约、交付工作流、Agent 协作模型和可执行质量闭环。Flutter、Android 与 iOS 构成当前用于实践和验证这套系统的参考环境。

## Demo 预览

> **自动化开发记录：** 当前 Demo 在一个通宵内完成，执行阶段没有人工介入代码实现。人工输入仅包括设计稿选择、范围确认和环境操作。

<table>
  <tr>
    <td><img src="./media/demo-app-preview-01.gif" alt="Ai-Harness Demo 预览 01" width="240"></td>
    <td><img src="./media/demo-app-preview-02.gif" alt="Ai-Harness Demo 预览 02" width="240"></td>
  </tr>
  <tr>
    <td><img src="./media/demo-app-preview-03.gif" alt="Ai-Harness Demo 预览 03" width="240"></td>
    <td><img src="./media/demo-app-preview-04.gif" alt="Ai-Harness Demo 预览 04" width="240"></td>
  </tr>
</table>

`Android Debug · 确定性本地 Fixture · 四段连续预览 · 原始录制时长：1 分 13 秒`

Shoppe 风格 Demo 包含 Welcome、Auth、Shop、Categories、Product Detail、Wishlist、Cart、Checkout、Profile、Settings、Orders、Search、Promotions、Rewards 和 Support 流程。它的任务卡、Review、实现证据和项目文档均由 Harness 的实际工作流产生，不是预先编写的占位历史。

设计稿来源：[Shoppe Community 设计稿](https://www.figma.com/community/file/1321464360558173342/shoppe-ecommerce-clothing-fashion-store-multi-purpose-ui-mobile-app-design)。来源与许可记录见 [`docs/figma-links.md`](./figma-links.md)。

## 核心概览

- 以一份权威项目契约为事实源，并生成 Codex 原生 Skill 与 Agent 适配。
- 覆盖任务规划、Figma 拆解、实现、审查、按风险触发的安全审查和发版检查。
- 用仓库内架构门禁、Git Hooks、证据采集和 CI 检查约束交付过程。
- 通过分层 Flutter Workspace 明确 Package、数据、路由和依赖注入边界。
- 将 Android 和 iOS 作为一等宿主，并采用契约优先的平台通道规范。
- 可选接入 Figma 和 Marionette，读取设计上下文并执行人工明确安排的 UI 验证。

```text
产品输入或 Figma
        -> 任务卡
        -> 实现与聚焦测试
        -> 独立审查
        -> 显式修复与复审
        -> 归档证据
```

## 快速开始

前置环境：Claude Code 2.1.198 或更高版本、`ripgrep`，以及 FVM 或 Flutter 3.41.9。

```bash
git clone https://github.com/bladeofgod/flutter-ai-harness.git
cd flutter-ai-harness
make setup
make check
```

运行使用本地 Fixture 的 Demo：

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh run
```

本仓库也可以作为工程架构参考，用于将 Harness 模式改造到现有项目。它不是运行时依赖，复用工程模式时也不要求复制 Demo。

## 仓库结构

```text
flutter-ai-harness/
├── CLAUDE.md     权威项目契约
├── .claude/      Command、Agent、Skill 和 Memory
├── .agents/      生成的 Codex Skill 适配
├── .codex/       生成的 Codex 项目 Agent
├── docs/         详细指南、架构、任务卡与 Review
├── scripts/      Hooks 和可执行质量门禁
└── app/          Flutter Workspace 与参考 Demo
```

## 继续了解

- [设计与采用详细指南](https://htmlpreview.github.io/?https://github.com/bladeofgod/flutter-ai-harness/blob/main/docs/zh-CN/index.html)
- [权威项目契约](../CLAUDE.md)
- [应用架构](./architecture.md)
- [背景文章：AI 编程的工程化实践](https://mp.weixin.qq.com/s/XAV8U9SfvbGgsAC5Tj2GEA)

## 当前状态

Harness 基线、Demo UI、Flutter 媒体资源与 Android/iOS 原生拍摄集成已经实现。应用使用确定性本地业务数据，不代表生产服务；Android Debug APK 与 iOS no-codesign Runner 已通过构建。Android 模拟器/真机拍摄流程，以及 iOS Camera、Microphone、系统中断与性能仍保留为人工设备验收项。

## 许可证

Flutter AI Harness 使用 [MIT License](../LICENSE)。
