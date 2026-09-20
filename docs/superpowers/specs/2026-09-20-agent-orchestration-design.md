# Agent Orchestration Design

## Purpose

This repository will use project-scoped Codex instructions and custom agents to build a native macOS productivity timer. The orchestration layer must keep implementation work bounded, prevent concurrent edits from colliding, and require an independent security and correctness review before work is declared complete.

This document covers only the Codex orchestration structure. It does not scaffold or implement the application.

## Selected Approach

Use Codex's official project-scoped layout:

- `AGENTS.md` for repository-wide product constraints, engineering rules, delegation policy, and completion gates.
- `.codex/config.toml` for multi-agent defaults and concurrency limits.
- `.codex/agents/*.toml` for narrowly scoped custom agent roles.

No `.agents/` compatibility directory will be created because Codex discovers project custom agents under `.codex/agents/`.

## Alternatives Considered

1. **Project-scoped custom agents — selected.** Keeps model, effort, sandbox, and role instructions versioned with the repository and reproducible for every contributor.
2. **`AGENTS.md` only.** Simpler, but model routing and reviewer isolation would depend on each prompt and would be easier to apply inconsistently.
3. **Personal agents under `~/.codex/agents/`.** Supports the same role controls, but is machine-specific and would not travel with the public repository.

## Roles

### Primary orchestrator

The primary Codex session remains the orchestrator. It owns requirement clarification, architecture decisions, task decomposition, task assignment, conflict avoidance, integration, and final reporting. It must not delegate ambiguous or overlapping write scopes.

### macOS core implementer

- Model: `gpt-5.6-terra`
- Reasoning effort: `high`
- Sandbox: `workspace-write`
- Scope: Xcode project structure, SwiftUI/AppKit application shell, timer and stopwatch domain logic, persistence, and macOS lifecycle behavior.

### integrations implementer

- Model: `gpt-5.6-terra`
- Reasoning effort: `high`
- Sandbox: `workspace-write`
- Scope: the MVP Apple Notes adapter and later explicitly assigned Notion work, credential handling, permission flows, retries, idempotency, and integration-focused tests.

### orchestration advisor

- Model: `gpt-5.6-sol`
- Reasoning effort: `high`
- Sandbox: `read-only`
- Scope: architecture, task decomposition, sequencing, and integration advice only. This role never implements product code or performs the final security review.

### quality implementer

- Model: `gpt-5.6-terra`
- Reasoning effort: `high`
- Sandbox: `workspace-write`
- Scope: test infrastructure, regression tests, accessibility checks, build verification, and targeted fixes assigned by the orchestrator.

### security reviewer

- Model: `gpt-5.6-terra`
- Reasoning effort: `high`
- Sandbox: `read-only`
- Scope: final independent review for secrets exposure, unsafe automation, permission misuse, data leakage, injection risks, concurrency defects, persistence corruption, regressions, and missing tests.
- The reviewer reports findings and does not edit files. The orchestrator routes fixes back to the appropriate Terra implementer, reruns verification, and requests another review when material findings existed.

## Orchestration Rules

1. The primary session first converts approved work into small tasks with explicit file ownership and acceptance criteria.
2. Independent read-heavy work may run in parallel.
3. Write-heavy tasks may run in parallel only when their file ownership does not overlap. Otherwise they run sequentially.
4. Every implementation task is assigned to a Terra High role and must return changed files, tests run, results, and known risks.
5. The primary session integrates the work and runs repository-level verification.
6. Sol High performs the final read-only security and correctness review.
7. Any substantive finding reopens implementation. Completion requires the fix, passing verification, and a clean follow-up review.

The project concurrency limit will be three spawned agents. This matches the available worker capacity while leaving orchestration in the primary session.

## Repository Instructions

`AGENTS.md` will preserve the product contract:

- The app is native to macOS.
- Users can create named timer and stopwatch activities such as study, reading, or rest.
- Resetting a stopwatch records a session; pausing or stopping alone does not.
- A timer records a session only when it reaches zero.
- Each completed session records title, mode, duration, and date.
- MVP sessions are delivered to Apple Notes. Notion delivery remains a post-MVP product requirement.
- Secrets must never be committed and must be stored through an appropriate macOS credential mechanism.
- External writes must be idempotent or carry stable identifiers so retries do not silently duplicate sessions.

The file will also require test-driven development for features and fixes, proportionate build/test verification, minimal changes, no destructive Git commands, and explicit reporting of blockers.

All development dependencies, caches, generated files, and scripting environments must remain project-local. Agents must not use `sudo`, install global packages, or write to system-level paths without explicit user approval. When a tool cannot be isolated inside the repository, the agent must stop and request permission before installing it.

After every important milestone, the orchestrator must create a focused Git commit and push the current feature branch to the configured GitHub remote. Force-pushes and direct pushes to a protected main branch remain prohibited unless the user explicitly authorizes them.

## Planned Files

```text
AGENTS.md
.codex/
  config.toml
  agents/
    macos-core-implementer.toml
    integrations-implementer.toml
    quality-implementer.toml
    orchestration-advisor.toml
    security-reviewer.toml
docs/
  superpowers/
    specs/
      2026-09-20-agent-orchestration-design.md
```

## Validation

Validation for this orchestration layer will include:

- TOML parsing for every `.toml` file.
- Presence checks for all required custom-agent fields: `name`, `description`, and `developer_instructions`.
- Exact checks that implementers and the reviewer use `gpt-5.6-terra` with `high` effort, while the read-only orchestration advisor uses `gpt-5.6-sol` with `high` effort.
- Inspection that `AGENTS.md` defines orchestration, verification, and final-review gates without granting agents broader authority than the user's task.
- A clean Git diff review before handoff.

## Out of Scope

- Application source code or Xcode scaffolding.
- Product UI design.
- Apple Notes or Notion credentials and live authorization.
- CI/CD and release signing.
- Deployment or App Store submission.
