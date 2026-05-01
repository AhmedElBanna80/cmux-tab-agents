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

## Re-syncing

When upstream `superpowers/X.Y.Z` ships:

1. `diff` upstream's `subagent-driven-development/SKILL.md` against the section comments referenced in this fork's `SKILL.md`. Forward-port any meaningful changes.
2. `diff` upstream's three prompt templates against this fork's three. Forward-port everything that isn't a cmux-specific shim.
3. `diff` upstream's `test-driven-development/SKILL.md` and `verification-before-completion/SKILL.md` against the verbatim sections in `prompts/implementer-tab-prompt.md`. The marker comments at the top of each verbatim section identify the source path and version.
4. Bump the version comment marker.
5. Update this page if the divergence list changed.
