#!/usr/bin/env bash
# test-prompt-absolute-script-refs.sh
# Asserts that every script reference in a prompt template uses
# {{SKILL_BASE}}/scripts/<name> form — not a bare-command (PATH-resolved)
# nor a relative ("scripts/<name>") form. ISSUE-82.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$SKILL_ROOT/prompts"

# Repo scripts whose references in prompts must be absolute via {{SKILL_BASE}}.
SCRIPT_NAMES='dispatch-spec-reviewer|dispatch-code-reviewer|dispatch-implementer|finish-task|should-skip-code-review|crex-save|task-adapter|poll-result|done-cleanup|ensure-worktree|install-tab-hooks|resolve-agents-pane'

failures=0

for f in "$PROMPTS_DIR"/*.md; do
  # 1. Bare-command form: line begins (after optional whitespace) with a script name.
  if grep -nE "^[[:space:]]*(${SCRIPT_NAMES})\.sh\b" "$f" >/dev/null; then
    echo "FAIL: $f has bare-command script reference(s):"
    grep -nE "^[[:space:]]*(${SCRIPT_NAMES})\.sh\b" "$f"
    failures=$((failures + 1))
  fi
  # 2. Relative-path form: "scripts/<name>.sh" not preceded by '/'.
  #    Allowed form is "{{SKILL_BASE}}/scripts/<name>.sh", which has '/' before
  #    'scripts/'. The negative class "(^|[^/])" excludes the allowed form.
  if grep -nE "(^|[^/])scripts/(${SCRIPT_NAMES})\.sh\b" "$f" >/dev/null; then
    echo "FAIL: $f has relative 'scripts/...' script reference(s):"
    grep -nE "(^|[^/])scripts/(${SCRIPT_NAMES})\.sh\b" "$f"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "Replace each with {{SKILL_BASE}}/scripts/<script> in the prompt template."
  exit 1
fi

echo "PASS: All prompt templates use {{SKILL_BASE}}/scripts/... for repo-script references"
