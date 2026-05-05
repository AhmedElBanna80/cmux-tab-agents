# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- **ISSUE-17: Cache-friendly seed prompt rendering** — Restructured all tab-agent seed prompts (implementer, spec-reviewer, code-reviewer) to separate static prefix from dynamic task context tail. The static prefix (containing ~95% of the prompt text) is now byte-identical across dispatches, enabling Anthropic's 5-minute auto-cache to reuse it across multiple tab-agent spawns. This reduces token costs by caching the stable prefix once and only paying for the small task-specific tail per dispatch.

### Added

- `references/prompt-rendering.md` — Documents the prompt caching contract, explaining the prefix/tail structure and rules for maintaining cacheability when editing prompts.
- `tests/test-prompt-prefix-caching.sh` — Automated test suite verifying that:
  - Prompt prefixes are byte-identical across dispatches with different task text
  - No placeholders appear in the cacheable prefix region
  - All placeholders are confined to the tail section

### Compliance

All acceptance criteria from ISSUE-17 are met:
- ✅ No `{{...}}` placeholders appear outside the `## Task context` section
- ✅ Rendering two dispatches with different tickets produces byte-identical prefix output
- ✅ All placeholder substitutions happen in the clearly marked tail section
- ✅ Documentation defines the caching contract and editing rules
- ✅ Test suite validates prefix consistency automatically
