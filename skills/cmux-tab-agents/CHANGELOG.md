# Changelog

All notable changes to cmux-tab-agents are documented here.

## Fixed

- **Structurally prevent `.cmux-*` files from being committed** (ISSUE-44): Dispatcher now injects `.cmux-*` and `.cmux-tab-prompt-*.md` patterns into the worktree's `.gitignore` automatically via `_ensure_cmux_gitignore()`, ensuring planner artifacts are protected without requiring consumer repo configuration. Injection is idempotent. Added `make lint` check to verify `.cmux-*` is in `.gitignore`. Updated `operational-guide.md` with setup notes on safe staging practices before dispatch.

- **`ensure-worktree.sh` branches from stale local main** (ISSUE-49): `ensure-worktree.sh` now fetches `origin/main` and branches new worktrees from it instead of a potentially stale local `main`. This eliminates the need to manually pull before creating a worktree and prevents inheriting out-of-date bases. Idempotent resume logic preserved: if a branch already exists, it is reused as before.

## Changed

- **Agent-to-agent review loop without planner involvement during iteration** (ISSUE-26): The implementer is now the **task lead** — it dispatches spec-reviewer and code-reviewer itself, loops on ISSUES_FOUND, and pushes one terminal message to the planner. New flags: `dispatch-implementer.sh --max-loop-iterations <n>` (default 5); `dispatch-spec-reviewer.sh` and `dispatch-code-reviewer.sh` accept `--lead-surface` so reviewers push ISSUES_FOUND back to the implementer and APPROVED to both implementer and planner. New `{{LEAD_SURFACE}}` and `{{MAX_LOOP_ITERATIONS}}` template placeholders in `_dispatch_common.sh`. Circuit-breaker fires on same issue twice or max iterations → BLOCKED escalation to planner. New roll-up file `.cmux-task-result.md` written by the implementer after all reviews pass. SKILL.md updated: planner dispatches `dispatch-implementer.sh` only; `dispatch-spec-reviewer.sh` and `dispatch-code-reviewer.sh` retained for manual use.

## Added

- **Session persistence with crex for 3-phase cycle** (CREX-POC-001-3): Tab-agents now integrate with `crex` (cmux-resurrect) to save and restore workspace state. The implementer saves session state via `crex save <timestamp>` before exiting, allowing spec-reviewer and code-reviewer to restore the workspace if they need to revisit work (e.g., on ISSUES_FOUND). This prevents zombie tabs and enables resumable workflows across session boundaries. README documents crex installation and setup (Stop hook configuration). Updated all three prompts with crex references: implementer saves state (Step 5), spec-reviewer can restore on investigation, code-reviewer monitors for zombie tabs.

- **Automated finish modes for implementer dispatch** (ISSUE-27): `dispatch-implementer.sh` now accepts `--finish-mode <mode>` to automate the post-review finish step. Modes: `keep` (default; noop), `pr` (push + open PR), `merge` (merge to main + clean). Includes `finish-task.sh` helper script with verification gate, mode-specific logic, and idempotency. See `references/finishing.md` for complete documentation, acceptance criteria compliance, and planner workflow examples.

- **Copy-pastable focus shortcuts for surface refs** (ISSUE-37): Tab-agents now emit a copy-pastable `cmux rpc surface.focus` command on a second line when they push terminal-state messages. The command lets users jump directly to the agent's surface. Boot sequence captures `OWN_SURFACE` via `cmux identify --no-caller` and injects it into the push. Surface ref detection is graceful — if unavailable (e.g., dispatched from outside cmux), the focus line is skipped. Updated in: all three seed prompts (boot sequence), discipline.md (push protocol), SKILL.md (two-line format and reporting convention), and reporting-contract.md.
