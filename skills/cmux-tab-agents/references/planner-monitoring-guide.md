# Planner monitoring guide

How a cmux-tab-agents **planner** watches a dispatched task progress to completion
using the shared progress stream.

## TL;DR

```bash
bash scripts/monitor-worktree-progress.sh <WORKTREE>
```

Tails `<WORKTREE>/.cmux-progress.jsonl`, prints one line per phase `done` event,
exits when the **code-reviewer** phase completes.

From inside a Claude planner session:

```text
Monitor(
  command="bash /Users/banna/POC/cmux-tab-agents/skills/cmux-tab-agents/scripts/monitor-worktree-progress.sh /path/to/worktree",
  until="phase=code-reviewer"
)
```

When the `Monitor` call returns, the task pipeline (implementer → spec-reviewer →
code-reviewer) is complete and the planner can read `.cmux-task-result.md`.

## The shared stream concept

Every tab-agent (implementer, spec-reviewer, code-reviewer) in a given task writes
to **one** file: `<WORKTREE>/.cmux-progress.jsonl`. Each emit appends one JSONL
line with shape (see `progress.sh`):

```json
{"v":1,"ts":"...","src":"implementer","sid":"...","kind":"done","name":"boot","agent_role":"implementer","payload":{"step":"1","agent_role":"implementer"}}
```

Key fields:

- `kind` — `started` | `done` | `terminal`
- `agent_role` — `implementer` | `spec-reviewer` | `code-reviewer`
- `name` — the step name (`boot`, `spec-dispatch`, `review-began`, `finish`, …)

Because all three agents write to the same file, the planner only needs **one**
tail to observe the entire pipeline. There is no need to spawn a separate Monitor
per agent.

## The pattern: tail -f | filter | act

`monitor-worktree-progress.sh` implements it:

1. `touch` the progress file (so `tail -f` attaches cleanly even before any agent
   has emitted).
2. `tail -f` the file, line by line.
3. For each line, parse `kind`. Skip everything that is not `done`.
4. For each `done`, print one human-readable line:
   `[HH:MM:SS] phase=<role> step=<step> name=<name>`
5. When `agent_role` is `code-reviewer` (or `src` is `code`), exit `0`.

Each printed line is a `Monitor` trigger surface — the planner can wait for any
specific phase by matching on the regex:

| Wait for                      | Monitor `until` pattern    |
|-------------------------------|----------------------------|
| Implementer boot/finish done  | `phase=implementer`        |
| Spec review done              | `phase=spec-reviewer`      |
| Code review done (terminal)   | `phase=code-reviewer`      |
| Any phase done                | `phase=`                   |

## Example Monitor command

A planner waiting for a freshly dispatched task:

```text
Monitor(
  command="bash /Users/banna/POC/cmux-tab-agents/skills/cmux-tab-agents/scripts/monitor-worktree-progress.sh /Users/banna/POC/worktrees/cmux-tab-agents/MONITORING-116/cmux-tab-agents",
  until="phase=code-reviewer",
  timeout=3600
)
```

When this returns, both reviewers have approved (or BLOCKED) — read
`.cmux-task-result.md` for the verdict and the implementer's notes.

For finer-grained checkpoints (e.g. "alert me when spec review fires"), run
multiple cheap `Monitor` calls back-to-back with different `until` regexes — the
script keeps running and emits each phase line in order.

## Comparison to the old multi-monitor approach

| Approach            | Tails | Files watched      | Coordination |
|---------------------|-------|--------------------|--------------|
| Old: per-agent poll | 3     | 3 result files     | Planner polls each `.cmux-*-result.md` separately |
| New: shared stream  | 1     | 1 JSONL stream     | Single tail, single Monitor, single source of truth |

The shared-stream approach is preferred because:

1. **One source of truth.** All phase transitions are in one append-only file.
2. **Order is preserved.** JSONL appends are atomic on POSIX local FS, so the
   planner sees events in the order agents emitted them.
3. **Cheaper to monitor.** One file watcher instead of three poll loops.
4. **Forward-compatible.** New phases (e.g. a future `lint-reviewer`) just emit
   their own `done` events; the planner pattern doesn't change.

## Troubleshooting

- **Monitor never sees `phase=code-reviewer`** — confirm the code-reviewer
  actually ran. Inspect `<WORKTREE>/.cmux-progress.jsonl` directly:
  `tail -20 <WORKTREE>/.cmux-progress.jsonl | jq .`
- **Stale `.cmux-monitor.pid`** — left behind if the monitor was SIGKILL'd. Safe
  to delete; it is only used to clean up the inner `tail -f`.
- **Worktree was deleted mid-task** — the script exits with code 1. Re-create the
  worktree (the implementer prompt has logic for this) and re-invoke the monitor.

## See also

- `scripts/progress.sh` — the emitter side, with `--role` flag for reviewers.
- `scripts/demo-monitor-progress.sh` — inline cheat-sheet for raw `tail -f` +
  Monitor predicates without using `monitor-worktree-progress.sh`.
- `SKILL.md` — "Progress event stream" section, schema definition.
