#!/usr/bin/env bash
# test_agent_loop.sh
# Verify agent-loop flags (--lead-surface, --max-loop-iterations) are rendered
# correctly in implementer, spec-reviewer, and code-reviewer prompts.
# Shell-level render-and-grep tests — no live cmux needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$SKILL_ROOT/scripts"
PROMPTS_DIR="$SKILL_ROOT/prompts"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

# Render a prompt template using _dispatch_common.sh's render_template function.
render() {
  local phase="$1" outfile="$2"
  shift 2
  # Set required env vars
  export TPL_TICKET="ISSUE-99"
  export TPL_TITLE="Test issue"
  export TPL_SLUG="test-issue"
  export TPL_WORKTREE="/tmp/test-wt"
  export TPL_PWS="ws-abc"
  export TPL_PSURF="surface:0"
  export TPL_IMPL_SHA="deadbeef"
  export TPL_TASK="Do the thing"
  export TPL_FEEDBACK=""
  export TPL_LEAD_SURF="${LEAD_SURF:-surface:7}"
  export TPL_MAX_LOOP_ITER="${MAX_LOOP_ITER:-5}"
  export PHASE="$phase"
  # Additional vars used by some phases
  export TPL_SPEC_SHA="${TPL_SPEC_SHA:-}"
  export TPL_CODE_SHA="${TPL_CODE_SHA:-}"
  export TPL_FINISH_MODE="${TPL_FINISH_MODE:-}"
  export TPL_FIX_ONLY="${TPL_FIX_ONLY:-}"
  export TPL_EFFORT="${TPL_EFFORT:-}"
  export TPL_MODEL="${TPL_MODEL:-}"
  export TPL_TYPE="${TPL_TYPE:-}"

  source "$SCRIPTS_DIR/_dispatch_common.sh"
  render_template "$PROMPTS_DIR/${phase}-tab-prompt.md" "$outfile"
}

# ---------------------------------------------------------------------------
# Test 1: Happy path — {{LEAD_SURFACE}} replaced in implementer prompt
# ---------------------------------------------------------------------------
echo "Test 1: {{LEAD_SURFACE}} replaced in implementer prompt..."
LEAD_SURF="surface:7" MAX_LOOP_ITER="5"
OUT="$TMPDIR/impl.md"
render "implementer" "$OUT"
if grep -q 'surface:7' "$OUT" && ! grep -q '{{LEAD_SURFACE}}' "$OUT"; then
  pass "LEAD_SURFACE substituted in implementer prompt"
else
  fail "LEAD_SURFACE not substituted in implementer prompt"
fi

# ---------------------------------------------------------------------------
# Test 2: Happy path — {{MAX_LOOP_ITERATIONS}} replaced in implementer prompt
# ---------------------------------------------------------------------------
echo "Test 2: {{MAX_LOOP_ITERATIONS}} replaced in implementer prompt..."
if grep -q '5' "$OUT" && ! grep -q '{{MAX_LOOP_ITERATIONS}}' "$OUT"; then
  pass "MAX_LOOP_ITERATIONS substituted in implementer prompt"
else
  fail "MAX_LOOP_ITERATIONS not substituted in implementer prompt"
fi

# ---------------------------------------------------------------------------
# Test 3: Circuit-breaker token replaced with custom max-iterations value
# ---------------------------------------------------------------------------
echo "Test 3: Custom --max-loop-iterations (3) rendered correctly..."
LEAD_SURF="surface:7" MAX_LOOP_ITER="3"
OUT3="$TMPDIR/impl-iter3.md"
render "implementer" "$OUT3"
if grep -q '3' "$OUT3" && ! grep -q '{{MAX_LOOP_ITERATIONS}}' "$OUT3"; then
  pass "Custom MAX_LOOP_ITERATIONS=3 rendered in implementer prompt"
else
  fail "Custom MAX_LOOP_ITERATIONS=3 not rendered in implementer prompt"
fi

# ---------------------------------------------------------------------------
# Test 4: {{LEAD_SURFACE}} replaced in spec-reviewer prompt
# ---------------------------------------------------------------------------
echo "Test 4: {{LEAD_SURFACE}} replaced in spec-reviewer prompt..."
LEAD_SURF="surface:9" MAX_LOOP_ITER="5"
SOUT="$TMPDIR/spec-rev.md"
render "spec-reviewer" "$SOUT"
if grep -q 'surface:9' "$SOUT" && ! grep -q '{{LEAD_SURFACE}}' "$SOUT"; then
  pass "LEAD_SURFACE substituted in spec-reviewer prompt"
else
  fail "LEAD_SURFACE not substituted in spec-reviewer prompt"
fi

# ---------------------------------------------------------------------------
# Test 5: spec-reviewer ISSUES_FOUND routing points to LEAD_SURFACE
# ---------------------------------------------------------------------------
echo "Test 5: spec-reviewer ISSUES_FOUND routes to LEAD_SURFACE..."
if grep -A3 'ISSUES_FOUND' "$SOUT" | grep -q 'surface:9'; then
  pass "spec-reviewer ISSUES_FOUND routes to LEAD_SURFACE"
else
  fail "spec-reviewer ISSUES_FOUND does not route to LEAD_SURFACE"
fi

# ---------------------------------------------------------------------------
# Test 6: {{LEAD_SURFACE}} replaced in code-reviewer prompt
# ---------------------------------------------------------------------------
echo "Test 6: {{LEAD_SURFACE}} replaced in code-reviewer prompt..."
LEAD_SURF="surface:9" MAX_LOOP_ITER="5"
COUT="$TMPDIR/code-rev.md"
render "code-reviewer" "$COUT"
if grep -q 'surface:9' "$COUT" && ! grep -q '{{LEAD_SURFACE}}' "$COUT"; then
  pass "LEAD_SURFACE substituted in code-reviewer prompt"
else
  fail "LEAD_SURFACE not substituted in code-reviewer prompt"
fi

# ---------------------------------------------------------------------------
# Test 7: code-reviewer ISSUES_FOUND routing points to LEAD_SURFACE
# ---------------------------------------------------------------------------
echo "Test 7: code-reviewer ISSUES_FOUND routes to LEAD_SURFACE..."
if grep -A3 'ISSUES_FOUND' "$COUT" | grep -q 'surface:9'; then
  pass "code-reviewer ISSUES_FOUND routes to LEAD_SURFACE"
else
  fail "code-reviewer ISSUES_FOUND does not route to LEAD_SURFACE"
fi

# ---------------------------------------------------------------------------
# Test 8: No unreplaced {{PLACEHOLDER}} tokens remain in any rendered prompt
# ---------------------------------------------------------------------------
echo "Test 8: No unreplaced placeholders in rendered prompts..."
LEFTOVERS=0
for f in "$TMPDIR"/*.md; do
  if grep -q '{{[A-Z_]*}}' "$f"; then
    echo "  Unreplaced placeholder(s) in $f:"
    grep '{{[A-Z_]*}}' "$f"
    ((LEFTOVERS++)) || true
  fi
done
if [[ $LEFTOVERS -eq 0 ]]; then
  pass "No unreplaced placeholders in any rendered prompt"
else
  fail "Unreplaced placeholders found in $LEFTOVERS file(s)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All tests passed!"
