# cmux-tab-agents

> **🪦 Archived (May 2026).** This plugin has been superseded by native Claude Code Agent Teams + cmux's native `claude-teams` integration. Its remaining IP — four superpowers-disciplined subagent definitions — has been extracted into the new [**superteam**](https://github.com/AhmedElBanna80/superteam) plugin.

If you're new here, **don't install this plugin.** Use the new stack instead. See [migration](#migration) below.

If you used this plugin: thank you, it worked, and the lessons learned shaped the successor. Read on for context.

---

## What this was

A Claude Code plugin that ran a TDD-driven planner → implementer → spec-reviewer → code-reviewer pipeline by spawning each subagent as a **real `claude --dangerously-skip-permissions` process in a cmux tab**, inside a dedicated git worktree. The planner polled YAML result files; tabs reported back via lifecycle hooks; the beta channel experimented with in-process `Task()` dispatch and progress-event streams.

It was built before native Claude Code Agent Teams existed. It validated the design — and Anthropic ultimately shipped essentially the same architecture natively.

## Why it's archived

Between February and May 2026, three native developments closed the gap this plugin filled:

1. **[Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)** (research preview, v2.1.139+) — native multi-subagent orchestration with a shared dependency-managed task list, plan approval, hooks for quality gates, and split-pane display.
2. **[Claude Code Agent View](https://code.claude.com/docs/en/agent-view)** (`claude agents`) — native TUI dashboard for all in-flight sessions with state icons, peek/reply/attach, PR status, kept alive by a supervisor process.
3. **[cmux's native `claude-teams` integration](https://cmux.com/docs/agent-integrations/claude-code-teams)** (since cmux nightly, March 2026) — `cmux claude-teams --dangerously-skip-permissions` translates Claude Code's tmux-pane commands into native cmux splits via a transparent shim. No upstream Claude Code change required.

Plus: `isolation: worktree` in subagent frontmatter, `Agent(agent_type)` tool restriction, Channels for webhooks, Routines / `/loop` / GitHub Actions schedule for headless scheduling. **Native covers every infrastructure layer this plugin was built for.**

The only IP still worth shipping is **four superpowers-disciplined subagent definitions** that turn generic Agent Teams into the TDD-driven pipeline. Those are now in [`superteam`](https://github.com/AhmedElBanna80/superteam).

## Migration

If you used `cmux-tab-agents`:

```bash
# 1. Uninstall this plugin
claude /plugin uninstall cmux-tab-agents
claude /plugin uninstall cmux-tab-agents-beta   # if you were on beta

# 2. Install the successor
claude /plugin marketplace add AhmedElBanna80/superteam
claude /plugin install superteam

# 3. Run the setup wizard
claude /superteam:setup

# 4. Launch with the command the wizard prints. For cmux users:
cmux claude-teams --dangerously-skip-permissions
# Then inside the session:
#   "Spawn superteam-implementer, superteam-spec-reviewer, superteam-code-reviewer as my team.
#    Then process ticket TICKET-1: <your spec>."
```

All your existing tickets and workflow patterns transfer. Only the dispatch grammar changes — instead of `task-adapter.sh` shelling out to four bash scripts, the lead calls native Agent Teams primitives and teammates self-claim from the shared task list.

For the full reasoning + lessons learned, see [`STATUS.md`](STATUS.md).

## What survives

Four `.md` files in `superteam/agents/`, lightly polished versions of what this plugin shipped at `agents/cmux-implementer.md` plus three new reviewer definitions that were deferred by [ISSUE-96 / PR #100](https://github.com/AhmedElBanna80/cmux-tab-agents/pull/100):

- `superteam-planner.md` — was new in `superteam`.
- `superteam-implementer.md` — direct evolution of `cmux-tab-agents/agents/cmux-implementer.md`.
- `superteam-spec-reviewer.md` — new in `superteam`.
- `superteam-code-reviewer.md` — new in `superteam`.

Plus an interactive `/superteam:setup` wizard that asks for multiplexer + per-agent model.

## What got absorbed by the platform

| Built here | Now native in… |
|---|---|
| Process-per-subagent dispatch (`dispatch-*.sh`, `task-adapter.sh`, `poll-result.sh`) | Claude Code Agent Teams (in-process subagents + shared task list) |
| Per-worktree lifecycle hooks (`install-tab-hooks.sh`, `session_start.sh`, `post_tool_use.sh`, `stop.sh`) | Claude Code session lifecycle + Agent Teams quality-gate hooks |
| Per-tab progress UI (`agent-tab-renderer.sh`, `.cmux-progress.jsonl`, `stream-watcher.sh`) | Agent View (`claude agents`) + Agent Teams split-pane display |
| Cmux tab routing (`resolve-agents-pane.sh`, layout config) | `cmux claude-teams` tmux-compat shim |
| Worktree provisioning (`ensure-worktree.sh`) | `isolation: worktree` subagent frontmatter OR planner-side `git worktree add` (chosen in `superteam`) |
| Result file polling + YAML schema | Native `Agent()` synchronous return values + Agent Teams completion notes |
| Finish modes (`finish-task.sh` keep/pr/merge) | `superpowers:finishing-a-development-branch` invoked by the planner |
| Cleanup orchestration (`/cmux-tab-agents:cleanup`) | Native `claude agents` session management + `git worktree prune` |

See [`STATUS.md`](STATUS.md) for the full inventory.

## Historical archive

The plugin's source remains intact in this repo as a record. No further releases, no further bug fixes. Final tagged release was **cmux-tab-agents 0.12.0** (2026-05-11), with a handful of un-released fixes on `main` (PRs #138, #147, #132, #134). Beta channel (`cmux-tab-agents-beta` 0.12.0-beta.0) is also archived — its experiments around Task() dispatch (PR #100), progress event streams (PR #102, #109, #119), Phase 3 stream coordination (PR #114), and workspace state tracking (PR #113) all graduated to stable in 0.12.0 before the platform absorbed the entire architecture.

## Acknowledgments

- [Anthropic](https://anthropic.com) for shipping the native primitives that made this plugin unnecessary — that's a good outcome.
- [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) and [@lawrencecchen](https://github.com/lawrencecchen) for the [`cmux claude-teams`](https://cmux.com/docs/agent-integrations/claude-code-teams) shim, which made cmux a first-class Agent Teams display target overnight ([cmux#123 comment 4045384569](https://github.com/manaflow-ai/cmux/issues/123#issuecomment-4045384569)).
- The [superpowers](https://github.com/anthropics/superpowers) plugin's `subagent-driven-development`, `test-driven-development`, `verification-before-completion`, `writing-plans`, and `finishing-a-development-branch` skills — the discipline this whole pipeline runs on.

## License

MIT. See [LICENSE](LICENSE).
