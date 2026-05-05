# Reporting contract

This is the wire format between tab-agents and the planner. It is the single source of truth for what each phase reports.

## File locations

For a given worktree `$WT`:

| Phase           | File                                  |
|-----------------|---------------------------------------|
| implementer     | `$WT/.cmux-implementer-result.md`     |
| spec-reviewer   | `$WT/.cmux-spec-reviewer-result.md`   |
| code-reviewer   | `$WT/.cmux-code-reviewer-result.md`   |

Files use YAML frontmatter + markdown body. They must contain a `status:` field in the frontmatter — `poll-result.sh` validates that and refuses to return malformed output.

## Schemas

### Implementer result

```yaml
---
ticket: ALPM-1234-1
phase: implementer
status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
branch: feat/ALPM-1234-1/form-validation
last_commit: abc1234...
---
## Summary
<2-3 sentences>

## Tests
<commands run, exit codes, counts>

## Files changed
<git diff --name-only output>

## Self-review findings
<bullet list, or "none">

## Concerns / blockers / context needed
<bullet list, or "none">
```

## Size limits

Result files must respect these limits to avoid inflating downstream contexts (next phase's seed, planner's context).

### Per-field limits

- **`summary`**: ≤ 200 words. Concise 2–3 sentence recap of what was done or attempted.
- **`concerns` / `issues` / other structured fields**: ≤ 10 bullets per section. Each bullet ≤ 25 words.

### File-level limits

- **Total length**: ≤ 200 lines (excluding YAML frontmatter).
- **Verbose detail** (e.g., test output, stack traces, long diffs, lengthy logs): write to a sibling file (e.g., `.cmux-implementer-verification.txt`, `.cmux-spec-reviewer-details.txt`, `.cmux-code-reviewer-issues.txt`) and **reference** it from the result file, do NOT inline.

### Example

Instead of inlining 500 lines of test output in `## Tests`:

```markdown
## Tests
Ran: `npm test`; 47/47 pass. (Full output: `.cmux-implementer-verification.txt`)
```

Or for a concern:

```markdown
## Concerns / blockers / context needed
- File `src/core/handlers.ts` grew to 1200 lines; consider splitting. (Details: `.cmux-implementer-details.txt`)
```

### Contract violation?

If a result file exceeds these limits, the next phase or planner can reject it as `ISSUES_FOUND`-grade, and the implementer / reviewer will need to edit and re-submit.

---

Status semantics (lifted from `superpowers:subagent-driven-development`):

- `DONE` — work complete, all checks pass, no concerns.
- `DONE_WITH_CONCERNS` — work complete and tests pass, but the implementer flagged doubts (scope creep, file size, mock complexity, etc.). Planner reads concerns before review.
- `NEEDS_CONTEXT` — implementer cannot proceed without missing information. Planner re-dispatches with more context.
- `BLOCKED` — implementer cannot complete. Planner decides: more context (re-dispatch), more capable model (re-dispatch with override), smaller scope (split task), or escalate to user.

### Spec-reviewer result

```yaml
---
ticket: ALPM-1234-1
phase: spec-reviewer
status: APPROVED | ISSUES_FOUND
implementer_sha: abc1234...
---
## Verdict
<one line>

## What was requested
## What was built
## Missing requirements
## Extra / unneeded work
## Misunderstandings
## Hook-bypass check
## Verification commands re-run
```

### Code-reviewer result

```yaml
---
ticket: ALPM-1234-1
phase: code-reviewer
status: APPROVED | ISSUES_FOUND
implementer_sha: abc1234...
spec_reviewer_status: APPROVED
---
## Verdict
## Strengths
## Issues — Critical
## Issues — Important
## Issues — Minor
## TDD assessment
## Hook-bypass check
## Verification commands re-run
## Overall assessment
```

## Verification artifact

The implementer writes an optional verification artifact file alongside its result file to help reviewers reduce re-verification work.

### File location and schema

For a given worktree `$WT`:

```
$WT/.cmux-implementer-verification.json
```

Schema:

```json
{
  "implementer_sha": "abc123def456...",
  "timestamp": "2026-05-05T12:34:56Z",
  "tests": {
    "framework": "jest",
    "passed": 42,
    "failed": 0,
    "command": "npm test",
    "status": "passed"
  },
  "hooks": {
    "status": "passed",
    "skipped": false,
    "evidence": "pre-commit hook output hash or summary"
  },
  "lint": {
    "command": "npm run lint",
    "status": "passed"
  },
  "build": {
    "command": "npm run build",
    "status": "passed"
  }
}
```

**Honest reporting required:** If a verification step was skipped or failed, the artifact must reflect that. Possible status values:

- `passed` — verification step succeeded
- `failed` — verification step failed (tests did not pass, lint found issues, etc.)
- `skipped` — verification step was not run

### How reviewers use it

When the implementer's verification artifact is present:

