---
name: cmux-tab-agents
description: Use whenever you would call `superpowers:subagent-driven-development` AND the session is running inside cmux. Forks that skill — same three-agent per-task pipeline (implementer → spec-reviewer → code-quality-reviewer) and same four-status reporting (DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED) — but dispatches each subagent as a real `claude` process in a cmux tab inside a dedicated git worktree per ticket. Triggers on phrasing like "execute this plan with cmux tab agents", "dispatch tab agents", "spawn an implementer in a tab", "fork subagent-driven-development for cmux", or any moment the planner is about to break a story into sub-tasks while inside cmux. Never edits code from the planner tab — only plans, files tickets, dispatches tab-agents, and reviews their result files. Enables cross-task parallelism (one worktree per task removes the conflict surface upstream worried about) and bakes in TDD discipline plus a hard prohibition on `--no-verify` and other hook-bypass shortcuts.
---

# cmux-tab-agents

A **fork of `superpowers:subagent-driven-development`** for cmux. Same workflow, same review gates, same status reporting — but each subagent is a real `claude --dangerously-skip-permissions` process running in its own cmux tab inside its own git worktree.

## When to use this skill

Use this skill instead of upstream `superpowers:subagent-driven-development` when **all** of:

- You are running inside cmux (`echo "$CMUX_SURFACE_ID"` returns a non-empty value).
- You have a parent story / bug / epic and are about to break it into sub-tasks.
- You want each sub-task isolated in its own worktree so the implementers can run in parallel.
- You want the work observable — visible cmux tabs, sidebar status pills, notifications.

If `$CMUX_SURFACE_ID` is empty, fall back to upstream `superpowers:subagent-driven-development`. The two skills have identical semantics, so the fallback path is safe.

## What "the planner" means in this skill

You are the planner. Your job is to:

