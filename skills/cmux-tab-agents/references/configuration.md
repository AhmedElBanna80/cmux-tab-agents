# Configuration

The skill is repo-agnostic. Defaults work out of the box for most projects. If your repo has non-standard layout or bootstrap, you have several override mechanisms.

## Dispatch CLI flags

All three dispatch scripts (`dispatch-implementer.sh`, `dispatch-spec-reviewer.sh`, `dispatch-code-reviewer.sh`) accept the same shared flags:

| Flag                               | Required | Default                                          | Purpose |
|------------------------------------|----------|--------------------------------------------------|---------|
| `--ticket TICKET`                  | yes      | —                                                | Stable ID used as the worktree directory and status-pill key. |
| `--title TITLE`                    | yes      | —                                                | Human-readable title; appears in the cmux tab name and seed prompt. |
| `--slug SLUG`                      | yes      | —                                                | Short kebab-case slug used in the branch name (`<type>/<TICKET>/<slug>`). |
| `--task-text "TEXT"` *or* `--task-file PATH` | yes (one of) | — | Full task spec. Use `--task-file` for multi-paragraph specs. |
| `--type TYPE`                      | no       | `feat` (or per-repo `branch_type_default`)       | Branch prefix: `feat`, `fix`, `chore`, etc. |
| `--planner-workspace REF`          | no       | `$CMUX_WORKSPACE_ID` (the dispatcher's workspace)| Where status pills are mirrored. |
| `--planner-surface REF`            | no       | dispatcher's own `surface_ref` from `cmux identify` | Where tab-agents push their one-line terminal-state message (see "How tab-agents talk to you" in `SKILL.md`). Pass `""` to disable the push channel and fall back to pure polling. |
| `--model MODEL_ID`                 | no       | (resolved — see section below)                   | Override the Claude model the tab-agent's `claude` process runs with. Resolved via the layered defaults (CLI > env > per-repo TOML > user-global TOML > unset). Use cheaper/faster models for mechanical tasks (`claude-haiku-4-5-20251001`) and stronger models for ambiguous design work, mirroring upstream `superpowers:subagent-driven-development`'s Model Selection. |
| `--effort LEVEL`                   | no       | (resolved — see section below)                   | Override the thinking effort level for tab-agents: `low`, `medium`, `high`, `xhigh`, `max`. Resolved via the layered defaults (CLI > env > per-repo TOML > user-global TOML > unset). Omit or set via config for default. |
| `--implementer-sha SHA`            | no       | —                                                | Reviewer-only: the implementer's commit so the reviewer can scope its read. |
| `--feedback-from-previous-review TEXT_OR_PATH` | no | — | On re-dispatch after a review found issues, pass the previous review's findings (literal text or readable file path). Wired into the seed prompt's "Feedback from a previous review" section. |

All four optional knobs (`--type`, `--planner-workspace`, `--planner-surface`, `--model`, `--implementer-sha`, `--feedback-from-previous-review`) are backward-compatible — omitting them yields the same behavior as before each was added.

### Examples

Default invocation (planner surface and model auto-detected / unset):

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-implementer.sh \
  --ticket ALPM-1234-1 --title "form validation" --slug form-validation \
  --task-file ./tasks/ALPM-1234-1.md
```

Mechanical refactor with the cheapest model:

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-implementer.sh \
  --ticket ALPM-1234-2 --title "rename module" --slug rename-module \
  --task-file ./tasks/ALPM-1234-2.md \
  --model claude-haiku-4-5-20251001
```

Send terminal-state pushes to a different surface than the one running the dispatcher (e.g. you want the inbox in tab `surface:3`, but you're triggering dispatch from `surface:5`):

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-implementer.sh \
  --ticket ALPM-1234-3 --title "wire api" --slug wire-api \
  --task-file ./tasks/ALPM-1234-3.md \
  --planner-surface surface:3
```

Disable the push channel entirely (pure polling):

```bash
~/.claude/skills/cmux-tab-agents/scripts/dispatch-implementer.sh \
  --ticket ALPM-1234-4 --title "..." --slug ... \
  --task-file ./tasks/ALPM-1234-4.md \
  --planner-surface ""
```

## Env var: `CMUX_TAB_AGENTS_WORKTREE_BASE`

Sets the base directory for all worktrees, globally. The actual worktree path becomes:

```
$CMUX_TAB_AGENTS_WORKTREE_BASE/<REPO_NAME>/<TICKET>/<REPO_NAME>
```

Example:

```bash
export CMUX_TAB_AGENTS_WORKTREE_BASE=/tmp/cmux-worktrees
~/.claude/skills/cmux-tab-agents/scripts/dispatch-implementer.sh --ticket FOO-1 ...
# → /tmp/cmux-worktrees/<repo-name>/FOO-1/<repo-name>
```

Set this in your shell profile if you want a non-default location for every repo.

## Per-repo config: `<repo>/.claude/cmux-tab-agents.toml`

Optional. Create this file at the root of any repo where the defaults aren't right.

### Supported keys

```toml
# Default Claude model for dispatches. Values: claude-opus-4-7, claude-sonnet-4-6,
# claude-haiku-4-5-20251001, or any valid model ID. Resolved via the layered defaults
# (CLI > env > per-repo TOML > user-global TOML > unset).
default_model = "claude-sonnet-4-6"

# Default effort level (thinking budget). Values: low, medium, high, xhigh, max.
# Resolved via the layered defaults (CLI > env > per-repo TOML > user-global TOML > unset).
default_effort = "high"

# Worktree base directory. Relative paths are resolved against the repo root.
# Absolute paths are used as-is.
worktree_base = "../worktrees"

# Default branch type prefix (used when --type isn't passed on the cli).
branch_type_default = "feat"

# Override the auto-detected bootstrap. If set, this command is run instead of
# the mise/pnpm/uv/etc probes. Run from the new worktree's root.
setup_command = "make bootstrap"

# Validate the --ticket arg against this regex. Default: any non-empty string.
ticket_pattern = "^[A-Z]+-[0-9]+(-[0-9]+)?$"

# Per-phase default models. Used when --model is not passed on the CLI.
# See "Model defaults by phase" below for details.
[models]
implementer    = "claude-sonnet-4-6"            # default for implementer phase
spec_reviewer  = "claude-haiku-4-5-20251001"    # default for spec review
code_reviewer  = "claude-haiku-4-5-20251001"    # default for code review
```

## User-global config: `~/.claude/cmux-tab-agents.toml`

Optional. Create this file at `~/.claude/cmux-tab-agents.toml` to set personal defaults for all repos.

Supports the same flat keys as per-repo TOML:

```toml
default_model = "claude-sonnet-4-6"
default_effort = "high"
worktree_base = "/tmp/cmux-worktrees"
branch_type_default = "feat"
```

Use `/cmux-tab-agents:setup` (interactive configuration wizard) to create/edit this file.

## Resolution order for defaults

### Model and effort resolution (dispatch time)

When dispatch is called, `--model` and `--effort` are resolved in this order (first match wins):

1. CLI flag (`--model MODEL` / `--effort LEVEL`)
2. Env var (`CMUX_TAB_AGENTS_DEFAULT_MODEL` / `CMUX_TAB_AGENTS_DEFAULT_EFFORT`)
3. Per-repo TOML key: `<repo>/.claude/cmux-tab-agents.toml` with key `default_model` / `default_effort`
4. User-global TOML key: `~/.claude/cmux-tab-agents.toml`, same keys
5. Unset (Claude uses its own default)

### Worktree base resolution

`ensure-worktree.sh` resolves the worktree base in this order (first match wins):

1. `$CMUX_TAB_AGENTS_WORKTREE_BASE` env var.
2. `worktree_base` key in `<repo>/.claude/cmux-tab-agents.toml`.
3. `<repo>/.worktrees/` if it exists *and* is git-ignored.
4. `<parent-of-repo>/worktrees/<repo-name>/` (sibling default — no gitignore concern, since it's outside the repo).

If none of these resolve to a usable path, dispatch fails with a clear error pointing to the env var and the config file.

## Model defaults by phase

Each dispatch script (implementer, spec-reviewer, code-reviewer) can have per-phase Claude model defaults, so you don't pay premium-model rates on mechanical tasks.

### Precedence order

When a dispatch script is invoked, the model to use is resolved in this order (first match wins):

1. **CLI flag:** `--model MODEL_ID` on the dispatch command (highest priority).
2. **Repo config:** `[models].<phase>` in `<repo>/.claude/cmux-tab-agents.toml`.
3. **Global default:** The Claude model configured in the user's global settings (current behavior if neither flag nor config is set).

### Example

Set per-phase defaults in your repo to use cheaper Haiku for reviews (which are mechanical) and stronger Sonnet for the implementer phase (which benefits from better reasoning):

```toml
# .claude/cmux-tab-agents.toml
[models]
implementer    = "claude-sonnet-4-6"            # ambiguous design work → stronger model
spec_reviewer  = "claude-haiku-4-5-20251001"    # mechanical → cheaper model
code_reviewer  = "claude-haiku-4-5-20251001"    # mechanical → cheaper model
```

Then dispatch without worrying about the cost:

```bash
./scripts/dispatch-implementer.sh --ticket PROJ-123 --title "..." --slug ... --task-file ...
# → uses claude-sonnet-4-6 (from config)

./scripts/dispatch-spec-reviewer.sh --ticket PROJ-123 ... --task-file ...
# → uses claude-haiku-4-5-20251001 (from config)

./scripts/dispatch-spec-reviewer.sh --ticket PROJ-123 ... --task-file ... --model claude-opus-4-7
# → uses claude-opus-4-7 (CLI flag overrides config)
```

The dispatch script prints the resolved model to stderr, so you can verify which model was chosen:

```
Resolved model for implementer: claude-sonnet-4-6
```

### Bootstrap probes (default behavior)

If `setup_command` is not set, `ensure-worktree.sh` probes the new worktree for project markers and runs the matching tool (best-effort — failures don't block dispatch):

| Marker file              | Tool                    | Command                          |
|--------------------------|-------------------------|----------------------------------|
| `mise.toml` or `.mise.toml` | mise                  | `mise install`                   |
| `pnpm-lock.yaml`         | pnpm                    | `pnpm install --frozen-lockfile` |
| `bun.lockb` or `bun.lock`| bun                     | `bun install --frozen-lockfile` |
| `yarn.lock`              | yarn                    | `yarn install --frozen-lockfile`|
| `package-lock.json`      | npm                     | `npm ci`                         |
| `package.json` (no lockfile) | npm                 | `npm install`                    |
| `pyproject.toml` + `uv.lock` | uv                  | `uv sync`                        |
| `pyproject.toml`         | pip                     | `pip install -e .`               |
| `Gemfile`                | bundler                 | `bundle install`                 |
| `go.mod`                 | go                      | `go mod download`                |
| `Cargo.toml`             | (skipped — auto-fetches)| —                                |

Output goes to `<worktree>/.cmux-bootstrap.log`. If you don't want any of these, set `setup_command = "true"` (a no-op).

## Inspecting the resolved configuration

Run with `--dry-run` to see what `ensure-worktree.sh` would do without actually touching anything:

```bash
cd /path/to/your/repo
~/.claude/skills/cmux-tab-agents/scripts/ensure-worktree.sh \
  --ticket TEST-1 --slug smoke --dry-run
```

Output (to stderr):
```
ensure-worktree (dry-run):
  repo:           /Users/you/repos/my-project
  default branch: main
  base:           /Users/you/repos/worktrees/my-project
  worktree:       /Users/you/repos/worktrees/my-project/TEST-1/my-project
  branch:         feat/TEST-1/smoke
```

Use that to confirm the resolution before running for real.
