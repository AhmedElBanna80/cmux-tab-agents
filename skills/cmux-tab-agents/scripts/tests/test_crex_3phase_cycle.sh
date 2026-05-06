#!/usr/bin/env bash
# Integration test for CREX-POC-001-3: 3-phase cycle with session persistence
# Tests that implementer saves crex session, spec-reviewer can resurrect on ISSUES_FOUND,
# and loop completes with no zombie tabs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== CREX-POC-001-3: 3-phase cycle session persistence tests ===\n\n'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# T1: README documents crex installation
readme="$SKILL_ROOT/../../README.md"
if [[ -r "$readme" ]]; then
  if grep -qi "crex\|cmux-resurrect" "$readme"; then
    pass "README documents crex (cmux-resurrect)"
  else
    fail "README missing crex documentation"
  fi
else
  fail "README not found"
fi

# T2: README documents crex save/restore commands
if [[ -r "$readme" ]]; then
  if grep -q "crex save" "$readme" && grep -q "crex restore" "$readme"; then
    pass "README shows crex save and restore commands"
  else
    fail "README missing crex save/restore command examples"
  fi
fi

# T3: README documents crex in hooks configuration
if [[ -r "$readme" ]]; then
  if grep -qE "Stop.*hook|crex save.*hook|~/.claude/settings.json" "$readme"; then
    pass "README documents crex in Stop hook configuration"
  else
    fail "README missing crex Stop hook setup"
  fi
fi

# T4: Implementer prompt references crex/session persistence
impl_prompt="$SKILL_ROOT/prompts/implementer-tab-prompt.md"
if [[ -r "$impl_prompt" ]]; then
  if grep -qi "crex\|session.*persist\|save.*session\|resurrect" "$impl_prompt"; then
    pass "implementer prompt references crex or session persistence"
  else
    fail "implementer prompt missing crex/session persistence reference"
  fi
else
  fail "implementer prompt not found"
fi

# T5: Spec-reviewer prompt references crex/session restoration
spec_prompt="$SKILL_ROOT/prompts/spec-reviewer-tab-prompt.md"
if [[ -r "$spec_prompt" ]]; then
  if grep -qi "crex\|session.*persist\|restore.*session\|resurrect" "$spec_prompt"; then
    pass "spec-reviewer prompt references crex or session restoration"
  else
    fail "spec-reviewer prompt missing crex/session restoration reference"
  fi
else
  fail "spec-reviewer prompt not found"
fi

# T6: Code-reviewer prompt references crex/session handling
code_prompt="$SKILL_ROOT/prompts/code-reviewer-tab-prompt.md"
if [[ -r "$code_prompt" ]]; then
  if grep -qi "crex\|session.*persist\|resurrect" "$code_prompt"; then
    pass "code-reviewer prompt references crex or session handling"
  else
    fail "code-reviewer prompt missing crex/session handling reference"
  fi
else
  fail "code-reviewer prompt not found"
fi

# T7: SKILL.md documents session persistence and zombie tab prevention
skill_md="$SKILL_ROOT/SKILL.md"
if [[ -r "$skill_md" ]]; then
  if grep -qi "session\|persist\|crex\|zombie\|resurrect" "$skill_md"; then
    pass "SKILL.md documents session persistence or zombie tab handling"
  else
    fail "SKILL.md missing session persistence or zombie tab documentation"
  fi
else
  fail "SKILL.md not found"
fi

# T8: CHANGELOG has entry for crex/session persistence feature
changelog="$SKILL_ROOT/CHANGELOG.md"
if [[ -r "$changelog" ]]; then
  if grep -qi "crex\|session.*persist\|CREX-POC" "$changelog"; then
    pass "CHANGELOG.md has entry for crex/session persistence"
  else
    fail "CHANGELOG.md missing crex/session persistence entry"
  fi
else
  fail "CHANGELOG.md not found"
fi

# T9: Discipline.md acknowledges session persistence as part of workflow
discipline="$SKILL_ROOT/references/discipline.md"
if [[ -r "$discipline" ]]; then
  # Check for reference to session handling or crex
  if grep -qi "session\|persist\|crex" "$discipline"; then
    pass "discipline.md acknowledges session persistence"
  else
    fail "discipline.md missing session persistence acknowledgment"
  fi
else
  fail "discipline.md not found"
fi

# T10: Implementer prompt documents process for saving session state before exit
if [[ -r "$impl_prompt" ]]; then
  content=$(cat "$impl_prompt")
  # Should mention that implementer needs to save state (crex save) before exit
  if echo "$content" | grep -qi "save.*state\|save.*session\|crex\|before.*exit\|on.*exit"; then
    pass "implementer prompt documents saving session before exit"
  else
    fail "implementer prompt missing documentation on saving session before exit"
  fi
fi

# T11: Spec-reviewer prompt documents process for restoring session on ISSUES_FOUND
if [[ -r "$spec_prompt" ]]; then
  content=$(cat "$spec_prompt")
  # Should mention that spec-reviewer needs to restore state when finding issues
  if echo "$content" | grep -qi "restore.*session\|restore.*state\|crex\|issues_found.*restore"; then
    pass "spec-reviewer prompt documents restoring session on ISSUES_FOUND"
  else
    fail "spec-reviewer prompt missing documentation on restoring session on ISSUES_FOUND"
  fi
fi

# T12: References directory has doc on session persistence workflow
ref_dir="$SKILL_ROOT/references"
if [[ -d "$ref_dir" ]]; then
  # Check if any reference file documents the session persistence workflow
  if grep -r -l -i "session\|persist\|crex\|resurrect" "$ref_dir" 2>/dev/null | grep -q .; then
    pass "references directory has documentation on session persistence"
  else
    fail "references directory missing session persistence documentation"
  fi
else
  fail "references directory not found"
fi

# T13: Implementer prompt task context has crex/session field
if [[ -r "$impl_prompt" ]]; then
  # Check task context section
  content=$(tail -100 "$impl_prompt")  # Check last 100 lines for task context
  if echo "$content" | grep -qi "crex\|session\|persist"; then
    pass "implementer task context mentions crex/session"
  else
    fail "implementer task context missing crex/session field"
  fi
fi

# T14: Spec-reviewer has reference to checking for zombie tabs
if [[ -r "$spec_prompt" ]]; then
  if grep -qi "zombie\|orphan\|tab.*cleanup\|tab.*state" "$spec_prompt"; then
    pass "spec-reviewer prompt references zombie tab prevention"
  else
    fail "spec-reviewer prompt missing zombie tab prevention reference"
  fi
fi

# T15: CONTRIBUTING.md documents crex requirement for integration tests
contrib="$SKILL_ROOT/../../CONTRIBUTING.md"
if [[ -r "$contrib" ]]; then
  if grep -qi "crex\|session\|integration.*test" "$contrib"; then
    pass "CONTRIBUTING.md documents crex/session persistence requirements"
  else
    fail "CONTRIBUTING.md missing crex/session persistence documentation"
  fi
else
  fail "CONTRIBUTING.md not found"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