1. Read the plan (or the user's intent) and extract atomic sub-tasks.
2. For each sub-task, create a Jira sub-task (or any other tracker — the skill only needs a string ID like `ALPM-1234-1`) with `parentIssueKey` pointing at the parent story.
3. For each sub-task, dispatch an implementer tab via `dispatch-implementer.sh`.
4. Poll each implementer's result file. Decide based on its status (DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED) what to do next.
5. After implementer reports DONE, dispatch a spec-reviewer tab. Loop reviews with the implementer if issues are found.
6. After spec-reviewer reports APPROVED, dispatch a code-quality-reviewer tab. Loop with the implementer if issues are found.
7. Mark the sub-task done. Move to the next.
8. When all sub-tasks are done, hand off to `superpowers:finishing-a-development-branch` (which you run yourself, not in a tab).

**You never edit code yourself.** If you catch yourself writing files in the project, stop and dispatch instead.

## Why subagents (verbatim from upstream)

> You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed at their task. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.
>
> **Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration.

## The per-task pipeline

```
For each sub-task (parallelizable across tasks):
  └── ensure-worktree.sh  →  worktree at <discovered base>/<TICKET>/<repo-name>
       on branch <type>/<TICKET>/<slug>  (default type: feat)
        │
        ├── dispatch-implementer.sh      → cmux tab #1, runs claude with implementer-tab-prompt seed
        │     │  TDD red-green-refactor, never --no-verify
        │     │  writes .cmux-implementer-result.md, idles
        │     ↓
        │   Planner polls .cmux-implementer-result.md
        │     DONE                → continue
        │     DONE_WITH_CONCERNS  → read concerns, decide
        │     NEEDS_CONTEXT       → re-dispatch implementer with --feedback-from-previous-review
        │     BLOCKED             → escalate
        │
        ├── dispatch-spec-reviewer.sh    → cmux tab #2, same worktree, spec-reviewer-tab-prompt seed
        │     │  reads code (NOT trusting implementer's report), re-runs verification
        │     │  writes .cmux-spec-reviewer-result.md, idles
        │     ↓
        │   Planner polls .cmux-spec-reviewer-result.md
        │     APPROVED      → continue
        │     ISSUES_FOUND  → re-dispatch implementer with --feedback-from-previous-review,
        │                     loop back to spec review
        │
        └── dispatch-code-reviewer.sh    → cmux tab #3, same worktree, code-reviewer-tab-prompt seed
              │  reviews code quality, TDD discipline, hooks; re-runs verification
              │  writes .cmux-code-reviewer-result.md, idles
              ↓
            Planner polls .cmux-code-reviewer-result.md
              APPROVED      → mark sub-task done, move to next
              ISSUES_FOUND  → re-dispatch implementer with --feedback-from-previous-review,
                              loop back through spec review then code review
```

Three sequential tabs in the same worktree. Only one runs at a time (implementer first; reviewers run on the implementer's committed state). Tabs from prior phases stay open for inspection.

## Cross-task parallelism (override of upstream rule)

> **Override of upstream rule.** Upstream `superpowers:subagent-driven-development` forbids dispatching multiple implementers in parallel because they share a working tree. cmux-tab-agents puts each task in its own git worktree, eliminating the conflict surface. The planner MAY dispatch implementers for distinct sub-tasks in parallel.
> The planner MUST NOT dispatch multiple implementers into the **same** worktree.

Practical pattern: for a story with 3 independent sub-tasks, fire all 3 implementer tabs in parallel, then poll their result files concurrently. Each implementer commits to its own branch in its own worktree. Reviewers per task still run sequentially (review depends on implementer being done).

## Status handling (verbatim from upstream)

Implementer tab-agents report one of four statuses in their result file. Handle each:

- **`DONE`** — Proceed to spec compliance review.
- **`DONE_WITH_CONCERNS`** — The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.
- **`NEEDS_CONTEXT`** — The implementer needs information that wasn't provided. Provide the missing context and re-dispatch.
- **`BLOCKED`** — The implementer cannot complete the task. Assess the blocker:
  1. If it's a context problem, provide more context and re-dispatch with the same model.
  2. If the task requires more reasoning, re-dispatch with a more capable model.
  3. If the task is too large, break it into smaller pieces.
  4. If the plan itself is wrong, escalate to the human.

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

## Dispatch commands

All scripts live at `~/.claude/skills/cmux-tab-agents/scripts/`. They must be run from inside cmux (so they can read `$CMUX_PANEL_ID` and `$CMUX_WORKSPACE_ID`).

### Dispatch an implementer

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-implementer.sh \
  --ticket ALPM-1234-1 \
  --title "wire up form validation" \
  --slug form-validation \
  --task-text "Add zod validation to the onboarding form. Files: apps/.../form.tsx. Acceptance: invalid email blocks submit + shows inline error."
```

Or read the task from a file:

```bash
... --task-file ./tasks/ALPM-1234-1.md
```

For re-dispatch after review feedback, pass the previous review's findings:

```bash
... --feedback-from-previous-review "$(cat $WT/.cmux-spec-reviewer-result.md)"
```

The script:
1. Provisions the worktree (idempotent — resumes if it exists).
2. Renders the seed prompt.
3. Opens a new cmux tab in your pane.
4. Sets a `<TICKET>-implementer` `dispatched` pill on your workspace.
5. Echoes the new tab's `surface:N` ref on stdout.

### Dispatch a spec-reviewer

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-spec-reviewer.sh \
  --ticket ALPM-1234-1 \
  --title "wire up form validation" \
  --slug form-validation \
  --task-text "$(cat tasks/ALPM-1234-1.md)" \
  --implementer-sha "$(git -C $WT rev-parse HEAD)"
```

### Dispatch a code-quality-reviewer

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-code-reviewer.sh \
  --ticket ALPM-1234-1 \
  --title "wire up form validation" \
  --slug form-validation \
  --task-text "$(cat tasks/ALPM-1234-1.md)" \
  --implementer-sha "$(git -C $WT rev-parse HEAD)"
```

## Polling for results

```bash
~/.claude/skills/cmux-tab-agents/scripts/poll-result.sh \
  --worktree "$WT" \
  --phase implementer \
  --timeout 1800
```

Phases: `implementer | spec-reviewer | code-reviewer`. Returns the result file's contents on stdout, exits 1 on timeout, exit 2 on a malformed file.

Parse the `status:` field to drive next action. See `references/reporting-contract.md` for the full schema.

## Red flags

Forked from upstream `superpowers:subagent-driven-development`, with two additions specific to this fork.

**Never:**
- Start implementation on `main` / `master` without explicit user consent.
- Skip reviews (spec compliance OR code quality).
- Proceed with unfixed issues.
- Make a tab-agent read the plan file (provide full text via `--task-text` or `--task-file` instead).
- Skip scene-setting context (the tab-agent needs to understand where the task fits).
- Ignore tab-agent questions — answer before letting them proceed.
- Accept "close enough" on spec compliance (spec reviewer found issues = not done).
- Skip review loops (reviewer found issues = implementer fixes = review again).
- Let a tab-agent self-review replace actual review (both are needed).
- **Start code quality review before spec compliance is APPROVED** (wrong order).
- Move to the next sub-task while either review has open issues.

**NEW vs upstream:**
- **Reject any tab-agent result file that mentions `--no-verify`, `HUSKY=0`, hook-skipping, or any other bypass technique.** Re-dispatch the implementer with explicit "fix the hook, do not bypass it" instructions.
- **Two implementers in the same worktree at the same time** → stop, audit, kill the duplicate. One implementer per worktree.

## Edge cases

### Worktree path exists but is not a git worktree

`ensure-worktree.sh` exits 1 with a clear message. The skill refuses to clobber unknown content. Action: investigate manually (the directory may be from a previous attempt or unrelated work). Remove or rename, then retry.

### `--dangerously-skip-permissions` is real but bounded

Tab-agents run with `--dangerously-skip-permissions` because the worktree is sandboxed and there's no human in the loop for permission prompts. The seed prompt forbids edits outside the worktree and forbids hook bypass. The blast radius is one disposable worktree.

### Tab-agent crashes mid-task

`poll-result.sh` times out. Treat as a soft `BLOCKED`. Read the tab's pane (`cmux capture-pane --surface <ref> --scrollback`) for context, then either re-dispatch or escalate.

## Integration with other skills

- **Before** invoking this skill, the planner uses `superpowers:writing-plans` (or its own judgment) to produce the sub-task list.
- **After** all sub-tasks are done, the planner runs `superpowers:finishing-a-development-branch` *per sub-task* — each sub-task has its own branch in its own worktree, so each integrates independently.
- The `superpowers:test-driven-development` and `superpowers:verification-before-completion` discipline is **not** invoked at runtime by tab-agents — it is **embedded verbatim** in the seed prompts (see `prompts/implementer-tab-prompt.md` and the reviewer prompts). This is intentional: tab-agents run in fresh `claude` processes that may not have the superpowers plugin loaded, so the discipline must be self-contained.

## Skill layout

```
~/.claude/skills/cmux-tab-agents/
├── SKILL.md                                # this file
├── scripts/
│   ├── ensure-worktree.sh                  # idempotent worktree provisioning
│   ├── dispatch-implementer.sh             # spawn implementer tab
│   ├── dispatch-spec-reviewer.sh           # spawn spec-reviewer tab
│   ├── dispatch-code-reviewer.sh           # spawn code-quality-reviewer tab
│   ├── poll-result.sh                      # planner helper: wait on result file
│   └── _dispatch_common.sh                 # shared dispatch logic (sourced)
├── prompts/
│   ├── implementer-tab-prompt.md           # forked + TDD + verification + hook-bypass
│   ├── spec-reviewer-tab-prompt.md         # forked + verification + hook-bypass
│   └── code-reviewer-tab-prompt.md         # forked + verification + hook-bypass
└── references/
    ├── status-conventions.md               # icons, colors, status keys
    ├── reporting-contract.md               # result file schemas, polling pattern
    ├── divergences-from-upstream.md        # why and where this fork differs
    └── configuration.md                    # env var + per-repo .toml config
```

## See also

- `references/reporting-contract.md` — exact schema of the three result files.
- `references/status-conventions.md` — status pill icon/color table.
- `references/divergences-from-upstream.md` — the diff against `superpowers:subagent-driven-development`.
- `references/configuration.md` — env var and per-repo config for non-default layouts.
- Upstream sources at `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/`.
