# Status: Archived (May 2026)

This repository is no longer maintained. It was archived on **2026-05-13** because native Claude Code + cmux features now cover its entire scope.

The successor is [**`superteam`**](https://github.com/AhmedElBanna80/superteam) — four superpowers-disciplined subagent definitions that plug into native Agent Teams. Use that instead.

## Final state

- **Last stable release:** `cmux-tab-agents 0.12.0` (2026-05-11; promoted from beta in PR #118, included MONITORING-116 + Phase 3 stream coordination).
- **Last beta release:** `cmux-tab-agents-beta 0.12.0-beta.0` (2026-05-11).
- **Unreleased post-0.12.0 fixes on main (now frozen):**
  - PR #138 — ISSUE-136 keyword-overlap secondary check to implementer circuit-breaker.
  - PR #147 — ISSUE-139 quote `${files[@]}` in cleanup-helper check-syntax loop.
  - PR #132, #134 — VALIDATE-001/002 `--apply` flag + autonomous verdict reaction. Not promoted to a tagged release; live on `main` as the repo's final state.
- **Open issues at archive time:**
  - [#96 — Multi-agent Task() dispatch with cmux tab visibility](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/96) — POC landed in PR #100. The reviewer-side work it scoped (`cmux-spec-reviewer`, `cmux-code-reviewer` Task() defs) is **completed** in `superteam`.
- **Experiments that graduated from beta to stable in 0.12.0:**
  - PR #100 (ISSUE-96) — Task() dispatch with cmux tab visibility POC.
  - PR #102, #109 (ISSUE-93 v1/v2) — progress event stream and reviewer expansion.
  - PR #114 (ISSUE-93 Phase 3) — agent-to-agent stream coordination (`stream-watcher.sh` + v2 `progress.sh` schema).
  - PR #119 (MONITORING-116) — planner monitoring for the shared progress stream.
  - PR #113 (ISSUE-112) — workspace state tracking + cleanup manifest.

## What survives in `superteam`

| Old artifact | New form in `superteam` |
|---|---|
| `agents/cmux-implementer.md` | `agents/superteam-implementer.md` (slim, references superpowers skills instead of embedding ~440 lines of TDD/verification copies) |
| Implementer prompt at `skills/cmux-tab-agents/prompts/implementer-tab-prompt.md` | Absorbed into the slim `superteam-implementer.md` body |
| The spec-reviewer + code-reviewer prompts at `skills/cmux-tab-agents/prompts/*-tab-prompt.md` | Materialized as `agents/superteam-spec-reviewer.md` + `agents/superteam-code-reviewer.md` (these were deferred from PR #100's scope and never shipped here) |
| `/cmux-tab-agents:setup` slash command | `/superteam:setup` interactive wizard (multiplexer + per-agent model) |
| Worktree-per-task model (heavy path) | Worktree-per-ticket model (lighter; impl + spec-review + code-review share the worktree) |

## What got absorbed by the platform

| Built here | Now native in… |
|---|---|
| Process-per-subagent dispatch (`scripts/dispatch-*.sh`, `task-adapter.sh`, `poll-result.sh`) | Claude Code Agent Teams (in-process subagents + shared task list with file-locked self-claim) |
| Per-worktree lifecycle hooks (`scripts/install-tab-hooks.sh`, `hooks/*.sh`) | Claude Code session lifecycle hooks + Agent Teams quality-gate hooks |
| Per-tab progress rendering (`scripts/agent-tab-renderer.sh`) | Agent Teams split-pane display + Agent View (`claude agents`) |
| `.cmux-progress.jsonl` + `Monitor` integration (PR #102, #109, #119) | Agent Teams dependency auto-unblock + completion notes |
| `stream-watcher.sh` agent-to-agent coordination (PR #114, Phase 3 of ISSUE-93) | Shared task list + reviewer→implementer re-add via `ISSUES_FOUND` (no JSONL plumbing needed) |
| Cmux tab routing (`scripts/resolve-agents-pane.sh`, `agents_pane_layout` TOML) | `cmux claude-teams` tmux-compat shim (cmux side, not Claude Code side) |
| Worktree provisioning (`scripts/ensure-worktree.sh`) | `isolation: worktree` subagent frontmatter, OR planner-side `git worktree add` (chosen in `superteam` for per-ticket granularity) |
| Result file polling + YAML frontmatter contract | Native `Agent()` synchronous return values + Agent Teams completion notes |
| Finish modes (`scripts/finish-task.sh keep|pr|merge`) | `superpowers:finishing-a-development-branch` invoked by the planner |
| Cleanup orchestration (`scripts/cleanup-helper.sh`, `/cmux-tab-agents:cleanup`) | Native `claude agents` session management + `git worktree prune` |
| Beta release channel infrastructure (release-please-config-beta.json, dual marketplace entries) | Same pattern reused in `superteam` (single-channel for now). |
| Layered surface refs + status pills (`cmux set-status`, `cmux send`, surface focus) | `superpowers:subagent-driven-development` status conventions + native Agent View peek/reply/attach |

## Lessons learned (the parts you can't get from the code)

1. **Process-per-subagent is too heavy.** ~10–30s boot per subagent, IPC plumbing (`task-adapter.sh` + `poll-result.sh`), per-worktree hook installation, ISSUE-88 prompt-overflow class of bugs. Native in-process Task() is strictly better when you have it.
2. **Embedding skill content in seed prompts becomes a maintenance pain.** The plugin shipped ~440 lines of verbatim copies from `superpowers:test-driven-development` + `verification-before-completion`. Every upstream release of superpowers risked drift. `superteam` references the skills by name — they load in-process and update automatically.
3. **Worktree-per-task vs worktree-per-ticket is a real choice.** Per-task (what `isolation: worktree` gives you) forces reviewers to inspect a clean tree, defeating the point. Per-ticket (planner provisions; teammates `cd` into the path from the task description) lets reviewers see the implementer's diff naturally.
4. **Race conditions in shared pane provisioning are real.** ISSUE-72 fix (mkdir-as-lock) was load-bearing. Native task-list self-claim has the same problem and solves it with file locking — same idea, native scope.
5. **The hook-driven lifecycle (ISSUE-66) was the right direction.** Removing the agent → planner `cmux send` push channel in favor of polling result files via `task-adapter.sh` was the cleanest IPC the plugin shipped. Native Agent Teams converges on roughly the same shape (synchronous Agent() return + async messaging via mailbox).
6. **Beta release channel as a staging ground worked.** The three experiments (#100, #102, #109) lived on beta without destabilizing main. Worth keeping for `superteam` as it grows.

## What's left in this repo

Nothing. The code stays as a historical record. No further commits, no further releases. Issues + PRs are read-only via the GitHub Archived flag.

If you want to see the original architecture, browse `skills/cmux-tab-agents/scripts/` and `skills/cmux-tab-agents/references/`. If you want to use the discipline today, install `superteam`.
