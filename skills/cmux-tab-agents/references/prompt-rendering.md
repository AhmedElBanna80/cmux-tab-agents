# Prompt Rendering and Caching Contract

## Overview

Tab-agent seed prompts are structured to enable Anthropic's 5-minute auto-caching of identical prompt prefixes. This reduces token costs when the planner fans out multiple tab-agents in quick succession.

## Structure

Each seed prompt is split into two logical regions:

### Static Prefix (Cacheable)

- Everything up to (but not including) the `## Task context` section heading
- Contains **zero placeholders** — all values are literal text
- Byte-identical across all dispatches, regardless of ticket, title, task, or feedback
- Anthropic's auto-cache recognizes this prefix and reuses it within the 5-minute cache window

### Dynamic Tail (Per-Dispatch)

- The `## Task context` section and everything after it
- Contains **all** placeholder substitutions: `{{TICKET}}`, `{{TITLE}}`, `{{WORKTREE}}`, `{{PLANNER_WORKSPACE}}`, `{{PLANNER_SURFACE}}`, `{{TASK}}`, `{{FEEDBACK}}`, `{{IMPLEMENTER_SHA}}`, `{{SKILL_BASE}}` (as relevant to the phase)
- Changes per dispatch, so this section is not cached (it's new content each time)

## Placeholder Reference

| Placeholder | Purpose | Value | Scope |
|---|---|---|---|
| `{{TICKET}}` | Issue/task ID | e.g., `ISSUE-25` | Tail only |
| `{{TITLE}}` | Issue title | e.g., `Fix discipline path` | Tail only |
| `{{WORKTREE}}` | Consumer repo's worktree path | e.g., `/tmp/worktree-xyz` | Tail only |
| `{{SKILL_BASE}}` | Installed skill directory | e.g., `/home/.claude/plugins/.../skills/cmux-tab-agents` | Prefix or tail (for reading skill files) |
| `{{PLANNER_WORKSPACE}}` | Planner's cmux workspace | e.g., `workspace:UUID` | Tail only |
| `{{PLANNER_SURFACE}}` | Planner's cmux surface | e.g., `surface:UUID` | Tail only |
| `{{TASK}}` | Task specification | Multi-line task text | Tail only |
| `{{FEEDBACK}}` | Code review feedback | Multi-line feedback text | Tail only |
| `{{IMPLEMENTER_SHA}}` | Implementer's final commit | e.g., `abc123def456` | Tail only |

### Important Distinction: {{WORKTREE}} vs {{SKILL_BASE}}

- **{{WORKTREE}}** = path to the consumer repo's working directory (where the implementer works)
- **{{SKILL_BASE}}** = path to the installed skill directory (where tab-agent code and discipline.md live)

These are **different paths** when the skill is used from outside the cmux-tab-agents repo itself. Never reference `{{WORKTREE}}/skills/cmux-tab-agents/...` because that path doesn't exist in consumer repos. Use `{{SKILL_BASE}}/...` to reference skill files.

## Enforcement

The rendering process (in `_dispatch_common.sh`) replaces all `{{KEY}}` placeholders using simple text substitution. This works because:

1. The prefix contains no placeholders, so substitution leaves it unchanged
2. The tail contains all placeholders, so substitution fills in task-specific values
3. The result is a complete, rendered prompt ready for Claude

### Verification

To verify this contract is maintained:

```bash
# Render two prompts with different task contexts but same ticket/title
RENDER1=$(TPL_TICKET=X TPL_TASK="A" ./scripts/_dispatch_common.sh render ...)
RENDER2=$(TPL_TICKET=X TPL_TASK="B" ./scripts/_dispatch_common.sh render ...)

# Extract the prefix (lines up to "## Task context")
PREFIX_LINE=$(grep -n "^## Task context" "$RENDER1" | cut -d: -f1)
head -n $((PREFIX_LINE - 1)) "$RENDER1" > prefix1
head -n $((PREFIX_LINE - 1)) "$RENDER2" > prefix2

# Should be identical
diff prefix1 prefix2 || echo "FAIL: prefixes differ"
```

The test `tests/test-prompt-prefix-caching.sh` validates this automatically.

## Files

Seed prompts are located in `prompts/`:

- `implementer-tab-prompt.md` — Implementer phase instructions
- `spec-reviewer-tab-prompt.md` — Spec compliance review phase instructions
- `code-reviewer-tab-prompt.md` — Code quality review phase instructions

Each file is self-contained and follows the prefix/tail structure.

## Rules for Editing Prompts

When editing seed prompts, follow these rules to preserve cacheability:

1. **No placeholders in the prefix.** If you add `{{...}}` to any section before `## Task context`, you break the cache.
2. **All new placeholders go in the tail.** If you introduce a new variable (e.g., `{{NEW_VAR}}`), add it to the `## Task context` section.
3. **Don't move sections between prefix and tail.** The boundary between static and dynamic is `## Task context`. Discipline sections (TDD, verification, hard rules) live in the prefix; task inputs live in the tail.
4. **Test your changes.** Run `bash tests/test-prompt-prefix-caching.sh` before committing.

## Why This Matters

- **Cost savings:** Without this structure, each dispatch with different task text would be treated as a new prompt by Anthropic's cache, incurring full prompt token cost × N for N dispatches.
- **With caching:** The static prefix (containing most of the text) is cached once, and only the small tail section is billed for each subsequent dispatch within the cache window. For a 500KB prefix and 20 dispatches, this is (500KB + tail × 20) instead of (500KB + tail) × 20.
- **No behavioral change:** End-users and tab-agents see no difference; the caching is transparent. This is a cost optimization, not a feature change.

## References

- Anthropic API documentation on prompt caching: https://docs.anthropic.com/docs/build-a-system-with-long-context#caching-tokens
- `_dispatch_common.sh`: The render_template function performs placeholder substitution.
