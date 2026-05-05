#!/usr/bin/env bash
# poll-result.sh — wait for a tab-agent's result file to appear, then print it.
#
# Usage:
#   poll-result.sh --worktree PATH --phase PHASE [--timeout SECONDS] [--interval SECONDS]
#                  [--full] [--frontmatter-only]
#
# PHASE ∈ {implementer | spec-reviewer | code-reviewer}.
# Result files are written by the tab-agent at:
#   $WORKTREE/.cmux-${PHASE}-result.md
#
# Flags:
#   --full               Emit entire file content (default: truncate to 30 body lines)
#   --frontmatter-only   Emit only YAML frontmatter (no body)
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
FULL_OUTPUT=false
FRONTMATTER_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)        WT="$2"; shift 2 ;;
    --phase)           PHASE="$2"; shift 2 ;;
    --timeout)         TIMEOUT="$2"; shift 2 ;;
    --interval)        INTERVAL="$2"; shift 2 ;;
    --full)            FULL_OUTPUT=true; shift ;;
    --frontmatter-only) FRONTMATTER_ONLY=true; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# //;s/^#//'
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

# Extract frontmatter and body
frontmatter=""
body=""
in_frontmatter=false
frontmatter_end_count=0

while IFS= read -r line; do
  if [[ "$line" == "---" ]]; then
    frontmatter_end_count=$((frontmatter_end_count + 1))
    if [[ $frontmatter_end_count -eq 1 ]]; then
      in_frontmatter=true
      frontmatter+="$line"$'\n'
    elif [[ $frontmatter_end_count -eq 2 ]]; then
      frontmatter+="$line"$'\n'
      in_frontmatter=false
      continue
    fi
  elif [[ $in_frontmatter == true ]]; then
    frontmatter+="$line"$'\n'
  elif [[ $frontmatter_end_count -eq 2 ]]; then
    body+="$line"$'\n'
  fi
done < "$RESULT"

# Output based on flags
if [[ "$FRONTMATTER_ONLY" == true ]]; then
  echo -n "$frontmatter"
elif [[ "$FULL_OUTPUT" == true ]]; then
  cat "$RESULT"
else
  # Default: frontmatter + up to 30 body lines + truncation marker if needed
  echo -n "$frontmatter"

  # Count lines in body
  body_line_count=$(echo -n "$body" | grep -c . || true)

  if [[ $body_line_count -le 30 ]]; then
    # Body is short enough, print it all
    echo -n "$body"
  else
    # Truncate: print first 30 lines + marker
    echo "$body" | head -n 30
    echo "… (truncated; use --full for entire body) …"
  fi
fi
