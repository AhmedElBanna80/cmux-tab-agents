# Tab-agent dispatch reference

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

The script:
1. Provisions the worktree (idempotent — resumes if it exists).
2. Renders the seed prompt.
3. Opens a new cmux tab in your pane.
4. Sets a `<TICKET>-implementer` `dispatched` pill on your workspace.
5. Echoes the new tab's `surface:N` ref on stdout.

## Optional flags

All three dispatch scripts accept:

- `--planner-surface <ref>` — surface ref where tab-agents should push their terminal-state line. Defaults to auto-detected surface. Pass explicitly only if you want the push to land elsewhere.
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
