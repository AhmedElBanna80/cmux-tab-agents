# Divergences from `superpowers:subagent-driven-development`

This skill is a fork. This page enumerates exactly where it diverges from upstream so a future maintainer can re-sync as upstream evolves.

Upstream version: `superpowers/5.0.7` at the time of fork.
Source files lifted verbatim into this fork are listed inline at the top of each prompt template (see `<!-- copied verbatim ... -->` comments).

## Divergences

### 1. Dispatch primitive

| Upstream | This fork |
|---|---|
| `Agent({...})` (in-process subagent) | `cmux new-surface` + `cmux send` (real `claude` process in a cmux tab) |

The subagent's prompt becomes the seed prompt; we deliver it via `claude --append-system-prompt "$(cat <rendered>.md)"`.

### 2. Return mechanism

| Upstream | This fork |
|---|---|
| Subagent returns a single text blob to the caller | Tab-agent writes a YAML-frontmatter result file in the worktree |

Result file location: `<worktree>/.cmux-<phase>-result.md`. See `reporting-contract.md` for schema.

### 3. Working directory model

| Upstream | This fork |
|---|---|
| All subagents share the controller's working directory | Each task gets its own git worktree at `<base>/<TICKET>/<repo-name>` |

This is the structural shift that unlocks the next divergence.

### 4. Cross-task parallelism (override of upstream rule)

Upstream `subagent-driven-development/SKILL.md` says, in the Red Flags section:

> **Never:** Dispatch multiple implementation subagents in parallel (conflicts)

This fork **overrides** that rule. Because each task has its own worktree, there is no shared working tree to conflict over. The planner MAY dispatch implementers for distinct sub-tasks in parallel.

Constraint that survives: never dispatch multiple implementers into the **same** worktree. One implementer per worktree at a time.

### 5. Hook-bypass prohibition (additive, not in upstream)

Upstream skills don't explicitly forbid `git commit --no-verify` or other hook bypasses. This fork adds an explicit, exhaustive prohibition in every tab-agent prompt (see "Hook-bypass is FORBIDDEN" section), and instructs the spec-reviewer and code-reviewer to scan the implementer's commits for evidence of bypass.

User-driven addition (the user explicitly asked for "never `--no-verify`"). Likely worth proposing back upstream if the maintainers agree.

### 6. Tab lifecycle

| Upstream | This fork |
|---|---|
| Subagent disappears after returning | Tab idles open after writing result file |

The user (or planner) closes tabs manually with `cmux close-surface` once the work is integrated. Two reasons: (1) user can chat with the tab-agent or take over, (2) the tab keeps the seed prompt + scrollback for inspection.

### 7. Three sequential tabs per task (vs. three Agent invocations on shared surface)

The phase ordering is identical to upstream: implementer first, then spec-reviewer, then code-quality-reviewer. The mechanism differs:

- Upstream: three Agent invocations to the same in-process surface.
- This fork: three cmux tabs, in sequence, in the same worktree. Each tab does its work and idles. The next phase opens a new tab — it does not continue the previous one.

Implication: re-running a phase (e.g., re-dispatching implementer after review feedback) means a new tab. The old tabs remain. Workspace can accumulate tabs over a long task; user may close finalized phases manually.

### 8. Status pills, log feed, notifications (additive)

Upstream returns a single text blob. This fork uses cmux sidebar features (`set-status`, `log`, `notify`) so the planner has ambient awareness without parsing transcripts. The status key convention is `<TICKET>-<phase>` and pills are mirrored on both the tab's workspace and the planner's. See `status-conventions.md`.

### 9. `--dangerously-skip-permissions` for tab-agents

Upstream `Agent({...})` runs subagents with the same permissions as the caller. This fork starts each tab-agent's `claude` process with `--dangerously-skip-permissions` because:

1. The worktree is sandboxed (separate git worktree, separate dir).
2. The seed prompt forbids edits outside `{{WORKTREE}}`.
3. Fire-and-forget makes interactive permission prompts useless — there's no human in the loop.

Risk: a compromised seed prompt could do destructive things in the worktree. Mitigation: worktrees are disposable and trivially recreatable.

### 10. Worktree discovery hierarchy (vs. upstream's directory priority)

Upstream `superpowers:using-git-worktrees` has its own priority logic. This fork's `ensure-worktree.sh` replicates the spirit (env var → per-repo config → project-local `.worktrees` if gitignored → sibling default) without invoking the upstream skill. See `configuration.md`.

### 11. Active push channel back to the planner (additive, not in upstream)

