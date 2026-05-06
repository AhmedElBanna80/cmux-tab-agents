# Divergences from `superpowers:subagent-driven-development`

This skill is a fork. This page enumerates exactly where it diverges from upstream so a future maintainer can re-sync as upstream evolves.

Upstream version: `superpowers/5.0.7` at the time of fork.
Source files lifted verbatim into this fork are listed inline at the top of each prompt template (see `<!-- copied verbatim ... -->` comments).

---

## Design-Intentional Divergences

These divergences represent intentional architectural decisions made when forking from upstream `superpowers:subagent-driven-development`. They define the core structure of cmux-tab-agents and should be carefully considered during any re-sync with upstream.

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

### 6. Idle-open tabs

| Upstream | This fork |
|---|---|
| Subagent disappears after returning | Tab idles open after writing result file |

The user (or planner) closes tabs manually with `cmux close-surface` once the work is integrated. Two reasons: (1) user can chat with the tab-agent or take over, (2) the tab keeps the seed prompt + scrollback for inspection.

### 7. Three sequential tabs per task

The phase ordering is identical to upstream: implementer first, then spec-reviewer, then code-quality-reviewer. The mechanism differs:

- Upstream: three Agent invocations to the same in-process surface.
- This fork: three cmux tabs, in sequence, in the same worktree. Each tab does its work and idles. The next phase opens a new tab — it does not continue the previous one.

Implication: re-running a phase (e.g., re-dispatching implementer after review feedback) means a new tab. The old tabs remain. Workspace can accumulate tabs over a long task; user may close finalized phases manually.

### 8. Status pills

Upstream returns a single text blob. This fork uses cmux sidebar features (`set-status`, `log`, `notify`) so the planner has ambient awareness without parsing transcripts. The status key convention is `<TICKET>-<phase>` and pills are mirrored on both the tab's workspace and the planner's. See `status-conventions.md`.

### 9. `--dangerously-skip-permissions`

Upstream `Agent({...})` runs subagents with the same permissions as the caller. This fork starts each tab-agent's `claude` process with `--dangerously-skip-permissions` because:

1. The worktree is sandboxed (separate git worktree, separate dir).
2. The seed prompt forbids edits outside `{{WORKTREE}}`.
3. Fire-and-forget makes interactive permission prompts useless — there's no human in the loop.

Risk: a compromised seed prompt could do destructive things in the worktree. Mitigation: worktrees are disposable and trivially recreatable.

### 10. Worktree discovery hierarchy

Upstream `superpowers:using-git-worktrees` has its own priority logic. This fork's `ensure-worktree.sh` replicates the spirit (env var → per-repo config → project-local `.worktrees` if gitignored → sibling default) without invoking the upstream skill. See `configuration.md`.

---

## Implementation Drift

These divergences represent features and implementation details that emerged during development. They may be less stable than design-intentional divergences and should be reviewed more carefully during re-sync — some may be subsumed by upstream changes, others may reveal genuine improvements worth proposing back.

### 1. Verification iron law embedded in reviewer prompts

**Description:** Upstream `verification-before-completion/SKILL.md` defines the iron law for verification discipline. This fork embeds the same language directly into `spec-reviewer-tab-prompt.md` and `code-reviewer-tab-prompt.md` seed prompts, making verification expectations explicit to the reviewers without requiring a separate skill read.

**Where:** 
- `prompts/spec-reviewer-tab-prompt.md` (search "Verification Before Completion")
- `prompts/code-reviewer-tab-prompt.md` (search "Verification Before Completion")

### 2. Hook-bypass scan in reviewer prompts

**Description:** Reviewers are explicitly instructed to scan the implementer's commit messages and git logs for signs of hook bypass (`--no-verify`, `HUSKY=0`, `LEFTHOOK=0`, etc.). This is an additional safeguard beyond the implementer's discipline — catching any bypass that slipped through.

