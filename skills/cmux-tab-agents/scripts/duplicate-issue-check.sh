#!/usr/bin/env bash
# duplicate-issue-check.sh — ISSUE-136 circuit-breaker hash-stability fix.
#
# The original implementer circuit-breaker compared reviewer issue_hash values
# verbatim. VALIDATE-003 showed that the same semantic issue can be re-emitted
# with a different hash (because the reviewer rephrased the feedback), letting
# the loop bypass the "same issue twice in a row" rule. This helper adds a
# secondary keyword-overlap check so semantic duplicates are detected even when
# their hashes differ.
#
# Library usage (source it):
#   source duplicate-issue-check.sh
#   extract_keywords "<text>"                       # one keyword per line
#   overlap_score   "<prev>" "<new>"                # JSON report
#
# CLI usage:
#   duplicate-issue-check.sh check \
#     --prev-hash <h1> --new-hash <h2> \
#     --prev-feedback <text1> --new-feedback <text2>
#
# Exit 0 → duplicate detected (hash match OR semantic overlap).
# Exit 1 → not a duplicate.
# Always prints a JSON report on stdout describing the decision.

set -o pipefail

# Stopwords kept short on purpose: common English glue words that carry no
# technical signal. Anything not in this set survives extraction, which means
# identifiers (parseConfig, issue_hash, stream-watcher) pass through intact.
_DUP_STOPWORDS=" the a an and or but if then else for to of in on at by is are was were be been being it its this that these those with from as not no into via per when while do does did has have had can will would should could may might must i you we they he she them us our your their my me him her so than too very just also only such own same other another any some all each every both either neither here there where why how what which who whom whose "

# Lowercase + tokenize + drop stopwords + drop pure-number tokens + drop length<3.
# Keeps underscores, hyphens, dots inside tokens (so identifiers survive).
extract_keywords() {
  local text="${1:-}"
  [[ -z "$text" ]] && return 0
  printf '%s\n' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9_.-' '\n' \
    | awk -v sw="$_DUP_STOPWORDS" '
        {
          gsub(/^[._-]+|[._-]+$/, "", $0)
          if (length($0) < 3) next
          if ($0 ~ /^[0-9]+$/) next
          if (index(sw, " " $0 " ") > 0) next
          if (seen[$0]++) next
          print $0
        }
      '
}

# Compute keyword overlap between two free-text feedback strings.
# Emits a JSON object on stdout:
#   {
#     "prev_keywords": N,
#     "new_keywords":  M,
#     "keyword_overlap_count": K,
#     "keyword_overlap_ratio": K / max(N, M),
#     "is_duplicate": bool,
#     "reason": "..."
#   }
#
# Duplicate rule (semantic): is_duplicate=true when K >= 3 OR ratio >= 0.7.
# We compare against max(N, M) so a tiny rephrasing isn't drowned out by a
# longer second message that happens to drag in unrelated words.
overlap_score() {
  local prev="${1:-}"
  local new="${2:-}"
  local prev_kw new_kw
  prev_kw=$(extract_keywords "$prev")
  new_kw=$(extract_keywords "$new")

  local prev_n new_n overlap
  prev_n=$(printf '%s\n' "$prev_kw" | grep -c .)
  new_n=$(printf '%s\n' "$new_kw"  | grep -c .)
  if [[ "$prev_n" -eq 0 || "$new_n" -eq 0 ]]; then
    overlap=0
  else
    overlap=$(comm -12 \
      <(printf '%s\n' "$prev_kw" | sort -u) \
      <(printf '%s\n' "$new_kw"  | sort -u) \
      | grep -c . || true)
  fi

  local max_n="$prev_n"
  [[ "$new_n" -gt "$max_n" ]] && max_n="$new_n"

  local ratio is_dup reason
  if [[ "$max_n" -eq 0 ]]; then
    ratio="0"; is_dup=false; reason="empty-input"
  else
    ratio=$(awk -v a="$overlap" -v b="$max_n" 'BEGIN{printf "%.4f", a/b}')
    if [[ "$overlap" -ge 3 ]]; then
      is_dup=true; reason="keyword-count>=3"
    elif awk -v r="$ratio" 'BEGIN{exit !(r+0 >= 0.7)}'; then
      is_dup=true; reason="keyword-ratio>=0.7"
    else
      is_dup=false; reason="below-thresholds"
    fi
  fi

  jq -nc \
    --argjson prev_n "$prev_n" \
    --argjson new_n "$new_n" \
    --argjson overlap "$overlap" \
    --argjson ratio "$ratio" \
    --argjson is_dup "$is_dup" \
    --arg reason "$reason" \
    '{prev_keywords:$prev_n, new_keywords:$new_n,
      keyword_overlap_count:$overlap, keyword_overlap_ratio:$ratio,
      is_duplicate:$is_dup, reason:$reason}'
}

# CLI: `duplicate-issue-check.sh check --prev-hash H1 --new-hash H2 \
#         --prev-feedback T1 --new-feedback T2`
_dup_check_cli() {
  local prev_hash="" new_hash="" prev_fb="" new_fb=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prev-hash)     prev_hash="$2"; shift 2 ;;
      --new-hash)      new_hash="$2";  shift 2 ;;
      --prev-feedback) prev_fb="$2";   shift 2 ;;
      --new-feedback)  new_fb="$2";    shift 2 ;;
      *) shift ;;
    esac
  done

  local hash_match=false
  if [[ -n "$prev_hash" && "$prev_hash" == "$new_hash" ]]; then
    hash_match=true
  fi

  local score_json
  score_json=$(overlap_score "$prev_fb" "$new_fb")

  local kw_dup
  kw_dup=$(echo "$score_json" | jq -r '.is_duplicate')

  local final_dup final_reason
  if [[ "$hash_match" == "true" ]]; then
    final_dup=true; final_reason="hash-match"
  elif [[ "$kw_dup" == "true" ]]; then
    final_dup=true
    final_reason=$(echo "$score_json" | jq -r '.reason')
  else
    final_dup=false; final_reason="distinct-issue"
  fi

  echo "$score_json" | jq -c \
    --argjson hash_match "$hash_match" \
    --argjson is_dup "$final_dup" \
    --arg reason "$final_reason" \
    '. + {hash_match:$hash_match, is_duplicate:$is_dup, reason:$reason}'

  [[ "$final_dup" == "true" ]]
}

# Only run CLI when invoked directly (not when sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    check) shift; _dup_check_cli "$@" ;;
    "")
      echo "usage: duplicate-issue-check.sh check --prev-hash H1 --new-hash H2 --prev-feedback T1 --new-feedback T2" >&2
      exit 2 ;;
    *)
      echo "unknown subcommand: $1" >&2
      exit 2 ;;
  esac
fi
