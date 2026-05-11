# ISSUE-93 Phase 3 — Agent-to-agent stream coordination

## What changed

The progress stream (`.cmux-progress.jsonl`) used to be a one-way feed: agents append step
events, the planner reads them. Phase 3 turns it into a **shared event bus** that peers can
also act on, without going through the planner.

Two artifacts were added to support this:

1. **`scripts/progress.sh` v2 schema** — four new flags (`--target`, `--verdict`,
   `--feedback`, `--issue-hash`) extend each line with agent-coordination fields. Lines
   with any of these flags emit `v: 2`; lines without them remain `v: 1` and byte-identical
   to the Phase 1/2 format.
2. **`scripts/stream-watcher.sh`** — sourced into a prompt to spawn a background tail of
   the progress file. It filters events by the `target` field and invokes a caller-supplied
   handler function for matches.

## v2 event shape

```json
{
  "v": 2,
  "ts": "2026-05-11T17:08:37Z",
  "src": "spec",
  "sid": "...",
  "kind": "verdict",
  "name": "spec-review",
  "agent_role": "spec-reviewer",
  "target": "implementer",
  "verdict": "ISSUES_FOUND",
  "feedback": "Line 42 missing null check",
  "issue_hash": "ab12cd34",
  "payload": { "step": "2", "agent_role": "spec-reviewer", "target": "implementer", "verdict": "ISSUES_FOUND", "feedback": "...", "issue_hash": "..." }
}
```

Field reference:

| Field        | Type   | Purpose                                                                 |
|--------------|--------|-------------------------------------------------------------------------|
| `target`     | string | Comma-separated role list this event is addressed to                    |
| `verdict`    | string | Reviewer outcome: `APPROVED` / `ISSUES_FOUND` / `BLOCKED` / etc.        |
| `feedback`   | string | Short prose attached to the event                                       |
| `issue_hash` | string | Stable hash of the issue body — used by circuit-breaker dedup           |

`verdict`, `feedback`, and `issue_hash` are omitted when empty.

## Coordination flow

```
implementer  ────► dispatch-spec-reviewer.sh
                    └─► spec-reviewer
                        └─► v2 event {target:implementer, verdict:ISSUES_FOUND, issue_hash:X}
implementer  ◄────  stream-watcher fires handle_implementer_event(event)
   │
   ├─► fixes code, commits
   └─► v2 event {target:spec-reviewer, feedback:"ready for re-review"}
                        ┌─► stream-watcher fires handle_spec_event(event)
spec-reviewer ◄────────┘
   └─► re-runs checks, emits next verdict
```

The same shape extends to code-reviewer. The planner is still notified (it tails the
same file) but no longer needs to drive each verdict round-trip.

## Backward compatibility

- All Phase 1/2 callers continue to emit v1 events (no v2 flags = no schema bump).
- Stream-watcher's `_should_handle_event` returns 1 for events without a `target`, so
  v1 broadcasts are simply ignored by peer watchers — only the planner's status poll
  needs to read them.
- v1-format tests (`test_progress.sh`) are unchanged and still pass.

## Circuit-breaker

`issue_hash` lets a watcher detect that the same complaint is being re-raised:

```bash
# Inside a handler
seen=$(grep -c "\"issue_hash\":\"$h\"" .cmux-progress.jsonl)
if [[ $seen -ge 2 ]]; then
  bash "$SKILL_BASE/scripts/progress.sh" \
    --role spec-reviewer --target implementer,planner \
    --verdict BLOCKED --feedback "same issue twice" \
    verdict 2 spec-review
  exit 1
fi
```

This implements the "same reviewer flags the same issue in two consecutive rounds = BLOCKED"
rule already documented in `discipline.md` without requiring the planner to track state.

## Prompts updated

| Prompt                          | What was added                                                                        |
|--------------------------------|---------------------------------------------------------------------------------------|
| `implementer-tab-prompt.md`    | `## Stream coordination (Phase 3)` section — watcher hook + how to emit feedback     |
| `spec-reviewer-tab-prompt.md`  | `## Stream coordination (Phase 3)` section — verdict emit + re-review handler        |
| `code-reviewer-tab-prompt.md`  | `## Stream coordination (Phase 3)` section — same shape as spec-reviewer             |

Each section is **additive**: the existing task-lead pipeline (result files,
`finish-task.sh`, etc.) still works unchanged. v2 events are an optional fast path, not a
replacement.

## Tests

| File                                          | Coverage                                                              |
|-----------------------------------------------|-----------------------------------------------------------------------|
| `scripts/tests/test_progress.sh`              | v1 schema (unchanged) — 34 tests                                      |
| `scripts/tests/test_progress_v2.sh`           | v2 flags, schema bump, comma-separated targets, malformed-flag safety |
| `scripts/tests/test_stream_watcher.sh`        | Event routing, v1 ignore, end-to-end watcher fire                     |
| `scripts/tests/test_agent_reactions.sh`       | ISSUES_FOUND → re-review → APPROVED round trip, circuit-breaker        |

Run all four via `make test` or individually.

## Open questions deferred

- **Polling timeout / liveness.** Phase 3 keeps the existing dispatch script as the
  liveness contract; if a watcher never sees a verdict, the task-lead pipeline's
  result-file poll still drives recovery.
- **Persistent stream history.** `.cmux-progress.jsonl` is wiped with the worktree by the
  cleanup hook; no separate audit retention has been added.

## Files at a glance

```
skills/cmux-tab-agents/
├── scripts/
│   ├── progress.sh                       (modified — v2 schema)
│   ├── stream-watcher.sh                 (added)
│   └── tests/
│       ├── test_progress.sh              (unchanged)
│       ├── test_progress_v2.sh           (added)
│       ├── test_stream_watcher.sh        (added)
│       └── test_agent_reactions.sh       (added)
├── prompts/
│   ├── implementer-tab-prompt.md         (modified — Phase 3 section)
│   ├── spec-reviewer-tab-prompt.md       (modified — Phase 3 section)
│   └── code-reviewer-tab-prompt.md       (modified — Phase 3 section)
└── references/
    └── ISSUE-93-phase-3.md               (this file)
```
