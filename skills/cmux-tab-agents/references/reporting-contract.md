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
