#!/usr/bin/env bash
# Tests for ISSUE-93 Phase 3: progress.sh v2 schema (target/verdict/feedback/issue-hash)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROGRESS_SH="$SCRIPTS_DIR/progress.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-93 Phase 3: progress.sh v2 tests ===\n\n'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
PF="$tmpdir/.cmux-progress.jsonl"

read_line() { head -1 "$PF" 2>/dev/null || echo ""; }
last_line() { tail -1 "$PF" 2>/dev/null || echo ""; }
reset_pf() { : > "$PF"; }

# T1: --target flag adds target field and bumps schema to v2
(cd "$tmpdir" && bash "$PROGRESS_SH" --target spec-reviewer started 2 spec-dispatch 2>/dev/null)
line=$(read_line)
if printf '%s' "$line" | grep -q '"target":"spec-reviewer"'; then
  pass "--target spec-reviewer adds target field"
else
  fail "--target spec-reviewer missing target field: '$line'"
fi
if printf '%s' "$line" | grep -q '"v":2'; then
  pass "--target sets v:2"
else
  fail "--target did not set v:2: '$line'"
fi
reset_pf

# T2: --verdict flag adds verdict field, kind=verdict
(cd "$tmpdir" && bash "$PROGRESS_SH" --role spec-reviewer --target implementer --verdict APPROVED verdict 2 spec-review 2>/dev/null)
line=$(read_line)
if printf '%s' "$line" | grep -q '"verdict":"APPROVED"'; then
  pass "--verdict APPROVED adds verdict field"
else
  fail "--verdict APPROVED missing verdict field: '$line'"
fi
if printf '%s' "$line" | grep -q '"kind":"verdict"'; then
  pass "verdict kind=verdict"
else
  fail "kind not 'verdict': '$line'"
fi
reset_pf

# T3: --feedback flag adds feedback field
(cd "$tmpdir" && bash "$PROGRESS_SH" --target spec-reviewer --feedback "Fixed null check at line 42" feedback 3 spec-fix 2>/dev/null)
line=$(read_line)
if printf '%s' "$line" | grep -q '"feedback":"Fixed null check at line 42"'; then
  pass "--feedback adds feedback field"
else
  fail "--feedback missing feedback field: '$line'"
fi
reset_pf

# T4: --issue-hash flag adds issue_hash field
(cd "$tmpdir" && bash "$PROGRESS_SH" --role spec-reviewer --target implementer --verdict ISSUES_FOUND --feedback "missing null check" --issue-hash "abc123" verdict 2 spec-review 2>/dev/null)
line=$(read_line)
if printf '%s' "$line" | grep -q '"issue_hash":"abc123"'; then
  pass "--issue-hash adds issue_hash field"
else
  fail "--issue-hash missing issue_hash field: '$line'"
fi
reset_pf

# T5: backward compat — no v2 flags => still v:1
(cd "$tmpdir" && bash "$PROGRESS_SH" started 1 boot 2>/dev/null)
line=$(read_line)
if printf '%s' "$line" | grep -q '"v":1'; then
  pass "no v2 flags => v:1 (backward compat)"
else
  fail "expected v:1 for legacy event: '$line'"
fi
if printf '%s' "$line" | grep -q '"target"'; then
  fail "legacy event must not include target field: '$line'"
else
  pass "legacy event has no target field"
fi
reset_pf

# T6: comma-separated targets supported
(cd "$tmpdir" && bash "$PROGRESS_SH" --target "implementer,planner" started 5 multi 2>/dev/null)
line=$(read_line)
if printf '%s' "$line" | grep -q '"target":"implementer,planner"'; then
  pass "comma-separated targets supported"
else
  fail "comma-separated targets failed: '$line'"
fi
reset_pf

# T7: produced lines are valid JSON when jq available
if command -v jq >/dev/null 2>&1; then
  (cd "$tmpdir" && bash "$PROGRESS_SH" --role code-reviewer --target implementer --verdict ISSUES_FOUND --feedback "lint failure" --issue-hash "deadbeef" verdict 4 code-review 2>/dev/null)
  line=$(read_line)
  if printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
    pass "v2 event with all fields is valid JSON"
  else
    fail "v2 event invalid JSON: '$line'"
  fi
  reset_pf
fi

# T8: progress.sh exits 0 even with v2 flag errors (best-effort)
ec=$(bash "$PROGRESS_SH" --target 2>/dev/null; echo $?)
if [[ "$ec" -eq 0 ]]; then
  pass "progress.sh tolerates malformed --target (exits 0)"
else
  fail "progress.sh --target with no value exited $ec (expected 0)"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
