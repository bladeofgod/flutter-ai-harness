# Start a New Project with the Harness

[Chinese version](./new-project.zh-CN.md) · [Adoption protocol](./AGENT_BOOTSTRAP.md)

Use this path when no recognizable project exists in the target directory. An empty target is not permission to copy the Flutter Demo or let the Agent select a stack without the user.

## Discuss the Product Before the Stack

The Agent should first understand the product outcome, then ask only questions that materially change architecture or delivery. Cover, as relevant:

- Product type: mobile app, web app, backend, desktop app, SDK, CLI, or multi-runtime system.
- Required targets and compatibility ranges.
- Required or prohibited languages, frameworks, databases, cloud services, and deployment environments.
- Native capabilities, offline behavior, authentication, payments, realtime communication, and regulated data.
- Team experience, maintenance horizon, release process, and operational constraints.
- Testing depth, CI, security review, observability, and release evidence expectations.

The Agent should propose a small number of coherent stack options, explain tradeoffs, recommend one, and record unresolved decisions. It must not initialize the project yet.

## Approval Gate

Implementation remains blocked until the user approves:

1. Product scope and explicit non-goals.
2. Target platforms or runtimes.
3. Technology stack and dependency policy.
4. Initial architecture and ownership boundaries.
5. Build, test, CI, and release validation approach.
6. The file and directory initialization plan.

## Build the Project and Harness Together

After approval:

1. Initialize the smallest real application or service that proves the selected stack.
2. Create a target-owned project contract using confirmed facts, not reference Demo assumptions.
3. Define target-specific task scopes, executors, workflows, and quality gates.
4. Add only Agent roles and skills needed by the initial consumers.
5. Establish one authoritative Agent source and generate supported tool adapters.
6. Wire formatting, analysis, tests, builds, and CI to the selected toolchain.
7. Validate the setup with one small, real task and preserve its truthful evidence.

Do not populate empty architecture layers, fabricate task history, or add integrations before a real consumer exists. The resulting repository should be able to explain why every initial dependency, role, and gate is present.
