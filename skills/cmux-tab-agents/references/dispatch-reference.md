# Tab-agent dispatch reference

## Synchronous wrapper (preferred)

For most planner workflows, use `task-adapter.sh` instead of calling
`dispatch-implementer.sh` directly. The adapter wraps dispatch + poll into a
single blocking call, returns the full result body on stdout, and disables
the (deprecated) push channel:

```bash
~/.claude/skills/cmux-tab-agents/scripts/task-adapter.sh implementer \
  --ticket ALPM-1234-1 --title "wire validation" --slug form-validation \
  --task-text "$(cat tasks/ALPM-1234-1.md)"
```

It accepts every flag `dispatch-implementer.sh` does. Use the underlying
dispatch script directly only when you want to spawn an agent without
blocking the planner (rare).

For parallel fan-out, run multiple adapters via `Bash run_in_background=true`
and watch them with `Monitor`.

## Dispatch an implementer

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

For small, focused fixes after a review (preferred for minor issues), use `--fix-only`:

```bash
... --fix-only --feedback-from-previous-review "$(cat $WT/.cmux-spec-reviewer-result.md)"
```

When `--fix-only` is used:
- The implementer boots with a **stripped seed**: identity, worktree, result-file contract, and the reviewer's feedback only — **no full task scaffolding**.
- `--task-text` and `--task-file` become optional (the existing code in the worktree is the task).
- `--feedback-from-previous-review` becomes **required**.
- The implementer is instructed to apply ONLY the reviewer's fixes, not re-derive the task.
- All discipline rules (TDD, hooks, verification) still apply.

**When to use `--fix-only`:**
- The reviewer found minor, localized issues (e.g., "add email regex check", "fix type annotation on line 42").
- The implementer's context is still fresh and relevant.
- You want to save tokens and wall-time by reusing the implementer's existing mental model of the codebase.

**When to use full re-dispatch (omit `--fix-only`):**
- The reviewer found structural or design issues requiring significant rework.
- The implementer's context is polluted (long backlog, many failed attempts).
- You want to switch the implementer's `--model` for a trickier fix.
- The fix scope is large enough that a clean slate is faster.

The script:
1. Provisions the worktree (idempotent — resumes if it exists).
2. Renders the seed prompt.
3. Opens a new cmux tab in your pane.
4. Sets a `<TICKET>-implementer` `dispatched` pill on your workspace.
5. Echoes the new tab's `surface:N` ref on stdout.

## Optional flags

All three dispatch scripts accept:

- `--planner-surface <ref>` — **deprecated; no-op.** The agent→planner push channel was removed when lifecycle hooks were introduced. The flag is preserved for one release for backward compatibility; any value passed is silently ignored. `task-adapter.sh` forces it to `""` regardless.
- `--model <model-id>` — override the Claude model. Use cheaper/faster models for mechanical tasks and stronger models for ambiguous design work.

Both flags are backward-compatible.

## Dispatch a spec-reviewer

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-spec-reviewer.sh \
  --ticket ALPM-1234-1 \
  --title "wire up form validation" \
  --slug form-validation \
  --task-text "$(cat tasks/ALPM-1234-1.md)" \
  --implementer-sha "$(git -C $WT rev-parse HEAD)"
```

## Dispatch a code-quality-reviewer

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-code-reviewer.sh \
  --ticket ALPM-1234-1 \
  --title "wire up form validation" \
  --slug form-validation \
  --task-text "$(cat tasks/ALPM-1234-1.md)" \
  --implementer-sha "$(git -C $WT rev-parse HEAD)"
```
