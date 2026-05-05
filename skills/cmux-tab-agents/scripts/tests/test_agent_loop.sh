#!/usr/bin/env bash
# Tests for ISSUE-26: agent-to-agent review loop (implementer as task lead)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
DISPATCH_COMMON="$SCRIPTS_DIR/_dispatch_common.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-26: agent loop / implementer-as-task-lead tests ===\n\n'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# T1: bash syntax check on _dispatch_common.sh
if bash -n "$DISPATCH_COMMON" 2>/dev/null; then
  pass "bash -n _dispatch_common.sh"
else
  fail "bash -n _dispatch_common.sh (syntax error)"
fi

# T2: --max-loop-iterations is recognized (no "unknown arg" error)
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test \
    --task-text 'task' --max-loop-iterations 5 2>&1
" || true)
if printf '%s' "$out" | grep -q "unknown arg.*max-loop"; then
  fail "--max-loop-iterations flag not recognized: $out"
else
  pass "--max-loop-iterations flag is recognized"
fi

# T3: --lead-surface is recognized (no "unknown arg" error)
out=$(cd "$tmpdir" && bash -c "
  . '$DISPATCH_COMMON'
  dispatch_main --ticket TEST-1 --title 'Test' --slug test \
    --task-text 'task' --lead-surface 'surface:42' 2>&1
" || true)
if printf '%s' "$out" | grep -q "unknown arg.*lead-surface"; then
  fail "--lead-surface flag not recognized: $out"
else
  pass "--lead-surface flag is recognized"
fi

# T4: render_template substitutes {{LEAD_SURFACE}}
cat > "$tmpdir/tpl.md" <<'EOF'
Lead surface is: {{LEAD_SURFACE}}
EOF
(
  # shellcheck source=/dev/null
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  TPL_TICKET="" TPL_TITLE="" TPL_SLUG="" TPL_WORKTREE="" TPL_PWS="" \
  TPL_PSURF="" TPL_IMPL_SHA="" TPL_TASK="" TPL_FEEDBACK="" \
  TPL_SKILL_BASE="" TPL_FINISH_MODE="" TPL_LEAD_SURF="surface:99" \
  TPL_MAX_LOOP_ITER="" \
  render_template "$tmpdir/tpl.md" "$tmpdir/out.md"
)
rendered=$(cat "$tmpdir/out.md" 2>/dev/null || echo "")
if printf '%s' "$rendered" | grep -q "surface:99"; then
  pass "render_template substitutes {{LEAD_SURFACE}}"
else
  fail "render_template does not substitute {{LEAD_SURFACE}}: '$rendered'"
fi

# T5: render_template substitutes {{MAX_LOOP_ITERATIONS}}
cat > "$tmpdir/tpl2.md" <<'EOF'
Max iterations: {{MAX_LOOP_ITERATIONS}}
EOF
(
  # shellcheck source=/dev/null
  # shellcheck source=/dev/null
  . "$DISPATCH_COMMON"
  TPL_TICKET="" TPL_TITLE="" TPL_SLUG="" TPL_WORKTREE="" TPL_PWS="" \
  TPL_PSURF="" TPL_IMPL_SHA="" TPL_TASK="" TPL_FEEDBACK="" \
  TPL_SKILL_BASE="" TPL_FINISH_MODE="" TPL_LEAD_SURF="" \
  TPL_MAX_LOOP_ITER="7" \
  render_template "$tmpdir/tpl2.md" "$tmpdir/out2.md"
)
rendered2=$(cat "$tmpdir/out2.md" 2>/dev/null || echo "")
if printf '%s' "$rendered2" | grep -q "Max iterations: 7"; then
  pass "render_template substitutes {{MAX_LOOP_ITERATIONS}}"
else
  fail "render_template does not substitute {{MAX_LOOP_ITERATIONS}}: '$rendered2'"
fi

# T6: Implementer prompt contains task-lead pipeline section
impl_prompt="$SKILL_ROOT/prompts/implementer-tab-prompt.md"
if [[ -r "$impl_prompt" ]]; then
  if grep -qiE "task.lead|task lead" "$impl_prompt"; then
    pass "implementer prompt contains task-lead pipeline section"
  else
    fail "implementer prompt missing task-lead pipeline section"
  fi
else
  fail "implementer prompt not found at $impl_prompt"
fi

# T7: Implementer prompt mentions dispatch-spec-reviewer after DONE
if [[ -r "$impl_prompt" ]]; then
  if grep -q "dispatch-spec-reviewer" "$impl_prompt"; then
    pass "implementer prompt references dispatch-spec-reviewer"
  else
    fail "implementer prompt does not reference dispatch-spec-reviewer"
  fi
fi

# T8: Implementer prompt mentions circuit-breaker
if [[ -r "$impl_prompt" ]]; then
  if grep -qiE "circuit.breaker|circuit_breaker|same issue twice|max.*iter|BLOCKED" "$impl_prompt"; then
    pass "implementer prompt mentions circuit-breaker / BLOCKED escalation"
  else
    fail "implementer prompt missing circuit-breaker instructions"
  fi
fi

# T9: Implementer prompt has {{MAX_LOOP_ITERATIONS}} placeholder
if [[ -r "$impl_prompt" ]]; then
  if grep -q "{{MAX_LOOP_ITERATIONS}}" "$impl_prompt"; then
    pass "implementer prompt has {{MAX_LOOP_ITERATIONS}} placeholder"
  else
    fail "implementer prompt missing {{MAX_LOOP_ITERATIONS}} placeholder"
  fi
fi

# T10: Spec-reviewer prompt has {{LEAD_SURFACE}} placeholder
spec_prompt="$SKILL_ROOT/prompts/spec-reviewer-tab-prompt.md"
if [[ -r "$spec_prompt" ]]; then
  if grep -q "{{LEAD_SURFACE}}" "$spec_prompt"; then
    pass "spec-reviewer prompt has {{LEAD_SURFACE}} placeholder"
  else
    fail "spec-reviewer prompt missing {{LEAD_SURFACE}} placeholder"
  fi
else
  fail "spec-reviewer prompt not found at $spec_prompt"
fi

# T11: Spec-reviewer prompt pushes ISSUES_FOUND to LEAD_SURFACE (not just PLANNER_SURFACE)
if [[ -r "$spec_prompt" ]]; then
  if grep -qE "LEAD_SURFACE.*ISSUES_FOUND|ISSUES_FOUND.*LEAD_SURFACE|lead.*surface.*issues|issues.*lead.*surface" "$spec_prompt" \
     || (grep -q "ISSUES_FOUND" "$spec_prompt" && grep -q "LEAD_SURFACE" "$spec_prompt"); then
    pass "spec-reviewer prompt references LEAD_SURFACE for ISSUES_FOUND"
  else
    fail "spec-reviewer prompt does not reference LEAD_SURFACE for ISSUES_FOUND"
  fi
fi

# T12: Code-reviewer prompt has {{LEAD_SURFACE}} placeholder
code_prompt="$SKILL_ROOT/prompts/code-reviewer-tab-prompt.md"
if [[ -r "$code_prompt" ]]; then
  if grep -q "{{LEAD_SURFACE}}" "$code_prompt"; then
    pass "code-reviewer prompt has {{LEAD_SURFACE}} placeholder"
  else
    fail "code-reviewer prompt missing {{LEAD_SURFACE}} placeholder"
  fi
else
  fail "code-reviewer prompt not found at $code_prompt"
fi

# T13: Code-reviewer prompt pushes ISSUES_FOUND to LEAD_SURFACE
if [[ -r "$code_prompt" ]]; then
  if grep -q "ISSUES_FOUND" "$code_prompt" && grep -q "LEAD_SURFACE" "$code_prompt"; then
    pass "code-reviewer prompt references LEAD_SURFACE for ISSUES_FOUND"
  else
    fail "code-reviewer prompt does not reference LEAD_SURFACE for ISSUES_FOUND"
  fi
fi

# T14: reporting-contract.md documents .cmux-task-result.md
contract="$SKILL_ROOT/references/reporting-contract.md"
if [[ -r "$contract" ]]; then
  if grep -q "cmux-task-result" "$contract"; then
    pass "reporting-contract.md documents .cmux-task-result.md"
  else
    fail "reporting-contract.md missing .cmux-task-result.md documentation"
  fi
else
  fail "reporting-contract.md not found"
fi

# T15: SKILL.md updated — planner no longer dispatches reviewers directly
skill_md="$SKILL_ROOT/SKILL.md"
if [[ -r "$skill_md" ]]; then
  if grep -qiE "implementer.*review.*loop|implementer.*task.lead|review.*loop.*without.*planner" "$skill_md"; then
    pass "SKILL.md documents implementer-as-task-lead loop"
  else
    fail "SKILL.md not updated for implementer-as-task-lead loop"
  fi
else
  fail "SKILL.md not found"
fi

# T16: CHANGELOG.md has entry for ISSUE-26
changelog="$SKILL_ROOT/CHANGELOG.md"
if [[ -r "$changelog" ]]; then
  if grep -qiE "ISSUE-26|agent.*loop.*without.*planner|review loop|task.lead" "$changelog"; then
    pass "CHANGELOG.md has entry for ISSUE-26"
  else
    fail "CHANGELOG.md missing entry for ISSUE-26"
  fi
else
  fail "CHANGELOG.md not found"
fi

# T17: Implementer prompt has {{LEAD_SURFACE}} placeholder (for spawning reviewers)
if [[ -r "$impl_prompt" ]]; then
  if grep -q "{{LEAD_SURFACE}}" "$impl_prompt" || grep -q "lead.surface\|lead_surface" "$impl_prompt"; then
    pass "implementer prompt references lead surface concept"
  else
    fail "implementer prompt missing lead surface reference"
  fi
fi

# T18: Spec-reviewer prompt task context includes LEAD_SURFACE field
if [[ -r "$spec_prompt" ]]; then
  if grep -qE "Lead surface|lead_surface|\*\*Lead" "$spec_prompt"; then
    pass "spec-reviewer task context has lead surface field"
  else
    fail "spec-reviewer task context missing lead surface field"
  fi
fi

# T19: Code-reviewer prompt task context includes LEAD_SURFACE field
if [[ -r "$code_prompt" ]]; then
  if grep -qE "Lead surface|lead_surface|\*\*Lead" "$code_prompt"; then
    pass "code-reviewer task context has lead surface field"
  else
    fail "code-reviewer task context missing lead surface field"
  fi
fi

# T20: Rendered implementer prompt contains circuit-breaker prose (same issue twice → BLOCKED)
if [[ -r "$impl_prompt" ]]; then
  (
    . "$DISPATCH_COMMON"
    TPL_TICKET="TEST-1" TPL_TITLE="Test" TPL_SLUG="test" TPL_WORKTREE="/tmp/wt" \
    TPL_PWS="surface:1" TPL_PSURF="surface:0" TPL_IMPL_SHA="abc1234" \
    TPL_TASK="task text" TPL_FEEDBACK="" TPL_SKILL_BASE="/tmp/skill" \
    TPL_FINISH_MODE="pr" TPL_LEAD_SURF="surface:42" TPL_MAX_LOOP_ITER="5" \
    render_template "$impl_prompt" "$tmpdir/rendered_impl.md"
  )
  rendered_impl=$(cat "$tmpdir/rendered_impl.md" 2>/dev/null || echo "")
  if printf '%s' "$rendered_impl" | grep -q "same issue" && \
     printf '%s' "$rendered_impl" | grep -q "BLOCKED"; then
    pass "rendered implementer prompt: circuit-breaker (same issue twice → BLOCKED) present"
  else
    fail "rendered implementer prompt missing circuit-breaker prose (same issue + BLOCKED)"
  fi
else
  fail "implementer prompt not found for T20"
fi

# T21: Rendered implementer prompt with MAX_LOOP_ITERATIONS=3 contains "3" and BLOCKED
if [[ -r "$impl_prompt" ]]; then
  (
    . "$DISPATCH_COMMON"
    TPL_TICKET="TEST-1" TPL_TITLE="Test" TPL_SLUG="test" TPL_WORKTREE="/tmp/wt" \
    TPL_PWS="surface:1" TPL_PSURF="surface:0" TPL_IMPL_SHA="abc1234" \
    TPL_TASK="task text" TPL_FEEDBACK="" TPL_SKILL_BASE="/tmp/skill" \
    TPL_FINISH_MODE="pr" TPL_LEAD_SURF="surface:42" TPL_MAX_LOOP_ITER="3" \
    render_template "$impl_prompt" "$tmpdir/rendered_impl_3.md"
  )
  rendered_impl3=$(cat "$tmpdir/rendered_impl_3.md" 2>/dev/null || echo "")
  if printf '%s' "$rendered_impl3" | grep -q "3" && \
     printf '%s' "$rendered_impl3" | grep -q "BLOCKED"; then
    pass "rendered implementer prompt (MAX_LOOP_ITERATIONS=3): max-iterations BLOCKED prose present"
  else
    fail "rendered implementer prompt missing max-iterations BLOCKED prose with value 3"
  fi
else
  fail "implementer prompt not found for T21"
fi

# T22: Rendered implementer prompt contains happy-path terminal state (finish-task.sh + .cmux-task-result.md + DONE)
if [[ -r "$impl_prompt" ]]; then
  rendered_impl=$(cat "$tmpdir/rendered_impl.md" 2>/dev/null || echo "")
  if printf '%s' "$rendered_impl" | grep -q "finish-task.sh" && \
     printf '%s' "$rendered_impl" | grep -q "cmux-task-result" && \
     printf '%s' "$rendered_impl" | grep -q "DONE"; then
    pass "rendered implementer prompt: happy-path terminal state (finish-task.sh + .cmux-task-result.md + DONE) present"
  else
    fail "rendered implementer prompt missing happy-path terminal state wiring"
  fi
else
  fail "implementer prompt not found for T22"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
