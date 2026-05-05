#!/usr/bin/env bash
# Test model defaults for dispatch scripts (ISSUE-18)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_ROOT="$(cd "$REPO_ROOT/skills/cmux-tab-agents" && pwd)"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

check_exit_zero() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"
  else fail "$label (expected exit 0)"; fi
}

check_output_contains() {
  local label="$1" expected="$2"; shift 2
  local out
  out="$("$@" 2>&1)" || true
  if printf '%s' "$out" | grep -qF "$expected"; then pass "$label"
  else fail "$label -- expected '${expected}' in: ${out:0:200}"; fi
}

printf '=== ISSUE-18 model defaults tests ===\n\n'

# Helper: create a temp repo with optional config
setup_test_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  mkdir -p .claude

  # Create a config file if content provided
  if [[ $# -gt 0 ]]; then
    echo -e "$1" > .claude/cmux-tab-agents.toml
  fi

  echo "$tmpdir"
}

cleanup_test_repo() {
  rm -rf "$1"
}

# Helper: run resolve_model_for_phase in a test repo
run_resolve_in_repo() {
  local tmpdir="$1" phase="$2"
  shift 2
  (
    cd "$tmpdir"
    # shellcheck source=/dev/null
    source "$SKILL_ROOT/scripts/_dispatch_common.sh"
    resolve_model_for_phase "$phase" "$@"
  ) || true
}

printf '=== Tests ===\n\n'

# Test 1: Bash syntax check on _dispatch_common.sh
check_exit_zero "bash -n _dispatch_common.sh" bash -n "$SKILL_ROOT/scripts/_dispatch_common.sh"

# Test 2: resolve_model_for_phase with explicit --model flag
tmpdir=$(setup_test_repo "[models]\nimplementer = \"claude-haiku-4-5-20251001\"")
trap "cleanup_test_repo '$tmpdir'" EXIT
out=$(run_resolve_in_repo "$tmpdir" implementer --model "claude-opus-4-7")
if [[ "$out" == "claude-opus-4-7" ]]; then
  pass "resolve_model_for_phase: explicit --model overrides config"
else
  fail "resolve_model_for_phase: explicit --model expected 'claude-opus-4-7', got '$out'"
fi
cleanup_test_repo "$tmpdir"

# Test 3: resolve_model_for_phase reads implementer from repo config
tmpdir=$(setup_test_repo "[models]\nimplementer = \"claude-sonnet-4-6\"\nspec_reviewer = \"claude-haiku-4-5-20251001\"\ncode_reviewer = \"claude-haiku-4-5-20251001\"")
trap "cleanup_test_repo '$tmpdir'" EXIT
out=$(run_resolve_in_repo "$tmpdir" implementer)
if [[ "$out" == "claude-sonnet-4-6" ]]; then
  pass "resolve_model_for_phase: reads implementer from repo config"
else
  fail "resolve_model_for_phase: implementer expected 'claude-sonnet-4-6', got '$out'"
fi

# Test 4: resolve_model_for_phase reads spec_reviewer from repo config
out=$(run_resolve_in_repo "$tmpdir" spec_reviewer)
if [[ "$out" == "claude-haiku-4-5-20251001" ]]; then
  pass "resolve_model_for_phase: reads spec_reviewer from repo config"
else
  fail "resolve_model_for_phase: spec_reviewer expected 'claude-haiku-4-5-20251001', got '$out'"
fi

# Test 5: resolve_model_for_phase reads code_reviewer from repo config
out=$(run_resolve_in_repo "$tmpdir" code_reviewer)
if [[ "$out" == "claude-haiku-4-5-20251001" ]]; then
  pass "resolve_model_for_phase: reads code_reviewer from repo config"
else
  fail "resolve_model_for_phase: code_reviewer expected 'claude-haiku-4-5-20251001', got '$out'"
fi
cleanup_test_repo "$tmpdir"

# Test 6: resolve_model_for_phase with no config and no flag returns empty
tmpdir=$(setup_test_repo)
trap "cleanup_test_repo '$tmpdir'" EXIT
out=$(run_resolve_in_repo "$tmpdir" implementer)
if [[ -z "$out" ]]; then
  pass "resolve_model_for_phase: no config, no flag returns empty"
else
  fail "resolve_model_for_phase: no config should return empty, got '$out'"
fi
cleanup_test_repo "$tmpdir"

# Test 7: CLI flag overrides config (explicit precedence)
tmpdir=$(setup_test_repo "[models]\nimplementer = \"claude-sonnet-4-6\"")
trap "cleanup_test_repo '$tmpdir'" EXIT
out=$(run_resolve_in_repo "$tmpdir" implementer --model "claude-haiku-4-5-20251001")
if [[ "$out" == "claude-haiku-4-5-20251001" ]]; then
  pass "resolve_model_for_phase: --model flag overrides config"
else
  fail "resolve_model_for_phase: --model flag should override, expected 'claude-haiku-4-5-20251001', got '$out'"
fi
cleanup_test_repo "$tmpdir"

# Test 8: Hyphenated phase names (spec-reviewer, code-reviewer) are normalized to underscores
tmpdir=$(setup_test_repo "[models]\nspec_reviewer = \"claude-opus-4-7\"\ncode_reviewer = \"claude-haiku-4-5-20251001\"")
trap "cleanup_test_repo '$tmpdir'" EXIT
out=$(run_resolve_in_repo "$tmpdir" spec-reviewer)
if [[ "$out" == "claude-opus-4-7" ]]; then
  pass "resolve_model_for_phase: hyphenated 'spec-reviewer' resolves to underscore config 'spec_reviewer'"
else
  fail "resolve_model_for_phase: spec-reviewer expected 'claude-opus-4-7', got '$out'"
fi

# Test 9: Hyphenated code-reviewer
out=$(run_resolve_in_repo "$tmpdir" code-reviewer)
if [[ "$out" == "claude-haiku-4-5-20251001" ]]; then
  pass "resolve_model_for_phase: hyphenated 'code-reviewer' resolves to underscore config 'code_reviewer'"
else
  fail "resolve_model_for_phase: code-reviewer expected 'claude-haiku-4-5-20251001', got '$out'"
fi
cleanup_test_repo "$tmpdir"

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
