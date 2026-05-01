# Status conventions

Every tab-agent reports state on its own workspace **and** mirrors the same status pill onto the planner's workspace, so the planner can see all in-flight tab-agents at a glance from its sidebar without switching tabs.

## Status key format

```
<TICKET>-<phase>
```

- `<TICKET>` — the Jira sub-task ID (or any string ID the planner passed via `--ticket`).
- `<phase>` ∈ `implementer | spec-reviewer | code-reviewer`.

Examples:
- `ALPM-1234-1-implementer`
- `ALPM-1234-1-spec-reviewer`
- `ALPM-1234-1-code-reviewer`

The planner always knows which key to look up because it owns the ticket ID and the phase it just dispatched.

## State / icon / color table

### Implementer

| state                | icon       | color (hex) | when                                           |
|----------------------|------------|-------------|------------------------------------------------|
| `dispatched`         | clock      | `#ff9500`   | planner just spawned the implementer tab        |
| `working`            | hammer     | `#ff9500`   | implementer mid-work                            |
| `testing`            | beaker     | `#007aff`   | running test suite                              |
| `blocked`            | x          | `#ff3b30`   | hook fail, missing context, infra issue         |
| `done`               | checkmark  | `#34c759`   | result file written, all checks green           |
| `done_with_concerns` | warning    | `#ffcc00`   | shipped with caveats listed in result           |

### Spec reviewer

| state           | icon             | color (hex) | when                              |
|-----------------|------------------|-------------|-----------------------------------|
| `dispatched`    | clock            | `#ff9500`   | planner just spawned the tab       |
| `reviewing`     | magnifyingglass  | `#007aff`   | reading code + verifying            |
| `approved`      | checkmark        | `#34c759`   | spec compliance ✅                  |
| `issues_found`  | warning          | `#ffcc00`   | spec gaps to fix                    |

### Code-quality reviewer

| state           | icon             | color (hex) | when                              |
|-----------------|------------------|-------------|-----------------------------------|
| `dispatched`    | clock            | `#ff9500`   | planner just spawned the tab       |
| `reviewing`     | magnifyingglass  | `#007aff`   | reading code + verifying            |
| `approved`      | checkmark        | `#34c759`   | code quality ✅                     |
| `issues_found`  | warning          | `#ffcc00`   | quality issues to fix               |

## How tab-agents emit status

Every transition emits **two** `cmux set-status` calls — one for the local workspace, one for the planner's:

```bash
KEY="${TICKET}-${PHASE}"
cmux set-status "$KEY" "$STATE" --icon "$ICON" --color "$COLOR"
cmux set-status "$KEY" "$STATE" --icon "$ICON" --color "$COLOR" --workspace "$PLANNER_WORKSPACE"
```

On terminal states (`done`, `done_with_concerns`, `blocked`, `approved`, `issues_found`), also emit a notification on the planner's workspace:

```bash
cmux notify --title "$TICKET $PHASE $STATE" --body "<one-line summary>" --workspace "$PLANNER_WORKSPACE"
```

## How the planner reads status

The planner has two channels:

1. **Eyes** — colored pills on the workspace tab in the sidebar. Useful while doing other work.
2. **Result file** — `<worktree>/.cmux-<phase>-result.md`. Authoritative; this is what the planner parses for the four status values (`DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED` for implementer; `APPROVED / ISSUES_FOUND` for reviewers).

The pill is for ambient awareness; the result file is for decisions.
