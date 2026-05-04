---
# This is the /cmux-tab-agents:setup command.
# It guides users through interactive configuration of default model and effort settings.
---

# Welcome to cmux-tab-agents setup

**cmux-tab-agents** automates code review workflows by dispatching tab-agents (implementer, spec-reviewer, code-reviewer). This setup command lets you configure personal defaults for Claude model and thinking effort—so you don't have to pass `--model` and `--effort` flags on every dispatch.

Your preferences will be saved to a config file (you choose the location), and subsequent dispatches will use them automatically.

Let's go through a quick series of questions:

---

## Step 1: Default Claude model

Which Claude model should tab-agents use by default? (You can override this later with `--model` CLI flag or `CMUX_TAB_AGENTS_DEFAULT_MODEL` env var.)

---

You'll be asked to choose a model. Here's what each offers:

- **claude-sonnet-4-6** — Recommended for parallel mechanical work (refactors, boilerplate, test writing). Fast, cost-effective, strong reasoning.
- **claude-opus-4-7** — Recommended for complex reasoning and design work (specs, architecture, code review). Slowest, most expensive, best quality.
- **claude-haiku-4-5-20251001** — Fastest and cheapest; best for trivial tasks only. Limited reasoning.
- **Skip** — Don't set a default; let each dispatch decide via env var, config, or Claude's default.

Once you choose, we'll move to effort level, then save location.

---

## Step 2: Default effort level

Effort controls Claude's thinking time and budget per request. (Override later with `--effort` CLI flag or `CMUX_TAB_AGENTS_DEFAULT_EFFORT` env var.)

- **low** — Fastest, least thinking (for trivial changes).
- **medium** — Balanced.
- **high** — Recommended default (good balance of speed and quality).
- **xhigh** — Extra thinking, slower (for complex design decisions).
- **max** — Maximum thinking budget, slowest (for very hard problems).
- **Skip** — Don't set a default.

---

## Step 3: Where to save?

Choose whether to save your defaults globally (in `~/.claude/cmux-tab-agents.toml`, recommended for personal defaults) or per-repo (in `.claude/cmux-tab-agents.toml` under the current repo, for project-specific overrides).

---

## Step 4: Bonus—optional per-repo settings (if new file)

If we're creating a fresh config file, you can also set:

- **worktree_base** — Where to clone worktrees. Default: `../worktrees` (sibling to your repo). Relative paths are resolved against the repo root.
- **branch_type_default** — Prefix for feature branches. Default: `feat` (so branches look like `feat/TICKET-123/slug`). Other common values: `fix`, `chore`.

We'll offer to set these only if the config file doesn't exist yet. If you skip, defaults apply.

---

Now, begin executing the task per the system prompt. Ask the user for their choices using AskUserQuestion (once per step), then:

1. **After model choice**: If not "Skip", store `default_model = "..."`.
2. **After effort choice**: If not "Skip", store `default_effort = "..."`.
3. **After save location**: Determine the file path.
4. **After location**: If the file will be new, offer the bonus prompt for `worktree_base` and `branch_type_default`.
5. **Read existing file** (if it exists) and preserve unrelated keys.
6. **Write the merged config** with TOML syntax (flat top-level keys, no `[sections]`).
7. **Print confirmation**: one line showing what was saved and the resolved settings.

Example output:
```
✓ Saved to ~/.claude/cmux-tab-agents.toml
default_model = claude-sonnet-4-6
default_effort = high
(To override: --model <id> or CMUX_TAB_AGENTS_DEFAULT_MODEL, --effort <level> or CMUX_TAB_AGENTS_DEFAULT_EFFORT)
```
