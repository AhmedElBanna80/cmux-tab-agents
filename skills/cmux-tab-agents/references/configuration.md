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
| `--model MODEL_ID`                 | no       | (omit — use user's default)                      | Override the Claude model the tab-agent's `claude` process runs with. Append-as-is to the boot command (`claude --model <id> ...`). Use cheaper/faster models for mechanical tasks (`claude-haiku-4-5-20251001`) and stronger models for ambiguous design work, mirroring upstream `superpowers:subagent-driven-development`'s Model Selection. |
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
```

### Resolution priority

`ensure-worktree.sh` resolves the worktree base in this order (first match wins):

1. `$CMUX_TAB_AGENTS_WORKTREE_BASE` env var.
2. `worktree_base` key in `<repo>/.claude/cmux-tab-agents.toml`.
3. `<repo>/.worktrees/` if it exists *and* is git-ignored.
4. `<parent-of-repo>/worktrees/<repo-name>/` (sibling default — no gitignore concern, since it's outside the repo).

If none of these resolve to a usable path, dispatch fails with a clear error pointing to the env var and the config file.

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