| Upstream | This fork |
|---|---|
| Subagent's text blob is the return value; controller waits for it inline | Tab-agent writes a result file (passive) **and** pushes one line into the planner's input box on terminal state (active) |

Upstream's `Agent({...})` is synchronous — the controller blocks on the call and reads the return value when the subagent finishes. This fork's tab-agents are real `claude` processes running asynchronously in cmux tabs; without an active push, the planner has to poll the result file. The active push (one `cmux send` per tab-agent, only on terminal state) inverts that: the planner's input box becomes an inbox of completed work.

Mechanism: each dispatch script auto-detects the dispatcher's `surface_ref` via `cmux identify`, threads it through as `{{PLANNER_SURFACE}}` in the seed prompt, and the seed prompt instructs the tab-agent to do exactly one `cmux send` + `cmux send-key enter` on terminal state (`DONE`/`DONE_WITH_CONCERNS`/`BLOCKED`/`NEEDS_CONTEXT` for implementers, `APPROVED`/`ISSUES_FOUND` for reviewers). Boot-time pushes are explicitly forbidden in the prompts to avoid spamming when the planner fans out N agents in parallel.

Override mechanism: `--planner-surface <ref>` on any dispatch script. Pass `""` to disable the push channel entirely (pure polling). See `configuration.md` and the "How tab-agents talk to you" section of `SKILL.md` for the full protocol, including the security caveat that the planner must always read the cited result file rather than acting on the pushed message body.

### 12. `--model` parity with upstream Model Selection (additive)

Upstream `superpowers:subagent-driven-development` has a "Model Selection" section recommending cheaper/faster models for mechanical sub-tasks (typing, refactoring) and stronger models for ambiguous design work, exposed via the `model` parameter on `Agent({...})`. This fork adds the `--model <model-id>` flag to all three dispatch scripts (and the shared `_dispatch_common.sh`). When passed, it's appended verbatim to the tab-agent's `claude` boot command (`claude --dangerously-skip-permissions --model <id> --append-system-prompt ...`). When omitted, the tab-agent runs on the user's default model — preserving prior behavior.

This brings the fork to per-task model-selection parity with upstream without changing the prompt-level discipline (TDD, verification, hook-bypass prohibition) that the model is bound by.

### 13. Bidirectional planner ↔ agent conversation (v0.2.1, additive)

| Upstream | This fork |
|---|---|
| Subagent return value is one text blob; the controller is the only one who can "reply" by spawning a new subagent | Tab-agent terminal state is a push line, **and** the planner can `cmux send --surface <agent-surface>` to inject a reply into the agent's input box, which the agent's TUI processes as a new user-message turn — no re-spawn needed |