**Where:**
- `prompts/spec-reviewer-tab-prompt.md` (search "hook bypass" or "pre-commit")
- `prompts/code-reviewer-tab-prompt.md` (search "hook bypass")
- `references/discipline.md` (section "Hook-bypass is FORBIDDEN")

### 3. `--model` flag for per-phase model selection

**Description:** All three dispatch scripts accept a `--model <model-id>` flag to override the user's default model on a per-task basis. This allows mechanical tasks to use cheaper models and ambitious work to use stronger ones, without coupling the choice to individual prompts.

**Where:**
- `scripts/dispatch-implementer.sh` (argument parsing, line ~30)
- `scripts/dispatch-spec-reviewer.sh` (argument parsing, line ~30)
- `scripts/dispatch-code-reviewer.sh` (argument parsing, line ~30)
- `scripts/_dispatch_common.sh` (resolution and model export, `dispatch_main()` function)

### 4. Lifecycle hooks own pill / log / notify (replaces agent→planner push)

**Description:** Each tab-agent's worktree has a generated `.claude/settings.json` registering three hooks: `SessionStart` sets the working pill and logs the phase start; `PostToolUse` (async) appends a JSONL event to `.cmux-events.jsonl`; `Stop` flips the pill to the agent's terminal status, fires `cmux notify`, and writes a minimal `status: BLOCKED` stub if the agent crashed before authoring its result file. The agent prompt remains the canonical author of result-file body and schema — Stop is a safety net, not the primary author.

This replaces the previous active-push channel: tab-agents no longer `cmux send` a terminal-state line into the planner's input box. The planner blocks via `task-adapter.sh` (which wraps dispatch + `poll-result.sh`) and reads the result file directly. The reviewer→implementer push on `LEAD_SURFACE` is unchanged — it's the task-lead loop's coordination channel.

