# Changelog

All notable changes to cmux-tab-agents will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **ISSUE-17: Cache-friendly seed prompt rendering** — Restructured all tab-agent seed prompts (implementer, spec-reviewer, code-reviewer) to separate static prefix from dynamic task context tail. The static prefix (containing ~95% of the prompt text) is now byte-identical across dispatches, enabling Anthropic's 5-minute auto-cache to reuse it across multiple tab-agent spawns. This reduces token costs by caching the stable prefix once and only paying for the small task-specific tail per dispatch.
  - `references/prompt-rendering.md` — Documents the prompt caching contract, explaining the prefix/tail structure and rules for maintaining cacheability when editing prompts.
  - `tests/test-prompt-prefix-caching.sh` — Automated test suite verifying that:
    - Prompt prefixes are byte-identical across dispatches with different task text
    - No placeholders appear in the cacheable prefix region
    - All placeholders are confined to the tail section
- **ISSUE-21: `--fix-only` re-dispatch mode** for `dispatch-implementer.sh`: Boot implementer with stripped seed (identity + worktree + result-file contract + reviewer feedback only, ~47 lines vs 502) for small, localized reviewer-driven fixes. Saves tokens and wall-time while preserving implementer's mental model. Requires `--feedback-from-previous-review`; task text becomes optional. See `references/dispatch-reference.md` for usage and decision tree.
- **ISSUE-22: poll-result.sh output modes** — Added output mode flags to reduce token cost during polling:
  - `--full` flag: Restore original behavior (emit entire result file)
  - `--frontmatter-only` flag: Emit only YAML frontmatter (cheapest read)
  - Default mode (no flags): Emit YAML frontmatter + first 30 lines of markdown body + truncation marker if longer
  - Updated SKILL.md with recommendations on when to use each mode
  - Added comprehensive test suite (poll-result.test.sh) covering all three modes
- **ISSUE-20:** Add heuristic for skipping code-quality review on trivial diffs
  - New helper script `scripts/should-skip-code-review.sh` automates the decision
  - New reference doc `references/skip-heuristics.md` describes the heuristic
  - Planner can now safely skip code-reviewer phase for test-only, doc-only, and changelog-only changes ≤30 lines
  - All changes require spec-reviewer approval with no concerns flagged
  - Skipping is optional; planner remains in control
- **Result file size caps (ISSUE-19)**: Enforced size limits in `references/reporting-contract.md` to prevent context bloat:
  - `summary` field: ≤ 200 words
  - `concerns` / issue sections: ≤ 10 bullets, each ≤ 25 words
  - Total result file: ≤ 200 lines (excluding YAML frontmatter)
  - Agents must write verbose detail (test output, traces, diffs) to sibling files (e.g., `.cmux-implementer-verification.txt`) and reference them from the result.
- Updated seed prompts (`implementer-tab-prompt.md`, `spec-reviewer-tab-prompt.md`, `code-reviewer-tab-prompt.md`) to enforce size limits and include self-check step before declaring completion.

### Changed

- **ISSUE-17: Prompt rendering** — Restructured seed prompts for cacheability across multiple tab-agent spawns
- **ISSUE-22: poll-result.sh** — Default output is now summary-only (frontmatter + 30 body lines), reducing planner token cost during routine polling
  - **SKILL.md**: Updated "Polling for results" section with documentation of new output modes
  - **references/reporting-contract.md**: Added examples and recommendations for selective polling modes

### Compliance

All acceptance criteria from ISSUE-17 are met:
- ✅ No `{{...}}` placeholders appear outside the `## Task context` section
- ✅ Rendering two dispatches with different tickets produces byte-identical prefix output
- ✅ All placeholder substitutions happen in the clearly marked tail section
- ✅ Documentation defines the caching contract and editing rules
- ✅ Test suite validates prefix consistency automatically
