#!/usr/bin/env bash
# poll-result.sh — wait for a tab-agent's result file to appear, then print it.
#
# Usage:
#   poll-result.sh --worktree PATH --phase PHASE [--timeout SECONDS] [--interval SECONDS]
#
# PHASE ∈ {implementer | spec-reviewer | code-reviewer}.
# Result files are written by the tab-agent at:
#   $WORKTREE/.cmux-${PHASE}-result.md
#
# Exit codes:
#   0 = file appeared and parses (has a `status:` field). Contents printed to stdout.
#   1 = timeout reached without the file appearing.
#   2 = file appeared but is malformed (no `status:` field). Partial contents printed to stderr.

set -euo pipefail

WT=""
PHASE=""
TIMEOUT=1800
INTERVAL=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) WT="$2"; shift 2 ;;
    --phase)    PHASE="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "poll-result: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

[[ -z "$WT"    ]] && { echo "poll-result: --worktree required" >&2; exit 1; }
[[ -z "$PHASE" ]] && { echo "poll-result: --phase required (implementer|spec-reviewer|code-reviewer)" >&2; exit 1; }
[[ -d "$WT"    ]] || { echo "poll-result: worktree '$WT' does not exist" >&2; exit 1; }

case "$PHASE" in
  implementer|spec-reviewer|code-reviewer) ;;
  *) echo "poll-result: invalid --phase '$PHASE'" >&2; exit 1 ;;
esac

RESULT="$WT/.cmux-${PHASE}-result.md"

deadline=$(( $(date +%s) + TIMEOUT ))
while [[ ! -f "$RESULT" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "poll-result: timeout after ${TIMEOUT}s waiting for $RESULT" >&2
    exit 1
  fi
  sleep "$INTERVAL"
done

# Validate: must contain a `status:` field somewhere in the YAML frontmatter.
if ! grep -qE '^status:[[:space:]]*[A-Z_]+' "$RESULT"; then
  echo "poll-result: $RESULT exists but is malformed (no 'status:' field found in YAML frontmatter)" >&2
  cat "$RESULT" >&2
  exit 2
fi

cat "$RESULT"
