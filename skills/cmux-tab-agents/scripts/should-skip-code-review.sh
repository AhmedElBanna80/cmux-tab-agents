#!/usr/bin/env bash
# should-skip-code-review.sh — determine if code-quality review can be skipped on a trivial diff
#
# Usage:
#   should-skip-code-review.sh --worktree <path> --implementer-sha <sha>
#
# Exit codes:
#   0 = safe to skip code-quality review
#   1 = code-quality review required
#
# Stderr: reason for the decision
#
# Heuristic (must meet ALL three conditions):
#   1. Diff is ≤ 30 changed lines (by git diff --shortstat)
#   2. All changed files are test/spec files (*test* / *spec*), markdown, or changelog
#   3. Spec-reviewer reported APPROVED with no concerns flagged

set -euo pipefail

WORKTREE=""
IMPLEMENTER_SHA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)      WORKTREE="$2"; shift 2 ;;
    --implementer-sha) IMPLEMENTER_SHA="$2"; shift 2 ;;
    *) echo "should-skip-code-review: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

[[ -z "$WORKTREE" ]] && { echo "should-skip-code-review: --worktree required" >&2; exit 1; }
[[ -z "$IMPLEMENTER_SHA" ]] && { echo "should-skip-code-review: --implementer-sha required" >&2; exit 1; }

# Helper: exit with a reason
skip_reason() {
  echo "$1" >&2
  exit 1
}

# 1. Check diff size
DIFF_SHORTSTAT=$(git -C "$WORKTREE" diff --shortstat "${IMPLEMENTER_SHA}~1..${IMPLEMENTER_SHA}" 2>/dev/null || echo "")
if [[ -z "$DIFF_SHORTSTAT" ]]; then
  skip_reason "diff check failed (no parent commit or git error)"
fi

# Extract changed lines from shortstat: "N files changed, M insertions(+), P deletions(-)"
# We sum insertions + deletions to get total changed lines
INSERTIONS=$(echo "$DIFF_SHORTSTAT" | grep -oE '[0-9]+ insertions' | grep -oE '[0-9]+' || echo 0)
DELETIONS=$(echo "$DIFF_SHORTSTAT" | grep -oE '[0-9]+ deletions' | grep -oE '[0-9]+' || echo 0)
TOTAL_CHANGES=$((INSERTIONS + DELETIONS))

if [[ $TOTAL_CHANGES -gt 30 ]]; then
  skip_reason "diff too large: $TOTAL_CHANGES changed lines (max 30)"
fi

# 2. Check file patterns: must be test/spec/markdown/changelog only
CHANGED_FILES=$(git -C "$WORKTREE" diff --name-only "${IMPLEMENTER_SHA}~1..${IMPLEMENTER_SHA}" 2>/dev/null || echo "")
while IFS= read -r file; do
  # Allow test/spec files, markdown, and changelog
  if ! [[ "$file" =~ test ]] && ! [[ "$file" =~ spec ]] && ! [[ "$file" =~ \.md$ ]] && ! [[ "$file" =~ CHANGELOG ]]; then
    skip_reason "non-trivial file: $file (must be test/*spec or markdown)"
  fi
done <<< "$CHANGED_FILES"

# 3. Check spec-reviewer result
SPEC_RESULT="$WORKTREE/.cmux-spec-reviewer-result.md"
if [[ ! -f "$SPEC_RESULT" ]]; then
  skip_reason "spec-reviewer result not found at $SPEC_RESULT"
fi

# Extract status from spec-reviewer result
SPEC_STATUS=$(awk -F': *' '/^status:/ {print $2; exit}' "$SPEC_RESULT" 2>/dev/null || echo "")
if [[ "$SPEC_STATUS" != "APPROVED" ]]; then
  skip_reason "spec-reviewer status is '$SPEC_STATUS' (not APPROVED)"
fi

# Check for concerns flagged in the spec-reviewer result.
# Conservative check: if the result mentions issues, concerns, or missing requirements, don't skip.
if grep -qi "missing requirement\|concern\|issue\|should\|but\|however" "$SPEC_RESULT"; then
  skip_reason "spec-reviewer flagged concerns or issues"
fi

# All checks passed: safe to skip
exit 0
