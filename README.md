# cmux-tab-agents

A Claude Code plugin that turns the **subagent-driven-development** workflow into something you can actually watch.

Instead of in-process `Agent({...})` subagents that vanish when they're done, this dispatcher spawns each subagent as a **real `claude --dangerously-skip-permissions` process running in a [cmux](https://cmux.com) tab**, inside its own dedicated git worktree per ticket. The planner stays in its own tab, fans out work to dozens of parallel tab-agents, and reads their results from on-disk YAML files.

## Why this exists

Upstream `superpowers:subagent-driven-development` is excellent but has three structural limits the cmux pattern dissolves:

| upstream | this plugin |
|---|---|
| Subagent has no shell, no worktree, returns one text blob | Tab-agent has its own shell, its own git worktree, its own commit history |
| Invisible to the user | Visible tab in the cmux sidebar — you can watch, take over, or chat |
| "Never dispatch multiple implementers in parallel — conflicts" | **Safe to dispatch implementers across tasks in parallel** because each owns its own worktree |
| Synchronous (planner blocks on `Agent` return) | Fire-and-forget; planner polls result files and reads sidebar status pills |

What it preserves *verbatim* from upstream:

- The four-status reporting model: `DONE` / `DONE_WITH_CONCERNS` / `NEEDS_CONTEXT` / `BLOCKED`.
- The two-stage per-task review: spec compliance first, then code quality, looped until both approve.
- Test-driven development discipline (red → green → refactor) and the verification iron law (no completion claims without fresh evidence). Both are embedded into every tab-agent's seed prompt — so spawned `claude` processes carry the discipline even though they don't have the superpowers plugin loaded.

What it adds beyond upstream:

