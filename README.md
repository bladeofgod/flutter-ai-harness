# Flutter AI Harness

**[Read the detailed guide](https://htmlpreview.github.io/?https://github.com/bladeofgod/flutter-ai-harness/blob/main/docs/index.html)** · [中文 README](docs/README.zh-CN.md)

An AI-native engineering harness for production Flutter and hybrid mobile application repositories.

Flutter AI Harness helps coding agents work inside explicit, testable engineering boundaries. It combines repository-owned project contracts, focused agent roles, task artifacts, review loops, and executable quality gates. It is an engineering system for building applications with AI agents, not an SDK for adding AI features to a Flutter app.

This README is the primary adoption entry and project preview. The [detailed guide](https://htmlpreview.github.io/?https://github.com/bladeofgod/flutter-ai-harness/blob/main/docs/index.html) covers the system model, delivery workflow, security review, reference implementation, adoption paths, and future extensions.

## What This Repository Is

AI Harness is a repository-level engineering system for governing and executing AI-assisted software delivery. The Flutter Demo is its first governed reference implementation, not the Harness itself.

```text
AI Harness
├── Project contract: architecture boundaries, coding rules, security policy
├── Workflows: planning, execution, review, fixes, archival, release checks
├── Task system: task cards, dependencies, executors, acceptance criteria
├── Agent system: architect, executors, reviewer, security reviewer
├── Quality gates: static checks, tests, builds, evidence, CI
├── AI tool adapters: Claude Code and Codex
└── Reference technology stacks and adapters
    ├── Flutter / Dart
    ├── Android / Kotlin
    └── iOS / Swift
```

The reusable product is the project contract, delivery workflow, agent collaboration model, and executable quality loop. Flutter, Android, and iOS provide the current reference environment used to exercise and verify that system.

## Use the Harness in Your Project

Start a coding agent in the project you want to build or improve. Do not clone the Flutter Demo into that project. The Agent uses this repository as reference input, first produces an adoption plan, and changes the target only after you approve the plan.

This repository currently ships native project entries for Claude Code and Codex. Another coding agent can follow the same tool-neutral protocol when it has equivalent filesystem, shell, and instruction-control capabilities.

### 1. Start in the Target Directory

```bash
cd path/to/your-project
# Start Claude Code, Codex, or an equivalent coding agent here.
```

### 2. Paste the Bootstrap Prompt

```text
Adapt the AI Harness engineering model from
https://github.com/bladeofgod/flutter-ai-harness.git
to the current directory.

The current directory is the target project. The Harness repository is reference
input only. Keep the target read-only during phase one: do not edit its files,
install dependencies, initialize a project, commit, or push. The only permitted
write is cloning the Harness outside the target into a temporary directory. Do not
execute source-repository scripts. Record the exact source commit and follow
docs/adoption/AGENT_BOOTSTRAP.md.

If this is an existing project, audit its stack, architecture, instructions, tests,
CI, and current changes before proposing an adaptation plan. If the directory is
empty, first discuss the product requirements, targets, constraints, deployment,
team capabilities, and quality expectations with me. Do not select a stack or
initialize the project until I approve those decisions. If the directory is
ambiguous, ask me how it should be treated.

Do not copy the Flutter Demo, business code, archived tasks, reviews, or evidence.
Present the adoption plan, proposed files, verification commands, conflicts, and
unresolved decisions, then stop and wait for my approval.
```

### 3. Approve Before Implementation

Review the proposed stack and adaptation plan. When it is correct, continue with:

```text
Implement the approved adoption plan. Keep the target project's confirmed stack
and contract authoritative, adopt only capabilities with real consumers, preserve
existing work, and run the target-specific checks. Report every unverified platform
or unavailable environment. Do not commit or push unless I explicitly ask.
```

```text
Target directory
├── Existing project -> read-only audit -> adaptation plan -> approval -> implementation
├── Empty directory  -> requirements and stack discussion -> initialization plan -> approval -> implementation
└── Ambiguous files  -> ask the user and stop
```

Read the complete [Agent adoption protocol](docs/adoption/AGENT_BOOTSTRAP.md), [existing-project path](docs/adoption/existing-project.md), and [new-project path](docs/adoption/new-project.md). The adopted result belongs to the target repository; this repository does not become its runtime dependency.

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

## Run the Reference Demo

Running the Demo is optional. Use it to inspect a complete working example of task cards, reviews, evidence, architecture gates, and Flutter/Android/iOS integration. It is not a prerequisite for adopting the Harness.

Prerequisites: Claude Code 2.1.198 or later for the repository's Claude workflows, `ripgrep`, and either FVM or Flutter 3.41.9.

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

See the complete [reference evaluation path](docs/adoption/evaluation.md).

### Demo Preview

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

- [Agent adoption protocol](docs/adoption/AGENT_BOOTSTRAP.md)
- [Adopt in an existing project](docs/adoption/existing-project.md)
- [Start a new project](docs/adoption/new-project.md)
- [Detailed design and adoption guide](https://htmlpreview.github.io/?https://github.com/bladeofgod/flutter-ai-harness/blob/main/docs/index.html)
- [Authoritative project contract](CLAUDE.md)
- [Application architecture](docs/architecture.md)
- [Background article: AI 编程的工程化实践](https://mp.weixin.qq.com/s/XAV8U9SfvbGgsAC5Tj2GEA) (Chinese)

## Project Status

The Harness baseline, Demo UI, shared media resources, and Android/iOS Media Capture integration are implemented. The app uses deterministic local business data rather than production services. Android Debug and iOS no-codesign builds are verified; Android emulator/device capture flows and iOS camera, microphone, interruption, and performance acceptance remain manual device checks.

## License

Flutter AI Harness is available under the [MIT License](LICENSE).
