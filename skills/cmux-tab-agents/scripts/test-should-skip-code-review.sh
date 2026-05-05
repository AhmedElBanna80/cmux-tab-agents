#!/usr/bin/env bash
# Test suite for should-skip-code-review.sh
# Tests the heuristic for skipping code-quality review on trivial diffs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/should-skip-code-review.sh"

# Test helpers
pass() { echo "✓ $1"; }
fail() { echo "✗ $1"; exit 1; }
assert_exit_code() {
  local expected=$1 actual=$2 msg=$3
  [[ $actual -eq $expected ]] || fail "$msg (expected $expected, got $actual)"
}

# Create a temporary test worktree
setup_test_worktree() {
  local test_dir="/tmp/test-skip-review-$$"
  mkdir -p "$test_dir"
  cd "$test_dir"

  # Initialize a git repo
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "initial" > README.md
  git add README.md
  git commit -q -m "initial commit"

  echo "$test_dir"
}

cleanup_test_worktree() {
  local test_dir=$1
  rm -rf "$test_dir"
}

# Test 1: Trivial test-only diff should skip
test_trivial_test_only_diff() {
  local WT
  WT=$(setup_test_worktree)
  cd "$WT"

  # Create a small test-only diff (≤ 30 lines)
  cat > app.test.js << 'EOF'
describe('app', () => {
  it('should work', () => {
    expect(true).toBe(true);
  });
});
EOF
  git add app.test.js
  git commit -q -m "add test"
  local IMPL_SHA
  IMPL_SHA=$(git rev-parse HEAD)

  # Create spec-reviewer result: APPROVED
  cat > .cmux-spec-reviewer-result.md << 'EOF'
---
ticket: TEST-1
phase: spec-reviewer
status: APPROVED
implementer_sha: abc123
---
## Verdict
Looks good.
EOF

  # Test the script
  if "$SCRIPT" --worktree "$WT" --implementer-sha "$IMPL_SHA" 2>/dev/null; then
    pass "trivial test-only diff → should skip"
  else
    fail "trivial test-only diff should return exit 0"
  fi

  cleanup_test_worktree "$WT"
}

# Test 2: Large diff should NOT skip
test_large_diff_no_skip() {
  local WT
  WT=$(setup_test_worktree)
  cd "$WT"

  # Create a large diff (> 30 lines)
  cat > app.js << 'EOF'
function main() {
  console.log('line 1');
  console.log('line 2');
  console.log('line 3');
  console.log('line 4');
  console.log('line 5');
  console.log('line 6');
  console.log('line 7');
  console.log('line 8');
  console.log('line 9');
  console.log('line 10');
  console.log('line 11');
  console.log('line 12');
  console.log('line 13');
  console.log('line 14');
  console.log('line 15');
  console.log('line 16');
  console.log('line 17');
  console.log('line 18');
  console.log('line 19');
  console.log('line 20');
  console.log('line 21');
  console.log('line 22');
  console.log('line 23');
  console.log('line 24');
  console.log('line 25');
  console.log('line 26');
  console.log('line 27');
  console.log('line 28');
  console.log('line 29');
  console.log('line 30');
  console.log('line 31');
}

main();
EOF
  git add app.js
  git commit -q -m "add main logic"
  local IMPL_SHA
  IMPL_SHA=$(git rev-parse HEAD)

  # Create spec-reviewer result: APPROVED
  cat > .cmux-spec-reviewer-result.md << 'EOF'
---
ticket: TEST-2
phase: spec-reviewer
status: APPROVED
implementer_sha: abc123
---
## Verdict
Looks good.
EOF

  # Test the script
  if "$SCRIPT" --worktree "$WT" --implementer-sha "$IMPL_SHA" 2>/dev/null; then
    fail "large diff should NOT skip (should return exit 1)"
  else
    pass "large diff → should NOT skip"
  fi

  cleanup_test_worktree "$WT"
}

# Test 3: Spec-reviewer with concerns should NOT skip
test_spec_reviewer_with_concerns_no_skip() {
  local WT
  WT=$(setup_test_worktree)
  cd "$WT"

  # Create a small test-only diff
  cat > app.test.js << 'EOF'
describe('app', () => {
  it('should work', () => {
    expect(true).toBe(true);
  });
});
EOF
  git add app.test.js
  git commit -q -m "add test"
  local IMPL_SHA
  IMPL_SHA=$(git rev-parse HEAD)

  # Create spec-reviewer result: APPROVED with concerns
  cat > .cmux-spec-reviewer-result.md << 'EOF'
---
ticket: TEST-3
phase: spec-reviewer
status: APPROVED
implementer_sha: abc123
---
## Verdict
Code works but needs attention.

## Missing requirements
- Should add more test cases
EOF

  # Test the script
  if "$SCRIPT" --worktree "$WT" --implementer-sha "$IMPL_SHA" 2>/dev/null; then
    fail "spec-reviewer with concerns should NOT skip"
  else
    pass "spec-reviewer with concerns → should NOT skip"
  fi

  cleanup_test_worktree "$WT"
}

# Test 4: Markdown/doc-only trivial diff should skip
test_markdown_only_diff() {
  local WT
  WT=$(setup_test_worktree)
  cd "$WT"

  # Create a small markdown-only diff
  mkdir -p docs
  cat > docs/guide.md << 'EOF'
# Guide

This is a guide.

It has multiple lines.

So that it's definitely content.

But still under 30 lines.
EOF
  git add docs/guide.md
  git commit -q -m "add docs"
  local IMPL_SHA
  IMPL_SHA=$(git rev-parse HEAD)

  # Create spec-reviewer result: APPROVED
  cat > .cmux-spec-reviewer-result.md << 'EOF'
---
ticket: TEST-4
phase: spec-reviewer
status: APPROVED
implementer_sha: abc123
---
## Verdict
Good documentation.
EOF

  # Test the script
  if "$SCRIPT" --worktree "$WT" --implementer-sha "$IMPL_SHA" 2>/dev/null; then
    pass "markdown-only diff → should skip"
  else
    fail "markdown-only diff should return exit 0"
  fi

  cleanup_test_worktree "$WT"
}

# Run all tests
echo "Running tests for should-skip-code-review.sh"
test_trivial_test_only_diff
test_large_diff_no_skip
test_spec_reviewer_with_concerns_no_skip
test_markdown_only_diff

echo ""
echo "All tests passed!"
