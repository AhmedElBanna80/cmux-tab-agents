# Skip code-quality review on trivial diffs

## Overview

The per-task pipeline always runs three phases: implementer → spec-reviewer → code-reviewer. For trivial changes (small test-only diffs, doc/typo fixes, single-line config tweaks), the code-quality review adds wall-time and tokens with near-zero signal.

This document describes a conservative heuristic for **optionally** skipping the code-quality review phase after spec-reviewer approves. The planner MAY apply this heuristic; it is never mandatory.

## The heuristic

Code-quality review MAY be skipped if **ALL THREE** of the following hold:

1. **Diff is small:** `git diff --shortstat <implementer-sha>~1..<implementer-sha>` shows ≤ 30 total changed lines (insertions + deletions combined).

2. **Files are trivial:** All files changed are **one or more** of:
   - Test/spec files: names containing `test` or `spec` (e.g., `app.test.js`, `user.spec.ts`, `test/utils.js`)
   - Markdown/docs: files ending in `.md` (e.g., `docs/guide.md`, `README.md`)
   - Changelog: files named `CHANGELOG`, `CHANGELOG.md`, `HISTORY.md`, etc. (name contains `CHANGELOG`)

3. **Spec-reviewer approved cleanly:** The spec-reviewer result file (`.cmux-spec-reviewer-result.md`) has:
   - `status: APPROVED` in the frontmatter
   - No flagged concerns, missing requirements, issues, or caveats in the body

## When the heuristic applies

**Examples where skipping is safe:**

- A PR adds 5 lines to `app.test.js` testing a new function. ✓ Skip.
- A PR fixes a typo in `README.md` (2 lines). ✓ Skip.
- A PR updates the changelog with today's release notes (10 lines). ✓ Skip.
- A PR adds a test case to `tests/handlers.spec.ts` (12 lines). ✓ Skip.

**Examples where skipping is NOT safe:**

- A PR changes `src/app.js` (25 lines) and `src/utils.js` (8 lines = 33 total). ✗ Exceeds 30-line limit.
- A PR is approved by spec-reviewer but includes "should add more validation" in the verdict. ✗ Has concerns.
- A PR changes `src/config.yml` (non-test, non-doc file). ✗ Not a trivial file.
- A PR changes `package.json` (10 lines). ✗ Not a test/spec/markdown file.

## Using the helper script

A planner can automate this decision using the provided helper:

```bash
~/.claude/skills/cmux-tab-agents/scripts/should-skip-code-review.sh \
  --worktree "$WORKTREE" \
  --implementer-sha "$(git -C $WORKTREE rev-parse HEAD)"
```

**Exit codes:**
- `0` — safe to skip code-quality review
- `1` — code-quality review required

**Stderr** contains a one-line reason (e.g., "diff too large: 35 changed lines (max 30)").

The script is deterministic — no LLM judgment, just git diff + pattern matching. Use it to make the skip decision objective and repeatable.

## Why this heuristic is conservative

The heuristic is biased toward **running** code-quality review, not skipping it:

- Size threshold (30 lines) is small. Multi-file changes are rare under this limit.
- File pattern whitelist is narrow: test, spec, markdown, changelog only. Config, source, type definitions, migrations, and build files all require review.
- Spec-reviewer concerns are detected conservatively: the helper greps for common concern words ("missing", "issue", "should", "but", etc.) to catch flagged problems.
- When in doubt (e.g., file name doesn't clearly match a pattern, result file is missing), the script recommends **not** skipping.

This prevents false negatives: it is always safer to run an extra review than to skip one and miss a bug.

## Planner integration

After spec-reviewer reports `APPROVED`:

```bash
IMPL_SHA=$(git -C "$WORKTREE" rev-parse HEAD)

if ~/.claude/skills/cmux-tab-agents/scripts/should-skip-code-review.sh \
   --worktree "$WORKTREE" --implementer-sha "$IMPL_SHA"; then
  echo "→ Trivial diff approved by spec-reviewer: skip code-quality review"
  # Mark sub-task done without dispatching code-reviewer tab
else
  echo "→ Dispatch code-reviewer tab (non-trivial or spec concerns)"
  # Continue with dispatch-code-reviewer.sh as usual
fi
```

The planner remains in control: the heuristic is advisory, not mandatory. Even when the helper returns 0 (safe to skip), the planner can always choose to run code-quality review anyway.

## Notes

- The helper is idempotent and fast (under 100ms). Call it as many times as needed.
- The spec-reviewer result file must exist and be well-formed. If the file is missing or malformed, the helper recommends not skipping.
- If either `git diff` or file checks fail unexpectedly, the helper recommends not skipping.
- The heuristic applies only to skipping the code-reviewer phase. The spec-reviewer phase is always required (it is the correctness gate).
