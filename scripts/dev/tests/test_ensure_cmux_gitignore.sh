#!/usr/bin/env bash
# Tests for _ensure_cmux_gitignore() in _dispatch_common.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DISPATCH_COMMON="$REPO_ROOT/skills/cmux-tab-agents/scripts/_dispatch_common.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== _ensure_cmux_gitignore tests ===\n\n'

# T1: bash syntax check
if bash -n "$DISPATCH_COMMON" 2>/dev/null; then
  pass "bash -n _dispatch_common.sh"
else
  fail "bash -n _dispatch_common.sh (syntax error)";
fi

# T2: _ensure_cmux_gitignore function exists
out=$(bash -c ". '$DISPATCH_COMMON'; declare -f _ensure_cmux_gitignore" 2>&1)
if printf '%s' "$out" | grep -q '_ensure_cmux_gitignore'; then
  pass "_ensure_cmux_gitignore is defined"
else
  fail "_ensure_cmux_gitignore not defined after sourcing";
fi

# T3: _ensure_cmux_gitignore creates .gitignore if missing
tmpdir=$(mktemp -d)
trap "rm -rf '$tmpdir'" EXIT
out=$(bash -c ". '$DISPATCH_COMMON'; _ensure_cmux_gitignore '$tmpdir'" 2>&1); rc=$?
if [[ $rc -eq 0 && -f "$tmpdir/.gitignore" ]]; then
  pass "_ensure_cmux_gitignore creates .gitignore when missing"
else
  fail "_ensure_cmux_gitignore: rc=$rc, .gitignore exists=$([[ -f "$tmpdir/.gitignore" ]] && echo yes || echo no)";
fi

# T4: _ensure_cmux_gitignore adds .cmux-* pattern
if grep -qF '.cmux-*' "$tmpdir/.gitignore"; then
  pass "_ensure_cmux_gitignore adds .cmux-* to .gitignore"
else
  fail "_ensure_cmux_gitignore: .cmux-* pattern not in .gitignore";
fi

# T5: _ensure_cmux_gitignore adds .cmux-tab-prompt-*.md pattern
if grep -qF '.cmux-tab-prompt-*.md' "$tmpdir/.gitignore"; then
  pass "_ensure_cmux_gitignore adds .cmux-tab-prompt-*.md to .gitignore"
else
  fail "_ensure_cmux_gitignore: .cmux-tab-prompt-*.md pattern not in .gitignore";
fi

# T6: _ensure_cmux_gitignore is idempotent (doesn't duplicate)
bash -c ". '$DISPATCH_COMMON'; _ensure_cmux_gitignore '$tmpdir'" 2>&1
pattern_count=$(grep -c '.cmux-\*' "$tmpdir/.gitignore" 2>/dev/null || echo 0)
if [[ "$pattern_count" -eq 1 ]]; then
  pass "_ensure_cmux_gitignore is idempotent (no duplicate .cmux-* entries)"
else
  fail "_ensure_cmux_gitignore: found $pattern_count .cmux-* entries (expected 1)";
fi

# T7: _ensure_cmux_gitignore succeeds on existing .gitignore with pattern
tmpdir2=$(mktemp -d)
trap "rm -rf '$tmpdir' '$tmpdir2'" EXIT
echo '.cmux-*' > "$tmpdir2/.gitignore"
out=$(bash -c ". '$DISPATCH_COMMON'; _ensure_cmux_gitignore '$tmpdir2'" 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then
  pass "_ensure_cmux_gitignore succeeds when pattern already exists"
else
  fail "_ensure_cmux_gitignore: rc=$rc when pattern exists";
fi

# T8: _ensure_cmux_gitignore adds both patterns when only one exists
echo '.cmux-*' > "$tmpdir2/.gitignore"
bash -c ". '$DISPATCH_COMMON'; _ensure_cmux_gitignore '$tmpdir2'" 2>&1
if grep -qF '.cmux-tab-prompt-*.md' "$tmpdir2/.gitignore"; then
  pass "_ensure_cmux_gitignore adds second pattern when one exists"
else
  fail "_ensure_cmux_gitignore: missing .cmux-tab-prompt-*.md when .cmux-* exists";
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
