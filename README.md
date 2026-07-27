# Flutter AI Harness

**[Read the detailed guide](https://bladeofgod.github.io/flutter-ai-harness/)** · [中文 README](docs/README.zh-CN.md) · [中文详细指南](https://bladeofgod.github.io/flutter-ai-harness/zh-CN/)

An AI-native engineering harness for production Flutter and hybrid mobile application repositories.

Flutter AI Harness helps coding agents work inside explicit, testable engineering boundaries. It combines repository-owned project contracts, focused agent roles, task artifacts, review loops, and executable quality gates. It is an engineering system for building applications with AI agents, not an SDK for adding AI features to a Flutter app.

This README is a project preview and quick start. The [detailed guide](https://bladeofgod.github.io/flutter-ai-harness/) covers the system model, delivery workflow, security review, reference implementation, adoption paths, and future extensions.

## Demo Preview

> **Automated development record:** The Demo was completed in one overnight run, with no human intervention in implementation during execution. Human input covered design selection, scope decisions, and environment operations.

<table>
  <tr>
    <td><img src="docs/media/demo-app-preview-01.gif" alt="Ai-Harness Demo preview 01" width="240"></td>
    <td><img src="docs/media/demo-app-preview-02.gif" alt="Ai-Harness Demo preview 02" width="240"></td>
  </tr>
  <tr>
    <td><img src="docs/media/demo-app-preview-03.gif" alt="Ai-Harness Demo preview 03" width="240"></td>
    <td><img src="docs/media/demo-app-preview-04.gif" alt="Ai-Harness Demo preview 04" width="240"></td>
  </tr>
</table>

`Android Debug · deterministic local fixtures · four sequential previews · source recording duration: 1m 13s`

The Shoppe-inspired Demo includes Welcome, Auth, Shop, Categories, Product Detail, Wishlist, Cart, Checkout, Profile, Settings, Orders, Search, Promotions, Rewards, and Support flows. Its task cards, reviews, implementation evidence, and project documentation were produced through the Harness workflow rather than written as placeholder history.

Design source: [Shoppe Community design](https://www.figma.com/community/file/1321464360558173342/shoppe-ecommerce-clothing-fashion-store-multi-purpose-ui-mobile-app-design). Source and license notes are recorded in [`docs/figma-links.md`](docs/figma-links.md).

## At A Glance

- One authoritative project contract with generated Codex-native Skill and Agent adapters.
- Focused workflows for planning, Figma decomposition, implementation, review, risk-triggered security review, and release checks.
- Repository-owned architecture gates, Git hooks, evidence capture, and CI checks.
- A layered Flutter workspace with explicit package, data, routing, and dependency-injection boundaries.
- First-class Android and iOS host guidance, including contract-first platform channels.
- Optional Figma and Marionette integrations for design context and explicitly scheduled UI verification.

```text
Product input or Figma
        -> task cards
        -> implementation and focused tests
        -> independent review
        -> explicit fixes and re-review
        -> archived evidence
```

## Quick Start

Prerequisites: Claude Code 2.1.198 or later, `ripgrep`, and either FVM or Flutter 3.35.7.

```bash
git clone https://github.com/bladeofgod/flutter-ai-harness.git
cd flutter-ai-harness
make setup
make check
```

Run the local-fixture Demo:

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh run
```

The repository can also be used as an architecture reference for adapting the Harness to an existing project. It is not a runtime dependency, and the Demo does not need to be copied with the reusable engineering patterns.

## Repository Map

```text
flutter-ai-harness/
├── CLAUDE.md     Authoritative project contract
├── .claude/      Commands, agents, skills, and memories
├── .agents/      Generated Codex Skill adapters
├── .codex/       Generated Codex project Agents
├── docs/         Detailed guide, architecture, tasks, and reviews
├── scripts/      Hooks and executable quality gates
└── app/          Flutter workspace and reference Demo
```

## Continue Reading

- [Detailed design and adoption guide](https://bladeofgod.github.io/flutter-ai-harness/)
- [Authoritative project contract](CLAUDE.md)
- [Application architecture](docs/architecture.md)
- [Background article: AI 编程的工程化实践](https://mp.weixin.qq.com/s/XAV8U9SfvbGgsAC5Tj2GEA) (Chinese)

## Project Status

The Harness baseline and first complete Demo UI batch are implemented. All current Demo tasks are archived, and the app uses deterministic local data rather than production services. Android Debug build and runtime verification are available; iOS no-codesign builds and native permission flows still depend on a suitable Apple toolchain and device environment.

## License

Flutter AI Harness is available under the [MIT License](LICENSE).
