# 运行参考 Demo

[English version](./evaluation.md) · [采用协议](./AGENT_BOOTSTRAP.zh-CN.md)

本路径只用于评估参考仓库本身，不会把 Harness 采用到其他工程中，也不是正式采用前的必经步骤。

前置环境：使用仓库 Claude 工作流时需要 Claude Code 2.1.198 或更高版本；此外需要 `ripgrep`，以及 FVM 或 Flutter 3.41.9。

```bash
git clone https://github.com/bladeofgod/flutter-ai-harness.git
cd flutter-ai-harness
make setup
make check
```

运行使用确定性本地 Fixture 的 Demo：

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh run
```

参考 checkout 可用于检查真实任务卡、Review、有界证据、架构门禁、生成的 Codex 适配和 Android/iOS 集成。没有批准后的采用方案时，不得把 Demo 业务代码、归档历史、凭据或 Flutter 专属规则复制到目标工程。