1. Check that `implementer_sha` matches the current HEAD commit.
2. Check that `timestamp` is recent (within the last hour; adjust threshold per project policy).
3. Check that all status fields are `passed` (not `failed` or `skipped`).

If all three checks pass, the reviewer **may** downgrade re-verification to spot-checks:
- Run a subset of the test suite (e.g., tests for changed files only, not full suite).
- Confirm the hook output artifact makes sense (hash/summary check, no truncation).
- Spot-check lint output (skim for false positives, don't exhaustively re-run).

If the artifact is missing, stale (timestamp > 1 hour), has a mismatched sha, or has any `failed`/`skipped` status:
- Perform full re-verification: run all tests, lint, build, and hooks independently.
- Flag the artifact state as a concern in your result file if it signals incomplete or stale information.

## Push line format (terminal states only)

When a tab-agent reaches a terminal state (implementer: `DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT`; reviewers: `APPROVED` / `ISSUES_FOUND`), it pushes two lines to the planner's input box:

```
[<TICKET>-<phase>] <STATUS>: <one-line summary>. Result: <worktree>/.cmux-<phase>-result.md
focus: cmux rpc surface.focus '{"surface_id":"surface:<N>"}'
```

Example:
```
[ALPM-1234-1-implementer] DONE: wired up zod validation; 12 tests pass. Result: /Users/.../.cmux-implementer-result.md
focus: cmux rpc surface.focus '{"surface_id":"surface:51"}'
```

The focus line is a copy-pastable shell command that jumps to the tab-agent's surface. It is always included (though the agent gracefully skips it if surface detection fails).

## Polling pattern

The planner uses `poll-result.sh` to wait on a phase's result file:

```bash
poll-result.sh \
  --worktree "$WT" \
  --phase implementer \
  --timeout 1800 \
  --interval 5
```

Exit codes:
- `0` — file appeared and is well-formed. Contents printed to stdout.
- `1` — timeout reached.
- `2` — file appeared but malformed (no `status:` field).

**Output modes** (default vs. compact):

- **Default** (no flags): Emits YAML frontmatter + first 30 lines of markdown body + truncation marker if body is longer. Reduces token cost during routine polling.
- `--full`: Emits the entire file. Use when you need the full body (status is `ISSUES_FOUND`, `BLOCKED`, `DONE_WITH_CONCERNS` with important concerns, etc.).
- `--frontmatter-only`: Emits only the YAML frontmatter (no body). Cheapest read for status-only checks.

The planner parses the YAML frontmatter to decide the next action. A simple bash one-liner:

```bash
RESULT=$(poll-result.sh --worktree "$WT" --phase implementer --timeout 1800)
STATUS=$(awk -F': *' '/^status:/ {print $2; exit}' <<< "$RESULT")
case "$STATUS" in
  DONE)               echo "→ proceed to spec review" ;;
  DONE_WITH_CONCERNS) echo "→ read concerns, decide whether to proceed" ;;
  NEEDS_CONTEXT)      echo "→ provide context, re-dispatch implementer" ;;
  BLOCKED)            echo "→ assess blocker, escalate or re-dispatch" ;;
  *)                  echo "→ unknown status, escalate" ;;
esac
```

If the default truncation mode hides concerns you need, poll again with `--full`:

```bash
# First poll with default output
RESULT=$(poll-result.sh --worktree "$WT" --phase implementer)
STATUS=$(awk -F': *' '/^status:/ {print $2; exit}' <<< "$RESULT")

# If you need the full body, fetch it
if [[ "$STATUS" == "ISSUES_FOUND" ]] || [[ "$STATUS" == "BLOCKED" ]]; then
  FULL=$(poll-result.sh --worktree "$WT" --phase implementer --full)
fi
```

## Slurping all in-flight results

If you want to scan every worktree's last-known state across the fleet:

```bash
WT_BASE="${CMUX_TAB_AGENTS_WORKTREE_BASE:-$(dirname "$REPO")/worktrees/$REPO_NAME}"
for f in "$WT_BASE"/*/*/. cmux-*-result.md; do
  [ -f "$f" ] || continue
  echo "=== $f ==="
  awk '/^---$/{c++; next} c==1 {print}' "$f"  # print frontmatter only
done
```

## Why a result file (not a return value)?

Upstream `superpowers:subagent-driven-development` returns a text blob from `Agent({...})`. cmux-tab-agents uses real `claude` processes that have no in-process return mechanism. The result file is the equivalent — except:
- It survives the tab being closed, killed, or restarted.
- The user can read it directly with `cat`.
- The planner can poll it asynchronously instead of blocking.
- Grep across worktrees gives a fleet-wide status snapshot.

Trade-off: there's no mechanism that *guarantees* the file gets written if the tab-agent crashes mid-task. Mitigation: the seed prompt instructs the tab-agent to write the file as the final step before idling; if it crashes earlier, the planner sees the timeout in `poll-result.sh` and treats it as a soft `BLOCKED`.