**Where:**
- `hooks/session_start.sh`, `hooks/post_tool_use.sh`, `hooks/stop.sh`, `hooks/lib_hook_common.sh`
- `scripts/install-tab-hooks.sh` (writes the worktree's `.claude/settings.json` at dispatch time)
- `scripts/task-adapter.sh` (planner-side sync wrapper)
- `scripts/_dispatch_common.sh` (writes `.cmux-state/dispatch.json` and calls `install-tab-hooks.sh` before booting `claude`)
- All three seed prompts (planner-targeted `cmux send` calls removed; pill/log/notify references removed from boot sequence)

`--planner-surface` on dispatch scripts is now a no-op preserved for one release of backward compatibility.

### 5. Implementer drives spec/code review without planner loop

**Description:** The implementer seed prompt includes a task-lead section allowing the implementer to auto-dispatch spec-reviewer and code-reviewer surfaces on terminal state (with `--lead-surface` flag), creating a self-contained review loop. The planner optionally monitors via status pills and result files.

**Where:**
- `prompts/implementer-tab-prompt.md` (search "Task lead setup" or "auto-dispatch")
- `scripts/dispatch-implementer.sh` (accepts `--lead-surface` flag)
- `scripts/_dispatch_common.sh` (threads lead surface through template substitution)

### 6. `--finish-mode` flag for automated task completion

**Description:** The implementer script accepts `--finish-mode` to enable automated post-review task completion. When this flag is set, a finish script runs after code-reviewer approval, packaging the result and marking the task done without manual planner intervention.

**Where:**
- `scripts/dispatch-implementer.sh` (argument parsing, search `--finish-mode`)
- `scripts/finish-task.sh` (automation script that runs post-review)

### 7. `{{SKILL_BASE}}` placeholder for discipline.md resolution

**Description:** Seed prompts read `discipline.md` from `{{SKILL_BASE}}/references/discipline.md` instead of the worktree path. This allows cmux-tab-agents to be used from consumer repos where the skill isn't installed locally. The placeholder resolves to the installed skill directory at dispatch time.

**Where:**
- All three seed prompts (boot sequence, step 1: read discipline from `{{SKILL_BASE}}`)
- `scripts/_dispatch_common.sh` (computes and exports `SKILL_BASE`)
- `scripts/dev/render-prompt.sh` (dev rendering includes SKILL_BASE allowlist)

### 8. Result file size caps to prevent context bloat

**Description:** Result files are capped at ≤200 lines (excluding YAML frontmatter). Verbose output (test logs, build traces, diffs) must be written to sibling files (e.g., `.cmux-implementer-verification.txt`) and referenced from the result. This prevents large output from consuming downstream context.

**Where:**
- `references/reporting-contract.md` (section "Result file size limits")
- All three seed prompts (final step: self-check file size before completion)
- `skills/cmux-tab-agents/references/discipline.md` (hard rule in "Hard Rules")

### 9. Skip-trivial-review heuristic for code-reviewer

**Description:** Code-reviewer can be skipped for diffs ≤30 lines that are test-only, doc-only, or changelog-only changes. A helper script automates the decision; planner can conditionally dispatch only spec-reviewer for trivial changes.

**Where:**
- `scripts/should-skip-code-review.sh` (heuristic implementation)
- `references/skip-heuristics.md` (decision criteria and examples)

### 10. Different SKILL.md workflow examples

**Description:** The SKILL.md examples assume a worktree-based workflow (dispatch distinct tabs in sequence, read result files, push to planner). Upstream examples assume in-process Agent invocations (synchronous return, shared context). Examples are not part of upstream verbatim sections and should be reviewed during re-sync.

**Where:**
- `SKILL.md` (entire planner-side guidance section, examples in "Typical workflows")
- Upstream comparison: `superpowers:subagent-driven-development/SKILL.md` examples section

---

## Re-syncing with Upstream

When upstream `superpowers/X.Y.Z` ships, follow this procedure to assess and forward-port changes:

**Stage 1: Design-intentional divergences**

1. `diff` upstream's `subagent-driven-development/SKILL.md` against the section comments referenced in this fork's `SKILL.md`. Forward-port any meaningful changes to the fork's SKILL.md.
2. `diff` upstream's three prompt templates (`implementer-tab-prompt.md`, `spec-reviewer-tab-prompt.md`, `code-reviewer-tab-prompt.md`) against this fork's three. Forward-port everything that isn't a cmux-specific shim (i.e., forward-port discipline updates, but keep the `{{WORKTREE}}` paths, result-file contract, and push protocol).
3. `diff` upstream's `test-driven-development/SKILL.md` and `verification-before-completion/SKILL.md` against the verbatim sections in this fork's `prompts/implementer-tab-prompt.md`. The marker comments at the top of each verbatim section (`<!-- Verbatim from superpowers ... -->`) identify the source path and version. Forward-port any discipline updates.
4. Bump the version comment marker in the verbatim sections if anything changed.

**Stage 2: Implementation drift**

Review each item in the "Implementation Drift" section above:

- Items 1-2 (verification, hook-bypass): These embed discipline from upstream. If upstream discipline changes, update both the embedded language and `references/discipline.md`.
- Items 3-6 (model, push, lead-surface, finish-mode): These are cmux-specific features. Unlikely to conflict with upstream; keep as-is unless upstream adds equivalent capabilities.
- Item 7 (SKILL_BASE): Resolution logic in `_dispatch_common.sh`. Keep as-is unless upstream changes how skills resolve paths.
- Items 8-9 (result file caps, skip heuristic): New constraints. Check if upstream adopts similar limits; if so, align.
- Item 10 (SKILL.md examples): Compare with upstream examples. Update to match upstream structure, but preserve worktree-workflow assumptions.

**Stage 3: Update this page**

- Renumber design-intentional divergences if items shift.
- Add or remove implementation-drift items if the picture changes.
- Update the "Upstream version" marker at the top.
