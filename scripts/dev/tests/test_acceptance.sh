#!/usr/bin/env bash
# Acceptance tests for CTADEV-2: render-prompt.sh and lint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RENDER="$REPO_ROOT/scripts/dev/render-prompt.sh"
LINT="$REPO_ROOT/scripts/dev/lint.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

check_exit_zero() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"
  else fail "$label (expected exit 0)"; fi
}

check_exit_nonzero() {
  local label="$1"; shift
  if ! "$@" >/dev/null 2>&1; then pass "$label"
  else fail "$label (expected non-zero exit)"; fi
}

check_output_contains() {
  local label="$1" expected="$2"; shift 2
  local out
  out="$("$@" 2>&1)" || true
  if printf '%s' "$out" | grep -qF "$expected"; then pass "$label"
  else fail "$label -- expected '${expected}' in: ${out:0:120}"; fi
}

check_output_not_contains() {
  local label="$1" unexpected="$2"; shift 2
  local out
  out="$("$@" 2>&1)" || true
  if ! printf '%s' "$out" | grep -qF "$unexpected"; then pass "$label"
  else fail "$label -- unexpected '${unexpected}' found in output"; fi
}

printf '=== CTADEV-2 acceptance tests ===\n\n'

# T1: bash syntax check
check_exit_zero "bash -n render-prompt.sh" bash -n "$RENDER"
check_exit_zero "bash -n lint.sh" bash -n "$LINT"

# T2: render implementer → no unsubstituted tokens for known keys
check_output_not_contains "render implementer: no {{TICKET}}" "{{TICKET}}" bash "$RENDER" implementer
check_output_not_contains "render implementer: no {{TASK}}" "{{TASK}}" bash "$RENDER" implementer
check_output_not_contains "render implementer: no {{WORKTREE}}" "{{WORKTREE}}" bash "$RENDER" implementer
check_output_not_contains "render implementer: no {{PLANNER_WORKSPACE}}" "{{PLANNER_WORKSPACE}}" bash "$RENDER" implementer
check_output_not_contains "render implementer: no {{PLANNER_SURFACE}}" "{{PLANNER_SURFACE}}" bash "$RENDER" implementer
check_output_not_contains "render implementer: no {{FEEDBACK}}" "{{FEEDBACK}}" bash "$RENDER" implementer

# T3: --check mode exits 0 for all phases
check_exit_zero "render implementer --check exits 0" bash "$RENDER" implementer --check
check_exit_zero "render spec-reviewer --check exits 0" bash "$RENDER" spec-reviewer --check
check_exit_zero "render code-reviewer --check exits 0" bash "$RENDER" code-reviewer --check

# T4: --check mode prints OK message
check_output_contains "render implementer --check: OK message" \
  "OK: implementer template clean" bash "$RENDER" implementer --check

# T5: --values overrides applied in rendered output
out=$(bash "$RENDER" spec-reviewer --values "TICKET=TEST-1,TASK=dummy" 2>&1) || out=""
if printf '%s' "$out" | grep -qF "TEST-1"; then pass "render spec-reviewer: TICKET override"
else fail "render spec-reviewer: TICKET override not found in output"; fi
if printf '%s' "$out" | grep -qF "dummy"; then pass "render spec-reviewer: TASK override"
else fail "render spec-reviewer: TASK override not found in output"; fi

# T6: invalid phase exits non-zero
check_exit_nonzero "invalid phase exits non-zero" bash "$RENDER" bad-phase

# T7: missing phase exits non-zero with error message
check_output_contains "bad-phase: error on stderr" "invalid phase" bash "$RENDER" bad-phase 2>&1 || true
check_exit_nonzero "bad-phase exits non-zero" bash "$RENDER" bad-phase

# T8: make preview exits 0
check_exit_zero "make preview exits 0" make -C "$REPO_ROOT" preview

# T10: make lint exits 0
check_exit_zero "make lint exits 0" make -C "$REPO_ROOT" lint

# T11: make help lists all 6 targets
out=$(make -C "$REPO_ROOT" help 2>&1) || out=""
for target in help link unlink status lint preview; do
  if printf '%s' "$out" | grep -qF "$target"; then pass "make help lists '$target'"
  else fail "make help missing '$target'"; fi
done

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
