# Run the Reference Demo

[Chinese version](./evaluation.zh-CN.md) · [Adoption protocol](./AGENT_BOOTSTRAP.md)

This path evaluates the reference repository itself. It does not adopt the Harness into another project and is not required before adoption.

Prerequisites: Claude Code 2.1.198 or later for the repository's Claude workflows, `ripgrep`, and either FVM or Flutter 3.41.9.

```bash
git clone https://github.com/bladeofgod/flutter-ai-harness.git
cd flutter-ai-harness
make setup
make check
```

Run the deterministic local-fixture Demo:

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh run
```

Use the reference checkout to inspect real task cards, reviews, bounded evidence, architecture gates, generated Codex adapters, and Android/iOS integration. Do not copy its Demo business code, archived history, credentials, or Flutter-specific rules into a target project without an approved adoption plan.
