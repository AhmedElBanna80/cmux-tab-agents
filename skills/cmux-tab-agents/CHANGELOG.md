# Changelog

All notable changes to cmux-tab-agents are documented here.

## Added

- **Automated finish modes for implementer dispatch** (ISSUE-27): `dispatch-implementer.sh` now accepts `--finish-mode <mode>` to automate the post-review finish step. Modes: `keep` (default; noop), `pr` (push + open PR), `merge` (merge to main + clean). Includes `finish-task.sh` helper script with verification gate, mode-specific logic, and idempotency. See `references/finishing.md` for complete documentation, acceptance criteria compliance, and planner workflow examples.

- **Copy-pastable focus shortcuts for surface refs** (ISSUE-37): Tab-agents now emit a copy-pastable `cmux rpc surface.focus` command on a second line when they push terminal-state messages. The command lets users jump directly to the agent's surface. Boot sequence captures `OWN_SURFACE` via `cmux identify --no-caller` and injects it into the push. Surface ref detection is graceful — if unavailable (e.g., dispatched from outside cmux), the focus line is skipped. Updated in: all three seed prompts (boot sequence), discipline.md (push protocol), SKILL.md (two-line format and reporting convention), and reporting-contract.md.
