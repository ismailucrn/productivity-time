# Agent Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repository-scoped Codex orchestration configuration with Terra High implementation roles and a read-only Sol High final reviewer.

**Architecture:** The repository root `AGENTS.md` is the orchestration contract read by every Codex session. `.codex/config.toml` sets multi-agent defaults and concurrency, while four narrow `.codex/agents/*.toml` files bind role instructions to explicit models, reasoning effort, and sandbox access.

**Tech Stack:** Markdown, TOML, Python 3 standard-library `tomllib`, Git, Codex project configuration.

**Spec:** `docs/superpowers/specs/2026-09-20-agent-orchestration-design.md`

## Global Constraints

- Use the official project-scoped Codex layout: `AGENTS.md`, `.codex/config.toml`, and `.codex/agents/*.toml`.
- Do not create a `.agents/` compatibility directory.
- All implementation roles use `gpt-5.6-terra` with `model_reasoning_effort = "high"` and `sandbox_mode = "workspace-write"`.
- The final reviewer uses `gpt-5.6-sol` with `model_reasoning_effort = "high"` and `sandbox_mode = "read-only"`.
- The primary session remains the orchestrator and assigns non-overlapping file ownership before parallel writes.
- Completion requires repository-level verification and a clean Sol High review; material findings reopen implementation.
- Keep dependencies, caches, generated files, and scripting environments project-local. Do not use `sudo`, global package installation, or system paths without explicit user approval.
- After every important milestone, create a focused Git commit and push the current feature branch to the configured GitHub remote; never force-push or bypass protected-branch policy.
- This plan must not create application source code, Xcode scaffolding, credentials, CI/CD, or deployment configuration.

## Review Focus

- **Model drift:** every implementation role must resolve to Terra High, while the final reviewer must resolve to Sol High.
- **Reviewer mutation risk:** the security reviewer must be read-only and explicitly prohibited from editing files.
- **Incomplete role schema:** every custom-agent file must contain non-empty `name`, `description`, and `developer_instructions` fields.
- **Write conflicts:** repository instructions must forbid parallel write tasks with overlapping file ownership.
- **Premature completion:** repository instructions must require fixes, rerun verification, and follow-up review after material findings.

---

### Task 1: Add the Repository Orchestration Contract

**Files:**
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: the product and orchestration requirements in `docs/superpowers/specs/2026-09-20-agent-orchestration-design.md`.
- Produces: repository-wide instructions that define `macos_core_implementer`, `integrations_implementer`, `quality_implementer`, and `security_reviewer` responsibilities and the primary-session workflow.

- [ ] **Step 1: Run the contract check and verify it fails**

Run:

```bash
test -f AGENTS.md \
  && rg -q 'gpt-5\.6-terra' AGENTS.md \
  && rg -q 'gpt-5\.6-sol' AGENTS.md \
  && rg -q 'Resetting a stopwatch' AGENTS.md \
  && rg -q 'timer reaches zero' AGENTS.md
```

Expected: non-zero exit status because `AGENTS.md` does not exist.

- [ ] **Step 2: Create the repository contract**

Create `AGENTS.md` with this content:

```markdown
# Productivity Time Repository Instructions

## Product contract

- Build a native macOS productivity application.
- Users can create named activities and run each activity as either a stopwatch or a timer.
- Resetting a stopwatch records a completed session; pausing or stopping without reset does not.
- A timer records a completed session only when the timer reaches zero.
- Store title, mode, elapsed or configured duration, completion date, and a stable session identifier.
- Deliver every completed session to both Apple Notes and Notion as title, duration, and date.
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
- Keep all dependencies, caches, generated files, and scripting environments inside the repository. Use project-local locations such as `.venv`, `node_modules`, `.build`, or a repository-local DerivedData directory when those ecosystems apply.
- Do not use `sudo`, install global packages, or write to `/usr`, `/usr/local`, `/opt/homebrew`, system Library directories, or other machine-level locations without explicit user approval.
- If a required tool cannot be installed or cached inside the project, stop and request permission before changing the machine.
- Keep secrets in ignored project-local environment files or the macOS credential store; commit only sanitized examples such as `.env.example`.

## Orchestration

- The primary Codex session is the orchestrator. It owns clarification, architecture, decomposition, task assignment, integration, verification, and final reporting.
- For implementation, delegate bounded work to the project custom agents under `.codex/agents/`.
- Use `macos_core_implementer` for the application shell, timer/stopwatch domain, persistence, and macOS lifecycle.
- Use `integrations_implementer` for Apple Notes and Notion adapters, permissions, credentials, retries, and idempotency.
- Use `quality_implementer` for test infrastructure, regression tests, accessibility validation, build verification, and targeted fixes assigned by the orchestrator.
- All implementation agents use `gpt-5.6-terra` with high reasoning effort.
- Give every delegated write task explicit file ownership and acceptance criteria.
- Run independent read-heavy tasks in parallel when useful. Run write-heavy tasks in parallel only when file ownership does not overlap; otherwise run them sequentially.
- Require every implementer to report changed files, verification commands and results, and remaining risks.
- After integration and repository-level verification, delegate a final read-only review to `security_reviewer`, which uses `gpt-5.6-sol` with high reasoning effort.
- The final review must cover correctness, security, secrets, permissions, unsafe automation, data leakage, injection, concurrency, persistence, regressions, and missing tests.
- Route each material finding back to the appropriate Terra implementer. Rerun verification and request a follow-up Sol review before declaring completion.
- After every important milestone, create a focused Git commit and push the current feature branch to the configured GitHub remote.
- Never force-push. Do not push directly to a protected main branch unless the user explicitly authorizes it.

## Code review rules

- Treat committed credentials, tokens, private user content, or verbose integration logs as blocking findings.
- Treat duplicate external session creation, incorrect stopwatch reset semantics, and timer completion before zero as blocking findings.
- Treat UI-only timing logic, wall-clock duration calculation, and untested integration error paths as correctness risks.
- Prefer concrete findings with file references, reproduction steps, and expected behavior. Avoid style-only findings unless they hide a functional or security problem.
```

