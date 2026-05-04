---
description: Interactive setup wizard for cmux-tab-agents — pick default model, effort, and worktree config in one go
---

# cmux-tab-agents setup

You are running the interactive setup wizard for the **cmux-tab-agents** plugin. Your job is to ask the user a small number of questions, then write a single TOML config file. After this command runs once, every dispatch (`dispatch-implementer.sh`, `dispatch-spec-reviewer.sh`, `dispatch-code-reviewer.sh`) will pick up these defaults automatically — the planner won't have to repeat `--model` / `--effort` on every call.

## Step 0 — Greet (one short paragraph)

Tell the user, in 2–3 sentences:

- This wizard configures defaults for the implementer / spec-reviewer / code-reviewer tabs that the plugin spawns.
- It's purely additive: anything you skip here will fall back to the user's `claude` defaults at dispatch time.
- It writes one file (TOML). Resolution order at dispatch time is documented; you'll show it at the end.

Do not dump the full resolution table now — show it once at the very end, after the file is written.

## Step 1 — Default model

Use **AskUserQuestion** with `multiSelect: false`, header "Model", question "Default model for tab-agents?" and these options:

- `claude-sonnet-4-6` — recommended for parallel mechanical work (refactors, codemods, wiring tests).
- `claude-opus-4-7` — recommended for complex reasoning, design work, ambiguous specs.
- `claude-haiku-4-5-20251001` — fastest / cheapest. Trivial tasks only.
- `Skip` — let each dispatch decide via its own `--model` flag, env var, or the `claude` CLI default.

Save the user's choice as `MODEL_CHOICE`. If they picked `Skip`, leave it unset.

## Step 2 — Default effort

Use **AskUserQuestion** with `multiSelect: false`, header "Effort", question "Default thinking-effort level?" and these options:

- `low` — fastest, cheapest. For mechanical edits where the path is obvious.
- `medium` — balanced. Sensible default for most tasks.
- `high` — more reasoning steps. For tasks with non-trivial design work.
- `xhigh` — extensive reasoning. For ambiguous specs or tricky bugs.
- `max` — maximum reasoning. Reserve for the hardest cases; expect significant cost.
- `Skip` — let each dispatch decide via its own `--effort` flag, env var, or the `claude` CLI default.

Save as `EFFORT_CHOICE`. If `Skip`, leave unset.

## Step 3 — Save location

Use **AskUserQuestion** with `multiSelect: false`, header "Save to", question "Where should these defaults live?" and these options:

- `User-global (~/.claude/cmux-tab-agents.toml)` — applies to every repo on this machine.
- `This repo only (./.claude/cmux-tab-agents.toml)` — applies only when dispatching from inside this repo. Per-repo overrides user-global.
- `Both` — write user-global first, then layer the per-repo file on top. Use this when you have a global default but one specific repo needs different settings (ask in Step 1/2 again or just confirm the per-repo file should mirror the global).

Save as `SAVE_LOCATION`. If the user picked `This repo only` and we are not inside a git repo (`git rev-parse --show-toplevel` fails), fall back to user-global and tell them why.

## Step 4 — Bonus: worktree base + branch type default

While we're already in the config file, offer to also set the two existing worktree-related keys. Use **AskUserQuestion** with `multiSelect: true` and these options:

- `Set worktree_base` — the directory where per-task worktrees are created. Default if unset: `<parent-of-repo>/worktrees/<repo-name>`.
- `Set branch_type_default` — the prefix on auto-generated branch names (`feat/<TICKET>/<slug>`). Default if unset: `feat`.
- `Skip both` (mutually exclusive — if checked, ignore the other two).

For each one the user checked, ask a short follow-up:

- For `worktree_base`: ask the path. Accept absolute or relative. Note in the prompt that relative paths resolve against the repo root.
- For `branch_type_default`: ask the prefix. Common values: `feat`, `fix`, `chore`, `refactor`. Default if blank: `feat`.

## Step 5 — Write the file(s)

Determine the target path(s) from `SAVE_LOCATION`:

- User-global: `$HOME/.claude/cmux-tab-agents.toml`.
- Per-repo: `<repo-root>/.claude/cmux-tab-agents.toml` where `<repo-root>` is `git rev-parse --show-toplevel`.

For each target:

1. If the file exists, read it. **Preserve any keys we are not changing.** Replace only the keys this wizard is responsible for (`default_model`, `default_effort`, `worktree_base`, `branch_type_default`). Use a section comment `# managed by /cmux-tab-agents:setup` only on a fresh file — do not add it to an already-existing file.
2. Write the file with the merged content. Quote string values with double quotes.
3. After writing, `git check-ignore` the file path (per-repo only) — if it's not ignored, mention to the user that they may want to add `.claude/cmux-tab-agents.toml` to `.gitignore` (or commit it deliberately, depending on whether the repo wants shared per-repo defaults).

Sample fresh-file body (illustrative — only emit the keys the user actually set):

```toml
# managed by /cmux-tab-agents:setup
default_model = "claude-sonnet-4-6"
default_effort = "high"
worktree_base = "../worktrees"
branch_type_default = "feat"
```

## Step 6 — Confirmation

Echo back, on one line each, every key actually written and where it landed. Example:

```
default_model = claude-sonnet-4-6   → /Users/you/.claude/cmux-tab-agents.toml
default_effort = high               → /Users/you/.claude/cmux-tab-agents.toml
```

Then, in 4–5 lines, restate the resolution order so the user knows how to override later:

```
Resolution order at dispatch time (first match wins):
  1. CLI flag (--model / --effort)
  2. Env var (CMUX_TAB_AGENTS_DEFAULT_MODEL / CMUX_TAB_AGENTS_DEFAULT_EFFORT)
  3. Per-repo:    <repo>/.claude/cmux-tab-agents.toml
  4. User-global: ~/.claude/cmux-tab-agents.toml
  5. Unset       (claude CLI default)
```

That's it. Stop. Do not dispatch any agents — this command only writes config.

## Failure modes

- **Not inside a git repo, user picked per-repo or both:** fall back to user-global. Explain why in one line.
- **TOML file contains lines we can't parse (multi-line array, complex tables):** preserve those lines verbatim, only update the flat keys this wizard owns. If you genuinely cannot determine where a key lives, abort with a clear message asking the user to edit by hand and showing them the path.
- **User picks `Skip` for both model and effort and `Skip both` for the bonus:** there is nothing to write. Tell the user, do not create an empty file.
