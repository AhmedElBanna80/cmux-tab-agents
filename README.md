# cmux-tab-agents

A Claude Code plugin that turns the **subagent-driven-development** workflow into something you can actually watch.

Instead of in-process `Agent({...})` subagents that vanish when they're done, this dispatcher spawns each subagent as a **real `claude --dangerously-skip-permissions` process running in a [cmux](https://cmux.com) tab**, inside its own dedicated git worktree per ticket. The planner stays in its own tab, fans out work to dozens of parallel tab-agents, and reads their results from on-disk YAML files.

## Demo 
 

https://github.com/user-attachments/assets/79b46ef7-c948-4051-8d81-4ace9126fa37



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

The short form above clones over SSH. If you don't have a GitHub SSH key configured, the clone will fail — use the HTTPS URL instead:

```sh
/plugin marketplace add https://github.com/AhmedElBanna80/cmux-tab-agents
```

Or, if you want the short form to keep working everywhere, tell git to rewrite GitHub SSH URLs to HTTPS globally:

```sh
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

### 2. Install the plugin

```sh
/plugin install cmux-tab-agents@cmux-tab-agents
```

The skill named `cmux-tab-agents` will appear in your available-skills list. It triggers on phrasing like "execute this plan with cmux tab agents", "dispatch tab agents", "spawn an implementer in a tab", or any moment a planner is breaking a story into sub-tasks while inside cmux.

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

## Local development

Iterate on this plugin in-place — no marketplace re-install loop.

### Prerequisites

- `bash` 3.2+ (macOS default works)
- `jq` — required by link/unlink/status (`brew install jq`)
- `python3` — required by `render-prompt.sh` and the template lint in `lint.sh` (preinstalled on macOS)
- `shellcheck` — recommended, optional (`brew install shellcheck`); `make lint` warns and skips the shell-lint sub-check when it isn't installed
- `make` — entry point (preinstalled on macOS via the Xcode CLT)

### The loop

1. Link this checkout into the plugin cache:

   ```sh
   make link
   ```

   This symlinks the checkout into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. If a real install is already there, it's renamed to `<target>.bak-<timestamp>` so you can restore it later.

2. Edit files under `skills/cmux-tab-agents/`. Changes are live — no re-install needed.

3. Lint:

   ```sh
   make lint
   ```

   Runs shellcheck (if installed) + jq JSON validation + the prompt-template lint (catches stray `{{TYPO}}` placeholders).

4. Run tests:

   ```sh
   make test
   ```

   Runs all test scripts in the repo. Tests must pass before committing.

5. Preview the rendered implementer prompt with sample values:

   ```sh
   make preview
   ```

   For other phases, call the renderer directly:

   ```sh
   scripts/dev/render-prompt.sh spec-reviewer --values TICKET=TEST-1,TASK="dummy"
   scripts/dev/render-prompt.sh code-reviewer
   ```

6. In a real cmux session, exercise `/cmux-tab-agents` against a sample ticket to test the live dispatch end-to-end.

7. Unlink when done:

   ```sh
   make unlink
   ```

   Removes the symlink. If a `.bak-<timestamp>` exists, the script prints the manual `mv` command to restore it. To switch back to the published version: `/plugin install cmux-tab-agents@cmux-tab-agents`.

`make status` shows the current state at any time — `linked` (and to where), `installed (not linked)`, or `not installed`.

### What the tooling does NOT cover

- No end-to-end smoke test that actually dispatches a tab-agent (would require a real cmux session and a throwaway repo). Run `/cmux-tab-agents` manually.
- No CI on PRs — linting is local-only.
- The `cmux <subcmd>` calls inside the dispatch scripts are not mocked.

## How tab-agents report back

Three out-of-band channels per phase:

- **Status pill** on the cmux sidebar (`<TICKET>-<phase>` key, e.g. `ALPM-1234-implementer`), mirrored on the planner's workspace.
- **Log entries** via `cmux log` for the lifecycle audit trail.
- **Notification** via `cmux notify` on terminal states (done / blocked).

And one in-band channel:

- A YAML-frontmatter **result file** at `<worktree>/.cmux-<phase>-result.md`. The planner polls it via `scripts/poll-result.sh`. Schema in [`skills/cmux-tab-agents/references/reporting-contract.md`](skills/cmux-tab-agents/references/reporting-contract.md).

## Session Persistence with crex

To automatically save your cmux workspace state when Claude stops, install [`crex`](https://github.com/drolosoft/cmux-resurrect) (cmux-resurrect):

```bash
brew install drolosoft/tap/crex
```

Then configure your Claude Code to auto-save on session end. Add this to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "crex save $(date +%Y%m%d-%H%M%S) 2>/dev/null || true",
            "statusMessage": "Saving cmux workspace..."
          }
        ]
      }
    ]
  }
}
```

**How it works:**
- On every Claude session end (Ctrl+C, `/clear`, or exit), the hook runs `crex save <timestamp>`
- Saves all cmux tabs, panes, layouts, and working directories with a timestamped name
- On the next cmux launch, restore with: `crex restore <timestamp>` (e.g., `crex restore 20260506-143022`)

**Why this matters:**
- Tab-agents run across multiple worktrees and can take time to complete
- If cmux crashes or you close the terminal, all agent state is persisted on disk (result files survive)
- crex restores your workspace layout so you can resume watching without manually re-opening tabs

## Configuration

Defaults work out of the box for most repos. Two override mechanisms when needed:

- **Env var**: `CMUX_TAB_AGENTS_WORKTREE_BASE=/path/to/base` overrides the worktree base globally.
- **Per-repo TOML**: `<repo>/.claude/cmux-tab-agents.toml` with keys `worktree_base`, `branch_type_default`, `setup_command`, `ticket_pattern`.

Full details: [`skills/cmux-tab-agents/references/configuration.md`](skills/cmux-tab-agents/references/configuration.md).

## Differences from upstream

The skill is a fork of `superpowers:subagent-driven-development`. A complete diff and re-sync guide lives at [`skills/cmux-tab-agents/references/divergences-from-upstream.md`](skills/cmux-tab-agents/references/divergences-from-upstream.md). Source baseline: `superpowers v5.0.7`.

## Hard rules

Every dispatched tab-agent is bound by these (verbatim from the seed prompts):

- **No production code without a failing test first.**
- **No completion claims without fresh verification evidence** (run the test, read the output, then claim).
- **`git commit --no-verify`, `--no-gpg-sign`, `HUSKY=0`, hook-config overrides, and creative hook-shaped escape hatches are FORBIDDEN.** If a hook fails, fix the underlying code or escalate as `BLOCKED`. Do not commit.
- Stay inside the worktree. Never edit files in the parent repo. Never push, merge, or open PRs — that's the planner's call.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to propose changes, the TDD requirements, the no-hook-bypass rule, and the conventional commit style.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Discipline language (TDD iron law, verification iron law, four-status reporting model) is lifted verbatim from [obra/superpowers](https://github.com/obra/superpowers) by Jesse Vincent. This plugin is structurally a downstream fork of `superpowers:subagent-driven-development`.

[cmux](https://cmux.com) by ara.so — the AI-native terminal multiplexer that makes this whole pattern work.
