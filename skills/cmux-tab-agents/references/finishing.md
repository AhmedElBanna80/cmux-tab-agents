# Finish Modes — Post-Review Task Completion

When code review is complete (both spec-reviewer and code-reviewer approve), the implementer tab uses `--finish-mode` to determine what to do with the branch and worktree.

## Quick Reference

| Mode   | Action                                | Worktree | Use Case |
|--------|---------------------------------------|----------|----------|
| `keep` | Nope (default)                        | Kept     | Safe default; let planner decide |
| `pr`   | Push + open PR, return URL            | Kept     | Automated PR creation |
| `merge`| Merge to base, test, clean worktree  | Removed  | Automated merge to main |
| `discard` | Rejected at dispatch               | N/A      | Interactive-only; use skill |

## Modes Detailed

### `keep` (default)

**What it does:** Nothing. Leaves the branch and worktree intact, ready for manual next steps.

**Exit behavior:**
- Worktree stays in place
- Branch remains unpushed (or pushed if implementer pushed manually)
- No PR opened

**When to use:** Safe default. When unsure whether to automate the finish step, use `keep` and let the planner decide later via `superpowers:finishing-a-development-branch`.

**Example dispatch:**
```bash
dispatch-implementer.sh \
  --ticket ISSUE-123 \
  --title "Add login flow" \
  --slug add-login-flow \
  --task-text "..." \
  # (no --finish-mode, defaults to keep)
```

---

### `pr` (automated PR opening)

**What it does:**
1. Verifies tests pass (verification gate)
2. Pushes branch to origin
3. Opens a PR via `gh pr create`
4. Auto-closes the issue if branch matches pattern `feat/ISSUE-NNN/...` or similar
5. Returns PR URL

**Exit behavior:**
- Worktree stays in place (can re-run tests, inspect code, etc.)
- Branch is pushed to origin
- PR is created (idempotent: re-running returns existing PR URL)
- Issue auto-closes when PR merges

**When to use:** When you want to automate the "push + open PR" step but keep the worktree for manual review or iteration.

**Example dispatch:**
```bash
dispatch-implementer.sh \
  --ticket ISSUE-123 \
  --title "Add login flow" \
  --slug add-login-flow \
  --task-text "..." \
  --finish-mode pr
```

**PR body template:**
```markdown
Resolves #NNN
```

If the branch name contains an issue number (e.g., `feat/ISSUE-123/add-login`), the PR body will include `Resolves #123`, which GitHub will auto-close when merged.

**Idempotency:** If the branch is already pushed and a PR already exists, re-running returns the existing PR URL without error.

---

### `merge` (automated merge to base)

**What it does:**
1. Verifies tests pass (verification gate)
2. Checks out the base branch (default: `main`)
3. Pulls latest from origin
4. Merges feature branch (using `git merge --no-ff`)
5. Re-runs tests on merged code
6. If green: removes the worktree
7. If tests fail: reverts merge and exits with error

**Exit behavior:**
- Worktree is **removed** on success
- Feature branch is merged to base
- Code is ready to deploy (all tests pass post-merge)

**When to use:** Fully automated finish. The task is review-complete and ready to merge to main without human intervention.

**Example dispatch:**
```bash
dispatch-implementer.sh \
  --ticket ISSUE-123 \
  --title "Add login flow" \
  --slug add-login-flow \
  --task-text "..." \
  --finish-mode merge
```

**Failure modes:**
- **Merge conflict:** Aborts merge, exits with error. Planner can re-dispatch with `--finish-mode keep` and resolve manually.
- **Tests fail post-merge:** Reverts merge, exits with error. Indicates the branch isn't compatible with current main (CI environment, dependency changes, etc.).

**Idempotency:** If branch is already merged, re-running detects this and exits cleanly (idempotent). If merge is half-done, re-running completes or fails cleanly.

---

### `discard` (interactive only)

**What it does:** Nothing. Rejected at dispatch time.

**Why:** `discard` (delete branch, remove worktree) is a destructive operation that requires human confirmation. Use the interactive `superpowers:finishing-a-development-branch` skill instead, which prompts for confirmation.

**Error at dispatch:**
```
dispatch-implementer.sh: --finish-mode discard is not supported at dispatch time. 
Use superpowers:finishing-a-development-branch interactively instead.
```

**When to use:** Never pass `--finish-mode discard` to `dispatch-implementer.sh`. Instead:
1. After code review, run `superpowers:finishing-a-development-branch` manually in the planner tab
2. Choose `discard` there (you'll be prompted for confirmation)
3. The skill will delete the branch and remove the worktree

---

## Interaction with Verification Gate

**Before any mode action**, `finish-task.sh` runs a verification gate:

```
1. Detect test command (npm test, make test, pytest, go test, etc.)
2. Run tests
3. If tests fail → abort (exit non-zero, no finish action taken)
4. If tests pass → proceed to mode-specific action
```

This ensures only green code is pushed/merged, regardless of finish mode.

If test detection fails, the script logs a warning and proceeds (fail-open, not fail-safe). To enforce tests strictly, ensure your project has a recognized test command.

---

## Base Branch

The `merge` mode defaults to `main` as the base branch. To merge to a different branch, set the environment variable `GIT_BASE_BRANCH`:

```bash
GIT_BASE_BRANCH=develop dispatch-implementer.sh \
  --ticket ISSUE-123 \
  ... \
  --finish-mode merge
```

---

## Planner Workflow

When dispatching an implementer with finish mode:

1. **`keep` (default):** Safe. Task is done, but planner decides the finish step later.
   ```
   dispatch-implementer.sh ... (no --finish-mode)
   # After code review approves:
   # Use superpowers:finishing-a-development-branch manually
   ```

2. **`pr`:** Automated PR opening. Planner reviews PR.
   ```
   dispatch-implementer.sh ... --finish-mode pr
   # After code review approves:
   # PR is already open, planner can review/merge in GitHub
   ```

3. **`merge`:** Fully automated. Planner confirms result file (DONE), code is merged.
   ```
   dispatch-implementer.sh ... --finish-mode merge
   # After code review approves:
   # Result file shows DONE, code is in main, worktree cleaned up
   ```

---

## Edge Cases and Troubleshooting

**PR mode: PR already exists (idempotent)**
- Re-running with `--finish-mode pr` detects existing PR and returns URL without re-opening

**Merge mode: Branch already merged (idempotent)**
- Re-running with `--finish-mode merge` detects merge and cleans up worktree

**Merge mode: Merge conflict**
- Detected, merge aborted, error reported
- Planner can re-dispatch with `--finish-mode keep` and resolve manually

**Merge mode: Tests fail post-merge**
- Tests pass before merge ✓
- Merge succeeds ✓
- Tests fail on merged code ✗
- Merge is automatically reverted
- Error reported; planner investigates why merge broke tests (CI env, dependency issues, etc.)

**Verification gate: Tests can't be detected**
- Script logs WARNING and proceeds (fail-open)
- Ensure your project has a recognized test command to enforce testing strictly
