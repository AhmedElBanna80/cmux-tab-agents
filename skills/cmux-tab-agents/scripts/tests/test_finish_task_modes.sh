#!/usr/bin/env bash
# Integration tests for finish-task.sh modes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FINISH_TASK="$SCRIPTS_DIR/finish-task.sh"

PASS=0
FAIL=0
SKIP=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIP=$((SKIP+1)); }

printf '=== finish-task.sh integration tests ===\n\n'

# T1: Syntax check
if bash -n "$FINISH_TASK" 2>/dev/null; then
  pass "bash -n finish-task.sh"
else
  fail "bash -n finish-task.sh (syntax error)"
  exit 1
fi

# T2: Usage message
out=$("$FINISH_TASK" -h 2>&1 || true)
if printf '%s' "$out" | grep -q "Usage:"; then
  pass "finish-task.sh shows usage on -h"
else
  fail "finish-task.sh usage message missing"
fi

# T3: Invalid mode rejected
out=$("$FINISH_TASK" invalid 2>&1 || true)
if printf '%s' "$out" | grep -qiE "invalid|mode"; then
  pass "invalid mode is rejected"
else
  fail "invalid mode not rejected: $out"
fi

# T4: keep mode with valid worktree (noop)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir" || exit 1
git init -q .
touch test.txt
git add test.txt
git commit -q -m "initial"

out=$("$FINISH_TASK" keep "$tmpdir" 2>&1)
if printf '%s' "$out" | grep -q "noop"; then
  pass "keep mode is noop"
else
  fail "keep mode didn't report noop: $out"
fi

# T5: Invalid worktree rejected
out=$("$FINISH_TASK" keep /nonexistent/path 2>&1 || true)
if printf '%s' "$out" | grep -qiE "cannot|not found|no such"; then
  pass "nonexistent worktree is rejected"
else
  fail "nonexistent worktree not rejected: $out"
fi

# T6: pr mode with mock gh
# Create temp directory with mock gh
mock_tmpdir=$(mktemp -d)
trap 'rm -rf "$mock_tmpdir"' EXIT

# Create mock gh binary
mkdir -p "$mock_tmpdir/mock-gh"
cat > "$mock_tmpdir/mock-gh/gh" <<'MOCKGH'
#!/usr/bin/env bash
# Mock gh binary for testing
case "$*" in
  *"pr view"*)
    # Return error (no existing PR)
    echo "no pull requests found" >&2
    exit 1
    ;;
  *"pr create"*)
    # Return fake PR URL
    echo "https://github.com/test/repo/pull/42"
    exit 0
    ;;
  *)
    echo "unknown command: $@" >&2
    exit 1
    ;;
esac
MOCKGH
chmod +x "$mock_tmpdir/mock-gh/gh"

# Set up pr mode test with mock gh in PATH
pr_test_tmpdir=$(mktemp -d)
trap 'rm -rf "$pr_test_tmpdir"' EXIT
cd "$pr_test_tmpdir" || exit 1

# Initialize git repo
git init -q .
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin https://github.com/test/repo.git

# Create initial commit
echo "test" > file.txt
git add file.txt
git commit -q -m "initial"

# Create feature branch
git checkout -q -b feat/ISSUE-42/test
echo "feature" >> file.txt
git add file.txt
git commit -q -m "add feature"

# Run finish-task with pr mode using mock gh
export PATH="$mock_tmpdir/mock-gh:$PATH"
out=$("$FINISH_TASK" pr "$pr_test_tmpdir" 2>&1)
if printf '%s' "$out" | grep -q "https://github.com/test/repo/pull/42"; then
  pass "pr mode creates PR and returns URL with mock gh"
else
  fail "pr mode didn't return PR URL: $out"
fi

# T7: merge mode with throwaway worktree
merge_test_tmpdir=$(mktemp -d)
trap 'rm -rf "$merge_test_tmpdir"' EXIT

# Create main repo
main_repo="$merge_test_tmpdir/main"
mkdir -p "$main_repo"
cd "$main_repo" || exit 1
git init -q .
git config user.email "test@example.com"
git config user.name "Test User"
touch init.txt
git add init.txt
git commit -q -m "initial"

# Create feature branch
git checkout -q -b feat/ISSUE-43/test
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"

# Create a worktree (simulating what the implementer would have)
worktree_dir="$merge_test_tmpdir/worktree"
git worktree add -q "$worktree_dir" feat/ISSUE-43/test

# Switch back to main
git checkout -q main

# Run merge mode (should remove the worktree)
out=$("$FINISH_TASK" merge "$worktree_dir" 2>&1)

# Verify worktree was removed
if ! git worktree list | grep -q "$worktree_dir"; then
  pass "merge mode cleans up worktree"
else
  fail "merge mode didn't remove worktree"
fi

# T8: Verify finish-task.sh is idempotent (can be called multiple times)
# For keep mode, should always succeed
out1=$("$FINISH_TASK" keep "$tmpdir" 2>&1)
out2=$("$FINISH_TASK" keep "$tmpdir" 2>&1)
if [[ "$out1" == "$out2" ]]; then
  pass "keep mode is idempotent (same output on re-run)"
else
  fail "keep mode output differs on re-run"
fi

# T9: finish-task.sh handles missing test command gracefully
skip_test_tmpdir=$(mktemp -d)
trap 'rm -rf "$skip_test_tmpdir"' EXIT
cd "$skip_test_tmpdir" || exit 1
git init -q .
touch test.txt
git add test.txt
git commit -q -m "initial"

# No test command defined, finish-task should warn and continue
out=$("$FINISH_TASK" keep "$skip_test_tmpdir" 2>&1)
if printf '%s' "$out" | grep -qiE "warning|could not|skip"; then
  pass "missing test command triggers warning, continues"
else
  fail "missing test command handling unclear: $out"
fi

# T10: tests-fail-aborts — finish-task.sh exits non-zero when tests fail
# Tests the verification gate: if tests fail, finish-task.sh should abort without action
fail_test_tmpdir=$(mktemp -d)
trap 'rm -rf "$fail_test_tmpdir"' EXIT
cd "$fail_test_tmpdir" || exit 1

# Create a repo with a failing test
git init -q .
git config user.email "test@example.com"
git config user.name "Test User"

# Create package.json with a test script that fails
cat > package.json <<EOF
{
  "name": "test-repo",
  "version": "1.0.0",
  "scripts": {
    "test": "exit 1"
  }
}
EOF

touch file.txt
git add package.json file.txt
git commit -q -m "initial with failing test"

# Call finish-task.sh keep mode with failing tests
out=$("$FINISH_TASK" keep "$fail_test_tmpdir" 2>&1)
exit_code=$?

# Verify it exits non-zero
if [[ $exit_code -ne 0 ]]; then
  pass "tests-fail-aborts: finish-task exits non-zero when tests fail"
else
  fail "tests-fail-aborts: finish-task should exit non-zero, got exit code $exit_code"
fi

# Verify error message mentions test failure
if printf '%s' "$out" | grep -qiE "failed|abort"; then
  pass "tests-fail-aborts: error message indicates test failure"
else
  fail "tests-fail-aborts: error message missing test failure indicator: $out"
fi

printf '\n=== Results: %d passed, %d failed, %d skipped ===\n' "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