- **Cross-task parallelism** (override of upstream's "no parallel implementers" rule, since worktrees eliminate the conflict surface).
- **Hard prohibition on `git commit --no-verify` and equivalents** in every prompt.
- **cmux observability**: status pills, sidebar log entries, and notifications mirror onto the planner's workspace so progress is visible without switching tabs.
- **YAML-frontmatter result files per phase**, polled asynchronously, replacing the upstream `Agent` text return value.

## Requirements

- [Claude Code](https://claude.com/claude-code) installed
- [cmux](https://cmux.com) running (this plugin uses the `cmux` CLI extensively)
- A git repo

The plugin is **repo-agnostic**: it discovers worktree base, default branch, and project-bootstrap commands at runtime. Works in any git repo.

## Install

### 1. Add this marketplace

```sh
/plugin marketplace add AhmedElBanna80/cmux-tab-agents
```

### 2. Install the plugin

```sh
/plugin install cmux-tab-agents@cmux-tab-agents
```

The skill named `cmux-tab-agents` will appear in your available-skills list. It triggers on phrasing like "execute this plan with cmux tab agents", "dispatch tab agents", "spawn an implementer in a tab", or any moment a planner is breaking a story into sub-tasks while inside cmux.

### 3. (Optional) Run the setup wizard

```sh
/cmux-tab-agents:setup
```

Interactive wizard that asks for a default Claude model and a default thinking-effort level (`low`/`medium`/`high`/`xhigh`/`max`), then writes them to `~/.claude/cmux-tab-agents.toml` (or a per-repo file). Once set, every dispatch picks up these defaults — you don't have to repeat `--model` / `--effort` on each call. Skipping the wizard is fine; the plugin works without it (every dispatch falls through to the `claude` CLI's own defaults).

If `/cmux-tab-agents:setup` doesn't show up after install, `/reload-plugins` (or restart Claude Code) — `/plugin update` does not always re-discover newly added top-level command directories until plugins are reloaded.

## Quick start

Inside a cmux session, with the plugin installed, give the planner a parent ticket and ask it to dispatch:

```
I have a story ALPM-1234 with 3 sub-tasks. Use the cmux-tab-agents skill
to dispatch implementers in parallel across worktrees, then run the
two-stage review per task.
```

The planner will:

1. For each sub-task, call `dispatch-implementer.sh` — which provisions `<base>/<TICKET>/<repo-name>` (creating the worktree if needed, resuming if it exists), opens a new cmux tab, and boots `claude` with the implementer seed prompt.
2. Poll each implementer's `.cmux-implementer-result.md` file. On `DONE`, dispatch the spec-reviewer; on `APPROVED`, dispatch the code-reviewer; on `ISSUES_FOUND`, re-dispatch the implementer with the review feedback.
3. Hand off completed sub-tasks to `superpowers:finishing-a-development-branch`.

You can run all of step 1 in parallel — different worktrees, no conflicts.

## How tab-agents report back

Three out-of-band channels per phase:

- **Status pill** on the cmux sidebar (`<TICKET>-<phase>` key, e.g. `ALPM-1234-implementer`), mirrored on the planner's workspace.
- **Log entries** via `cmux log` for the lifecycle audit trail.
- **Notification** via `cmux notify` on terminal states (done / blocked).

And one in-band channel:

- A YAML-frontmatter **result file** at `<worktree>/.cmux-<phase>-result.md`. The planner polls it via `scripts/poll-result.sh`. Schema in [`skills/cmux-tab-agents/references/reporting-contract.md`](skills/cmux-tab-agents/references/reporting-contract.md).

## Configuration

Defaults work out of the box for most repos. Override mechanisms when needed:

- **Layered defaults for `--model` and `--effort`** (v0.3.0+): resolved in order CLI flag > env var (`CMUX_TAB_AGENTS_DEFAULT_MODEL` / `CMUX_TAB_AGENTS_DEFAULT_EFFORT`) > per-repo TOML > user-global TOML > unset. The two new TOML keys are `default_model` and `default_effort`. Set these once via `/cmux-tab-agents:setup` and forget. Effort levels: `low | medium | high | xhigh | max`.
- **Worktree base**: `CMUX_TAB_AGENTS_WORKTREE_BASE=/path/to/base` env var overrides the worktree base globally.
- **Per-repo TOML**: `<repo>/.claude/cmux-tab-agents.toml` accepts `default_model`, `default_effort`, `worktree_base`, `branch_type_default`, `setup_command`, `ticket_pattern`.
- **User-global TOML**: `~/.claude/cmux-tab-agents.toml` accepts `default_model` and `default_effort` (the others are repo-scoped by nature).

Full details and the complete resolution table: [`skills/cmux-tab-agents/references/configuration.md`](skills/cmux-tab-agents/references/configuration.md).

## Differences from upstream

The skill is a fork of `superpowers:subagent-driven-development`. A complete diff and re-sync guide lives at [`skills/cmux-tab-agents/references/divergences-from-upstream.md`](skills/cmux-tab-agents/references/divergences-from-upstream.md). Source baseline: `superpowers v5.0.7`.

## Hard rules

Every dispatched tab-agent is bound by these (verbatim from the seed prompts):

- **No production code without a failing test first.**
- **No completion claims without fresh verification evidence** (run the test, read the output, then claim).
- **`git commit --no-verify`, `--no-gpg-sign`, `HUSKY=0`, hook-config overrides, and creative hook-shaped escape hatches are FORBIDDEN.** If a hook fails, fix the underlying code or escalate as `BLOCKED`. Do not commit.
- Stay inside the worktree. Never edit files in the parent repo. Never push, merge, or open PRs — that's the planner's call.

## Development

Working on the plugin itself? [`CONTRIBUTING.md`](CONTRIBUTING.md) covers the symlink trick (`./scripts/dev-link.sh` makes Claude Code load directly from your worktree, no `/plugin update` cycle), the daily edit → `/reload-plugins` → test loop, the lockstep version-bump script, and `claude --plugin-dir .` for sandbox testing.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Discipline language (TDD iron law, verification iron law, four-status reporting model) is lifted verbatim from [obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent. This plugin is structurally a downstream fork of `superpowers:subagent-driven-development`.

[cmux](https://cmux.com) by ara.so — the AI-native terminal multiplexer that makes this whole pattern work.