- [ ] **Step 3: Run the focused contract checks**

Run:

```bash
test -f AGENTS.md
rg -n 'gpt-5\.6-terra|gpt-5\.6-sol|Resetting a stopwatch|timer reaches zero|file ownership does not overlap|follow-up Sol review' AGENTS.md
```

Expected: all six required concepts appear and both commands exit successfully.

- [ ] **Step 4: Review the contract for forbidden scope expansion**

Run:

```bash
rg -n 'App Store submission|deploy|credential value|API token value' AGENTS.md
```

Expected: no matches and exit status 1.

- [ ] **Step 5: Commit the repository contract**

```bash
git add AGENTS.md
git commit -m "chore: define repository agent workflow"
```

### Task 2: Add Project Multi-Agent Configuration

**Files:**
- Create: `.codex/config.toml`
- Create: `.codex/agents/macos-core-implementer.toml`
- Create: `.codex/agents/integrations-implementer.toml`
- Create: `.codex/agents/quality-implementer.toml`
- Create: `.codex/agents/security-reviewer.toml`

**Interfaces:**
- Consumes: role names and responsibilities defined by `AGENTS.md`.
- Produces: four discoverable custom Codex roles named `macos_core_implementer`, `integrations_implementer`, `quality_implementer`, and `security_reviewer`, plus a three-agent concurrency cap.

- [ ] **Step 1: Run the TOML presence check and verify it fails**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

required = [
    Path('.codex/config.toml'),
    Path('.codex/agents/macos-core-implementer.toml'),
    Path('.codex/agents/integrations-implementer.toml'),
    Path('.codex/agents/quality-implementer.toml'),
    Path('.codex/agents/security-reviewer.toml'),
]
missing = [str(path) for path in required if not path.is_file()]
assert not missing, f"missing: {missing}"
PY
```

Expected: `AssertionError` listing all five missing files.

- [ ] **Step 2: Create the project defaults**

Create `.codex/config.toml`:

```toml
[agents]
enabled = true
max_concurrent_threads_per_session = 3
default_subagent_model = "gpt-5.6-terra"
default_subagent_reasoning_effort = "high"
```

- [ ] **Step 3: Create the macOS core implementer**

Create `.codex/agents/macos-core-implementer.toml`:

```toml
name = "macos_core_implementer"
description = "Implements the native macOS app shell, timer and stopwatch domain, persistence, and lifecycle behavior."
model = "gpt-5.6-terra"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
developer_instructions = """
Work only within the file ownership and acceptance criteria assigned by the orchestrator.
Use test-driven development. Keep timekeeping independent from SwiftUI rendering and based on monotonic time.
Do not implement Apple Notes or Notion transport unless the orchestrator explicitly assigns an integration boundary.
Preserve unrelated changes. Return changed files, commands run, exact results, and remaining risks.
"""
```

- [ ] **Step 4: Create the integrations implementer**

Create `.codex/agents/integrations-implementer.toml`:

```toml
name = "integrations_implementer"
description = "Implements Apple Notes and Notion adapters, permissions, credentials, idempotency, retries, and integration tests."
model = "gpt-5.6-terra"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
developer_instructions = """
Work only within the integration files and acceptance criteria assigned by the orchestrator.
Use test-driven development and protocol-driven adapters. Never hard-code, print, or commit credentials or private note content.
Use stable session identifiers and explicit retry behavior so partial failures cannot silently duplicate records.
Do not change timer semantics or unrelated UI files. Return changed files, commands run, exact results, and remaining risks.
"""
```

- [ ] **Step 5: Create the quality implementer**

Create `.codex/agents/quality-implementer.toml`:

```toml
name = "quality_implementer"
description = "Builds test infrastructure, regression coverage, accessibility checks, and targeted fixes assigned by the orchestrator."
model = "gpt-5.6-terra"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
developer_instructions = """
Own only test, verification, accessibility, or targeted-fix files assigned by the orchestrator.
Prefer deterministic tests with fake clocks and fake external adapters. Reproduce a defect before changing production code.
Do not weaken assertions to make failures pass and do not broaden scope into unrelated refactors.
Return changed files, commands run, exact results, and remaining risks.
"""
```

- [ ] **Step 6: Create the final security reviewer**

Create `.codex/agents/security-reviewer.toml`:

```toml
name = "security_reviewer"
description = "Performs the final read-only correctness, security, privacy, and regression review after repository verification passes."
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
developer_instructions = """
Review only; never edit files, create commits, or alter external state.
Inspect the complete diff and relevant execution paths. Prioritize correctness, secret exposure, permission misuse, unsafe automation, data leakage, injection, timer concurrency, persistence corruption, duplicate external writes, regressions, and missing tests.
Lead with findings ordered by severity. Include file references, reproduction or evidence, impact, and the smallest safe remediation.
If no material findings remain, state that explicitly and list residual risks or verification gaps.
"""
```

- [ ] **Step 7: Parse every TOML file and validate the complete role matrix**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import tomllib

config = tomllib.loads(Path('.codex/config.toml').read_text())
agents = config['agents']
assert agents['enabled'] is True
assert agents['max_concurrent_threads_per_session'] == 3
assert agents['default_subagent_model'] == 'gpt-5.6-terra'
assert agents['default_subagent_reasoning_effort'] == 'high'

expected = {
    'macos-core-implementer.toml': ('macos_core_implementer', 'gpt-5.6-terra', 'high', 'workspace-write'),
    'integrations-implementer.toml': ('integrations_implementer', 'gpt-5.6-terra', 'high', 'workspace-write'),
    'quality-implementer.toml': ('quality_implementer', 'gpt-5.6-terra', 'high', 'workspace-write'),
    'security-reviewer.toml': ('security_reviewer', 'gpt-5.6-sol', 'high', 'read-only'),
}

for filename, values in expected.items():
    data = tomllib.loads((Path('.codex/agents') / filename).read_text())
    name, model, effort, sandbox = values
    assert data['name'] == name
    assert data['model'] == model
    assert data['model_reasoning_effort'] == effort
    assert data['sandbox_mode'] == sandbox
    assert data['description'].strip()
    assert data['developer_instructions'].strip()

reviewer = tomllib.loads(Path('.codex/agents/security-reviewer.toml').read_text())
assert 'never edit files' in reviewer['developer_instructions']
print('agent orchestration configuration: valid')
PY
```

