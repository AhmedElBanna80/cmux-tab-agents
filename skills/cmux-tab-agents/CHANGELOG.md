# Changelog

All notable changes to the cmux-tab-agents skill are documented here.

## [Unreleased]

### Changed
- **Seed prompt shrinkage (ISSUE-16):** Extracted stable, task-independent discipline rules into a shared reference file (`references/discipline.md`) to reduce per-task token cost.
  - `prompts/implementer-tab-prompt.md`: 503 lines → 76 lines
  - `prompts/spec-reviewer-tab-prompt.md`: 203 lines → 73 lines
  - `prompts/code-reviewer-tab-prompt.md`: 183 lines → 66 lines
  - All three now point to the unified `references/discipline.md` (491 lines) containing:
    - TDD red-green-refactor discipline
    - Verification before completion discipline
    - Hook-bypass prohibition rules
    - Code organization guidance
    - Report format and push protocol (shared principles)
    - Core hard rules
  - Net result: 41% reduction in combined seed prompt size; per-task token cost reduced (discipline reference may be cached or shared across tasks)
- **SKILL.md refactored for clarity (ISSUE-24):** Moved verbatim upstream quote blocks to `references/upstream-quotes.md`, reducing main documentation from ~370 lines to 249 lines.
  - "Why subagents" section replaced with 1-line summary + reference.
  - "Status handling" section tightened with decision-critical rules condensed; full upstream wording moved to reference.
  - Dispatch command examples moved to `references/dispatch-reference.md` for more compact main guide.
  - Skill directory structure moved to `references/skill-structure.md`.
  - Edge cases and integration with other skills moved to `references/operational-guide.md`.
  - "See also" section expanded to list all reference documents.
- Dispatch scripts now support `[models]` configuration section (backward-compatible) (ISSUE-18)

### Added
- **Verification artifact for reviewers (ISSUE-23):** Implementer now writes an optional `.cmux-implementer-verification.json` artifact alongside its result file, capturing test, lint, build, and hook verification results. Reviewers can use this artifact to reduce re-verification scope when the artifact is fresh, consistent, and shows all steps passing. See `references/reporting-contract.md` for schema and usage guidelines. Ensures honest reporting: failed or skipped verification steps must be reflected accurately in the artifact.
- **Per-phase model defaults (ISSUE-18):** `[models]` section in `.claude/cmux-tab-agents.toml` allows configuring default Claude models for each phase (implementer, spec_reviewer, code_reviewer), avoiding repeated `--model` flags and reducing costs on mechanical review tasks. Precedence: CLI `--model` flag > repo config `[models].<phase>` > global `default_model` > global default. See `references/configuration.md` for details.
- **Copy-pastable focus shortcuts for surface refs (ISSUE-37):** Tab-agents now emit a copy-pastable `cmux rpc surface.focus` command on a separate line each time they push a terminal-state message. The command lets users jump directly to the agent's tab without typing the JSON by hand. Boot sequence now captures `OWN_SURFACE` via `cmux identify --no-caller` and injects it into the focus command. Surface ref detection is graceful — if unavailable (e.g., dispatched from outside cmux), the agent skips the focus suffix rather than emitting a broken command.

### Details (ISSUE-16)
- Created `references/discipline.md` with verbatim discipline language from:
  - `superpowers:test-driven-development @ 5.0.7`
  - `superpowers:verification-before-completion @ 5.0.7`
  - `superpowers:subagent-driven-development` (custom hook-bypass prohibition)
- Refactored all three seed prompts to replace inline discipline sections with pointers to the reference
- No discipline rules were lost in migration; all stable content is preserved verbatim
- Dispatch rendering verified to correctly substitute `{{WORKTREE}}` placeholder for discipline file path

### New (ISSUE-24)
- `references/upstream-quotes.md` — Verbatim text from upstream `superpowers:subagent-driven-development`.
- `references/dispatch-reference.md` — Detailed dispatch script examples and all command-line flags.
- `references/skill-structure.md` — Skill directory and file organization.
- `references/operational-guide.md` — Troubleshooting (edge cases) and skill integration notes.
