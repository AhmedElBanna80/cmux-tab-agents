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

### Details
- Created `references/discipline.md` with verbatim discipline language from:
  - `superpowers:test-driven-development @ 5.0.7`
  - `superpowers:verification-before-completion @ 5.0.7`
  - `superpowers:subagent-driven-development` (custom hook-bypass prohibition)
- Refactored all three seed prompts to replace inline discipline sections with pointers to the reference
- No discipline rules were lost in migration; all stable content is preserved verbatim
- Dispatch rendering verified to correctly substitute `{{WORKTREE}}` placeholder for discipline file path
