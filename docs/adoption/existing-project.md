# Adopt the Harness in an Existing Project

[Chinese version](./existing-project.zh-CN.md) · [Adoption protocol](./AGENT_BOOTSTRAP.md)

Use this path when the target already contains recognizable project facts. The goal is to strengthen the existing engineering system, not replace it with the Flutter reference architecture.

## Read-Only Audit

Inspect without changing state:

1. Existing project instructions, Agent files, architecture documents, and ownership rules.
2. Languages, frameworks, package boundaries, generated code, and dependency direction.
3. Build, format, lint, test, integration, release, and CI commands.
4. Current Git state and user-owned changes.
5. Security boundaries, external inputs, credentials policy, native permissions, and deployment surfaces.
6. Existing task, review, evidence, and documentation practices.

Do not execute the source Harness scripts against the target during this audit.

## Map Instead of Copying

For every proposed Harness asset, choose one disposition:

| Disposition | Meaning |
| --- | --- |
| `adopt` | The concept already fits and can be introduced with only target naming changes. |
| `adapt` | The concept is useful but must be rewritten for the target stack or existing conventions. |
| `omit` | The target has no real consumer, already has a stronger equivalent, or would be harmed by it. |

The plan must explicitly cover the project contract, task schema, executor routing, workflows, Agent source of truth, tool adapters, quality gates, CI, reviews, evidence, and archival rules.

## Conflict Rules

- User instructions and the target repository's approved contract take precedence over source Harness examples.
- Never overwrite an existing `CLAUDE.md`, `AGENTS.md`, CI workflow, hook, or build entry without explaining and obtaining approval for the merge strategy.
- Preserve stronger existing checks. Do not weaken them to match the reference repository.
- Do not introduce Flutter-specific platforms, roles, or commands unless Flutter is a real target consumer.
- Do not create roles or abstractions only to mirror the reference layout.

## Recommended Implementation Order

1. Establish or update the target-owned project contract.
2. Define target scopes, work kinds, executor routing, and document lifecycle.
3. Add only the necessary roles, workflows, skills, and memories.
4. Add tool-specific discovery adapters from one authoritative source.
5. Convert critical architecture and safety rules into executable checks.
6. Integrate focused checks with existing hooks and CI.
7. Validate the adopted workflow with one small, real target task.

Completion requires target-specific checks to pass, conflicts and omitted capabilities to be documented, and all unavailable environments to remain explicit.