Expected: `agent orchestration configuration: valid`.

- [ ] **Step 8: Commit the custom agents**

```bash
git add .codex/config.toml .codex/agents
git commit -m "chore: configure project subagents"
```

### Task 3: Audit the Integrated Orchestration Layer

**Files:**
- Verify: `AGENTS.md`
- Verify: `.codex/config.toml`
- Verify: `.codex/agents/*.toml`
- Verify: `docs/superpowers/specs/2026-09-20-agent-orchestration-design.md`
- Verify: `docs/superpowers/plans/2026-09-20-agent-orchestration.md`

**Interfaces:**
- Consumes: the completed repository contract and role configuration from Tasks 1 and 2.
- Produces: evidence that the orchestration layer matches the approved design and is ready to govern application implementation in a new Codex session.

- [ ] **Step 1: Confirm the official layout and reject the obsolete layout**

Run:

```bash
test -f AGENTS.md
test -f .codex/config.toml
test "$(find .codex/agents -type f -name '*.toml' | wc -l | tr -d ' ')" = "4"
test ! -e .agents
```

Expected: all commands exit successfully.

- [ ] **Step 2: Check the five review-focus conditions**

Run:

```bash
rg -n 'gpt-5\.6-terra|gpt-5\.6-sol|sandbox_mode = "read-only"' .codex
rg -n 'file ownership does not overlap|follow-up Sol review' AGENTS.md
python3 - <<'PY'
from pathlib import Path
import tomllib

for path in sorted(Path('.codex/agents').glob('*.toml')):
    data = tomllib.loads(path.read_text())
    for key in ('name', 'description', 'developer_instructions'):
        assert isinstance(data[key], str) and data[key].strip(), f'{path}: invalid {key}'
print('required custom-agent fields: valid')
PY
```

Expected: exact model/sandbox lines, both orchestration gates, and `required custom-agent fields: valid`.

- [ ] **Step 3: Review the complete diff and repository state**

Run:

```bash
git diff --check
git status --short --branch
git log --oneline --decorate -5
```

Expected: `git diff --check` has no output, the working tree contains only the plan file if it has not yet been committed, and the log contains the design and orchestration commits.

- [ ] **Step 4: Commit the implementation plan if still uncommitted**

```bash
git add docs/superpowers/plans/2026-09-20-agent-orchestration.md
git commit -m "docs: add agent orchestration implementation plan"
```

- [ ] **Step 5: Record the session-boundary requirement**

Report that Codex loads `AGENTS.md` and project agent configuration at session start. Start the application implementation in a new Codex session from the repository root so the new instructions and custom roles are discovered.