v0.2.0 (#1) added the agent → planner push direction. v0.2.1 documents the reverse direction explicitly: the same `cmux send` primitive lets the planner reply to any tab-agent it has dispatched, turning the one-line push into a real back-and-forth conversation.

Implications:

1. **Push moments are an enumeration, not a single moment.** Implementer prompts now list `NEEDS_CONTEXT` / `BLOCKED` / `DONE_WITH_CONCERNS` / `DONE` as legitimate push moments; reviewer prompts list `APPROVED` / `ISSUES_FOUND`. After every push, the agent idles waiting for the planner's reply and processes it as a new user-message turn. Boot-time pushes remain forbidden (they would spam the planner during fan-out).
2. **For reviewer `ISSUES_FOUND`, the planner has two valid responses** — re-dispatch the implementer (fresh tab, clean context, optionally a different `--model`) or reply directly to the existing implementer's surface (same context, less spawn overhead). Both are documented in `SKILL.md` under "How to talk back to a tab-agent" along with decision criteria.
3. **Reviewers who receive a planner reply must rewrite their result file.** The result file is the source of truth for downstream consumers; if the planner overrode the verdict but the file still says the old verdict, downstream phases will read stale information. The reviewer prompts now spell out the corrected-result-file rule explicitly.
4. **Hard-rule override refusal is documented in both directions.** A planner reply that asks the agent to bypass hooks, skip tests, edit outside the worktree, or soften a hook-bypass finding must be REFUSED by the agent — same discipline, just delivered via a different channel. The agent pushes back with `BLOCKED` (implementer) or `ISSUES_FOUND` (reviewers) and idles for an alternative path or human escalation.
5. **No mechanical changes** to `_dispatch_common.sh` or any script. The channel mechanism was already complete in v0.2.0; v0.2.1 is purely the prompt-level language to *use* it as a conversation, plus the `SKILL.md` planner-side guidance for tracking surfaces and replying.
6. **Mid-flight pushes skip the result file.** Conversational `NEEDS_CONTEXT` / `BLOCKED` (where the agent will continue after the planner replies) push only — no file write. The push line itself carries the question or blocker; no downstream agent reads the file for these states; the file would be overwritten when the agent reaches a true terminal state. Files are still written for terminal `DONE` / `DONE_WITH_CONCERNS` (and final `BLOCKED` / `NEEDS_CONTEXT` when the agent has decided to give up), since reviewers and code-reviewers need them as the source of truth. This eliminates duplicate work for short-lived conversational exchanges without losing the audit trail or the cross-phase contract.

Override mechanism: same as v0.2.0 (`--planner-surface ""` on dispatch disables the channel both ways; the agent won't push and the planner has nowhere documented to reply, falling back to pure polling).

### 14. User-configurable model/effort defaults + `/cmux-tab-agents:setup` (v0.3.0, additive)

v0.2.0 introduced `--model <id>` for per-task model selection. v0.3.0 layers on user and project defaults so model (and effort) selection doesn't require CLI flag noise.

| Feature | Where |
|---|---|
| Resolution order | CLI `--model` / `--effort` > env var `CMUX_TAB_AGENTS_DEFAULT_MODEL` / `CMUX_TAB_AGENTS_DEFAULT_EFFORT` > per-repo `.claude/cmux-tab-agents.toml` keys `default_model` / `default_effort` > user-global `~/.claude/cmux-tab-agents.toml`, same keys > unset |
| Interactive setup | `/cmux-tab-agents:setup` slash command (walks user through model/effort choice, save location, and optional per-repo settings like `worktree_base`) |
| TOML keys | `default_model` (e.g. `claude-sonnet-4-6`) and `default_effort` (e.g. `high`, one of `low` / `medium` / `high` / `xhigh` / `max`) |
| Backward-compatible | Yes — unset defaults yield same behavior as v0.2.0; only env vars or TOML change behavior |
| Bootstrap integration | No script changes; resolution happens in `_dispatch_common.sh`'s `dispatch_main()`, and the resolved values are passed to claude boot as `--model <id> --effort <level>` (omitted if empty) |

Rationale: per-task model selection keeps prompt discipline tight (TDD, verification, hook-bypass prohibition) while letting mechanical work use cheaper models and ambitious work use stronger ones — without flag clutter. Now defaults (via env or config) enable the same choice without flagging every dispatch.

### 15. Verification artifact for reviewers (v0.3.0, additive)

| Upstream | This fork |
|---|---|
| Reviewers always re-run full verification (tests, lint, build, hooks) | Reviewers may optionally reduce re-verification scope if the implementer's verification artifact is fresh and consistent |

The implementer writes a `.cmux-implementer-verification.json` artifact alongside its result file, capturing the results of its own verification commands (tests, lint, build, hooks). The artifact includes the commit sha, a timestamp, and the status of each verification step.

When reading the artifact, reviewers check:
1. Is `implementer_sha` the current HEAD commit?
2. Is `timestamp` recent (within last hour)?
3. Are all status fields `passed` (not `failed` or `skipped`)?

If all three checks pass, reviewers **may** downgrade to spot-checks (subset of tests, skim lint output, confirm hook claim). If any check fails, reviewers perform full re-verification and flag the artifact state as a concern.

**Why:** Implementer verification is expensive—two independent full re-runs on every task (spec-reviewer + code-reviewer) plus more on review loops. The artifact is a hint, not a substitute for skepticism. Reviewers remain in control: full re-run always remains the fallback when anything looks off.

**Honest reporting required:** Implementer must report failed or skipped steps accurately in the artifact; reviewers will full-re-verify if they see failures/omissions.

See `references/reporting-contract.md` for schema and `prompts/implementer-tab-prompt.md` for implementer instructions.

## Re-syncing

When upstream `superpowers/X.Y.Z` ships:

1. `diff` upstream's `subagent-driven-development/SKILL.md` against the section comments referenced in this fork's `SKILL.md`. Forward-port any meaningful changes.
2. `diff` upstream's three prompt templates against this fork's three. Forward-port everything that isn't a cmux-specific shim.
3. `diff` upstream's `test-driven-development/SKILL.md` and `verification-before-completion/SKILL.md` against the verbatim sections in `prompts/implementer-tab-prompt.md`. The marker comments at the top of each verbatim section identify the source path and version.
4. Bump the version comment marker.
5. Update this page if the divergence list changed.
