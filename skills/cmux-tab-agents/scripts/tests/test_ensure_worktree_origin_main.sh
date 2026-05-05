#!/usr/bin/env bash
# Test ensure-worktree.sh branches from origin/main instead of stale local main
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENSURE_WT="$SCRIPTS_DIR/ensure-worktree.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ensure-worktree.sh origin/main tests ===\n\n'

# T1: Syntax check
if bash -n "$ENSURE_WT" 2>/dev/null; then
  pass "bash -n ensure-worktree.sh"
else
  fail "bash -n ensure-worktree.sh (syntax error)"
  exit 1
fi

# T2: Test branching from origin/main when local main is stale
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir" || exit 1

# Create initial repo with commit 1
initial_repo="$tmpdir/initial"
git init -q -b main "$initial_repo"
cd "$initial_repo"
git config user.email "test@example.com"
git config user.name "Test User"
touch file1.txt
git add file1.txt
git commit -q -m "commit 1"
commit1=$(git rev-parse HEAD)

# Create bare repo as origin
bare_repo="$tmpdir/origin.git"
git clone -q --bare . "$bare_repo"

# Clone to get a working copy
local_repo="$tmpdir/repo"
git clone -q "$bare_repo" "$local_repo"
cd "$local_repo"
git config user.email "test@example.com"
git config user.name "Test User"

# Now push additional commits from the initial_repo to origin
cd "$initial_repo"
touch file2.txt
git add file2.txt
git commit -q -m "commit 2"
commit2=$(git rev-parse HEAD)
git push -q "$bare_repo" main

# Go back to local_repo and fetch (without pulling)
cd "$local_repo"
git fetch -q origin

# Verify local main is behind origin/main
local_main=$(git rev-parse main)
origin_main=$(git rev-parse origin/main)

if [[ "$local_main" == "$commit1" ]] && [[ "$origin_main" == "$commit2" ]]; then
  pass "local main is stale, behind origin/main"
else
  fail "failed to set up stale main scenario (local=$local_main, origin=$origin_main, expect local=$commit1, origin=$commit2)"
  exit 1
fi

# Create worktree base directory
wt_base="$tmpdir/worktrees"
mkdir -p "$wt_base"

# Call ensure-worktree.sh
wt_path=$("$ENSURE_WT" --ticket TEST-1 --slug test-slug --type feat 2>/dev/null || echo "")

if [[ -z "$wt_path" ]]; then
  fail "ensure-worktree.sh failed to create worktree"
  exit 1
fi

if ! [[ -d "$wt_path" ]]; then
  fail "worktree path does not exist: $wt_path"
  exit 1
fi

pass "worktree created successfully"

# Check that the worktree is based on origin/main (commit2), not stale local main (commit1)
wt_head=$(cd "$wt_path" && git rev-parse HEAD)

if [[ "$wt_head" == "$commit2" ]]; then
  pass "worktree is based on origin/main (fresh commit)"
elif [[ "$wt_head" == "$commit1" ]]; then
  fail "worktree is based on stale local main (should be origin/main)"
else
  fail "worktree HEAD is unexpected: $wt_head (expected $commit2 or $commit1)"
fi

# Summary
printf '\n=== Results ===\n'
printf 'PASS: %d\n' "$PASS"
printf 'FAIL: %d\n' "$FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
