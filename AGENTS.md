# Productivity Time Repository Instructions

## Scope

- These instructions apply only to this repository.
- Keep project-specific Codex agents under `.codex/agents/` in this repository. Do not install or copy them into `~/.codex/agents/` or another global Codex location.

## Product contract

- Build a native macOS productivity application.
- Users can create named activities and run each activity as either a stopwatch or a timer.
- Resetting a stopwatch records a completed session; pausing or stopping without reset does not.
- A timer records a completed session only when the timer reaches zero.
- Store title, mode, elapsed or configured duration, completion date, and a stable session identifier.
- For the MVP, deliver every completed session to both Apple Notes and Notion as title, duration, and date.
- Maintain independent durable, idempotent delivery state for Apple Notes and Notion, so either destination can succeed, fail, retry, and recover without masking the other.
- Make external writes idempotent so retries cannot silently create duplicate session records.
- Store credentials and tokens through an appropriate macOS credential mechanism. Never commit secrets.

## Engineering rules

- Prefer Swift and SwiftUI, using AppKit only where macOS behavior requires it.
- Keep timekeeping based on monotonic time; do not derive elapsed duration from timer tick counts.
- Separate domain logic, persistence, and external integrations behind testable interfaces.
- Use test-driven development for features and fixes.
- Preserve unrelated user changes and never use destructive Git commands without explicit approval.
- Run focused tests while working and the complete available test/build suite before completion.
- Do not claim completion without fresh verification evidence.

## Project-local development environment

- Keep all dependencies, caches, generated files, build artifacts, and scripting environments inside this repository.
- Use project-local locations such as `.venv`, `node_modules`, `.build`, or a repository-local DerivedData directory when those ecosystems apply.
- Do not use `sudo`, install global packages, or write to `/usr`, `/usr/local`, `/opt/homebrew`, system Library directories, or other machine-level locations without explicit user approval.
- Do not modify global shell profiles, global Git configuration, global Codex configuration, or global package-manager state for this project.
- If a required tool cannot be installed or cached inside the project, stop and request permission before changing the machine.
- Keep secrets in ignored project-local environment files or the macOS credential store; commit only sanitized examples such as `.env.example`.

## Orchestration

- The primary Codex session is the orchestrator. It owns clarification, architecture, decomposition, task assignment, integration, verification, and final reporting.
- For implementation, delegate bounded work to the project custom agents under `.codex/agents/`.
- Use `macos_core_implementer` for the application shell, timer/stopwatch domain, persistence, and macOS lifecycle.
- Use `integrations_implementer` for the MVP Apple Notes and Notion adapters, permissions, Keychain credentials, retries, idempotency, and integration tests.
- Use `quality_implementer` for test infrastructure, regression tests, accessibility validation, build verification, and targeted fixes assigned by the orchestrator.
- Use `github_manager` for GitHub workflows, branch management, pull requests, issue tracking, and release milestone coordination.
- All implementation agents use `gpt-5.6-terra` with high reasoning effort.
- The `github_manager` uses `gpt-5.6-luna` with high reasoning effort.
- Use the read-only `orchestration_advisor`, which runs `gpt-5.6-sol` with high reasoning effort, only to review architecture, task decomposition, sequencing, and integration decisions. It must not implement code or perform the final security review.
- Give every delegated write task explicit file ownership and acceptance criteria.
- Run independent read-heavy tasks in parallel when useful. Run write-heavy tasks in parallel only when file ownership does not overlap; otherwise run them sequentially.
- Require every implementer to report changed files, verification commands and results, and remaining risks.
- After integration and repository-level verification, delegate a final read-only review to `security_reviewer`, which uses `gpt-5.6-terra` with high reasoning effort.
- The final review must cover correctness, security, secrets, permissions, unsafe automation, data leakage, injection, concurrency, persistence, regressions, and missing tests.
- Route each material finding back to the appropriate Terra implementer. Rerun verification and request a follow-up Terra security review before declaring completion.

## Git milestones

- Treat an approved spec, a completed implementation slice, an integration milestone, and a verified review-fix pass as important milestones.
- After every important milestone, create a focused Git commit with only that milestone's changes.
- Push the current feature branch to the configured GitHub remote after each milestone when authentication and network access are available.
- Never force-push. Do not push directly to a protected main branch unless the user explicitly authorizes it.
- Before committing or pushing, verify the relevant tests and inspect the staged diff for secrets and unrelated changes.

## Code review rules

- Treat committed credentials, tokens, private user content, or verbose integration logs as blocking findings.
- Treat duplicate external session creation, incorrect stopwatch reset semantics, and timer completion before zero as blocking findings.
- Treat UI-only timing logic, wall-clock duration calculation, and untested integration error paths as correctness risks.
- Prefer concrete findings with file references, reproduction steps, and expected behavior. Avoid style-only findings unless they hide a functional or security problem.
