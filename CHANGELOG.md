# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **ISSUE-17: Cache-friendly seed prompt rendering** — Restructured all tab-agent seed prompts (implementer, spec-reviewer, code-reviewer) to separate static prefix from dynamic task context tail. The static prefix (containing ~95% of the prompt text) is now byte-identical across dispatches, enabling Anthropic's 5-minute auto-cache to reuse it across multiple tab-agent spawns. This reduces token costs by caching the stable prefix once and only paying for the small task-specific tail per dispatch.
  - `references/prompt-rendering.md` — Documents the prompt caching contract, explaining the prefix/tail structure and rules for maintaining cacheability when editing prompts.
  - `tests/test-prompt-prefix-caching.sh` — Automated test suite verifying that:
    - Prompt prefixes are byte-identical across dispatches with different task text
    - No placeholders appear in the cacheable prefix region
    - All placeholders are confined to the tail section
- **ISSUE-22: poll-result.sh output modes** — Added output mode flags to reduce token cost during polling:
  - `--full` flag: Restore original behavior (emit entire result file)
  - `--frontmatter-only` flag: Emit only YAML frontmatter (cheapest read)
  - Default mode (no flags): Emit YAML frontmatter + first 30 lines of markdown body + truncation marker if longer
  - Updated SKILL.md with recommendations on when to use each mode
  - Added comprehensive test suite (poll-result.test.sh) covering all three modes

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
