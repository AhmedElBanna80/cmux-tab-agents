#!/usr/bin/env bash
# Tests for ISSUE-136: duplicate-issue-check.sh — keyword-based circuit-breaker
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_SH="$SCRIPTS_DIR/duplicate-issue-check.sh"

PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-136: duplicate-issue-check.sh tests ===\n\n'

# T1: script exists and is readable
if [[ -r "$TARGET_SH" ]]; then
  pass "duplicate-issue-check.sh exists"
else
  fail "duplicate-issue-check.sh not found at $TARGET_SH"; exit 1
fi

# T2: bash syntax check
if bash -n "$TARGET_SH"; then
  pass "bash -n duplicate-issue-check.sh"
else
  fail "bash -n duplicate-issue-check.sh failed"; exit 1
fi

# shellcheck source=/dev/null
source "$TARGET_SH"

# T3: extract_keywords defined
if declare -f extract_keywords >/dev/null; then
  pass "defines extract_keywords"
else
  fail "extract_keywords not defined"; exit 1
fi

# T4: overlap_score defined
if declare -f overlap_score >/dev/null; then
  pass "defines overlap_score"
else
  fail "overlap_score not defined"; exit 1
fi

# T5: extract_keywords lowercases and filters stopwords
out=$(extract_keywords "The function returns the wrong VALUE for empty input")
# expect words like: function, returns, wrong, value, empty, input (not "the", "for")
if echo "$out" | grep -qx "function" \
   && echo "$out" | grep -qx "value" \
   && echo "$out" | grep -qx "empty" \
   && ! echo "$out" | grep -qx "the" \
   && ! echo "$out" | grep -qx "for"; then
  pass "extract_keywords: lowercase + stopword filtering"
else
  fail "extract_keywords output unexpected: $out"
fi

# T6: extract_keywords on empty input → empty output
out=$(extract_keywords "")
if [[ -z "$out" ]]; then
  pass "extract_keywords: empty input → empty output"
else
  fail "extract_keywords empty input produced: $out"
fi

# T7: extract_keywords keeps technical terms / identifiers
out=$(extract_keywords "issue_hash mismatch in stream-watcher.sh at line 42")
if echo "$out" | grep -qx "issue_hash" \
   && echo "$out" | grep -qx "mismatch" \
   && echo "$out" | grep -q "stream"; then
  pass "extract_keywords: preserves technical identifiers"
else
  fail "extract_keywords technical-term output unexpected: $out"
fi

# T8: overlap_score on identical non-trivial text → high overlap, is_duplicate=true
json=$(overlap_score "missing null check in parseConfig function" "missing null check in parseConfig function")
if echo "$json" | jq -e '.is_duplicate == true' >/dev/null \
   && echo "$json" | jq -e '.keyword_overlap_ratio >= 0.99' >/dev/null; then
  pass "overlap_score: identical text → is_duplicate=true"
else
  fail "overlap_score identical: $json"
fi

# T9: overlap_score on disjoint text → is_duplicate=false
json=$(overlap_score "missing null check in parseConfig" "rename variable foo to bar")
if echo "$json" | jq -e '.is_duplicate == false' >/dev/null; then
  pass "overlap_score: disjoint text → is_duplicate=false"
else
  fail "overlap_score disjoint: $json"
fi

# T10: overlap_score with 3+ matching keywords → duplicate (even if ratio < 0.7)
prev="missing null check in parseConfig function for empty input"
new="the parseConfig null check is missing when handling other completely different unrelated cases scenarios situations conditions"
json=$(overlap_score "$prev" "$new")
matches=$(echo "$json" | jq -r '.keyword_overlap_count')
if [[ "$matches" -ge 3 ]] && echo "$json" | jq -e '.is_duplicate == true' >/dev/null; then
  pass "overlap_score: ≥3 keyword matches → is_duplicate=true"
else
  fail "overlap_score 3-keyword rule: matches=$matches json=$json"
fi

# T11: overlap_score with ≥70% ratio → duplicate
prev="alpha beta gamma delta"
new="alpha beta gamma epsilon"
json=$(overlap_score "$prev" "$new")
if echo "$json" | jq -e '.keyword_overlap_ratio >= 0.7' >/dev/null \
   && echo "$json" | jq -e '.is_duplicate == true' >/dev/null; then
  pass "overlap_score: ≥70% ratio → is_duplicate=true"
else
  fail "overlap_score 70% rule: $json"
fi

# T12: check CLI — hash match alone → exit 0 (duplicate)
if bash "$TARGET_SH" check --prev-hash abc123 --new-hash abc123 \
     --prev-feedback "x" --new-feedback "y" >/dev/null 2>&1; then
  pass "CLI check: hash match → exit 0"
else
  fail "CLI check did not treat hash match as duplicate"
fi

# T13: check CLI — different hash + disjoint text → exit 1 (not duplicate)
if ! bash "$TARGET_SH" check --prev-hash aaa --new-hash bbb \
     --prev-feedback "missing null check" --new-feedback "rename variable foo" >/dev/null 2>&1; then
  pass "CLI check: different hash + disjoint text → exit 1"
else
  fail "CLI check incorrectly flagged distinct issues as duplicate"
fi

# T14: check CLI — different hash but ≥70% keyword overlap → exit 0 (semantic duplicate)
prev="alpha beta gamma delta keyword"
new="alpha beta gamma delta different"
if bash "$TARGET_SH" check --prev-hash aaa --new-hash bbb \
     --prev-feedback "$prev" --new-feedback "$new" >/dev/null 2>&1; then
  pass "CLI check: different hashes + high overlap → exit 0 (semantic duplicate)"
else
  fail "CLI check missed semantic duplicate via keyword overlap"
fi

# T15: check CLI emits JSON to stdout including hash_match and keyword fields
out=$(bash "$TARGET_SH" check --prev-hash aaa --new-hash aaa \
        --prev-feedback "x" --new-feedback "y" 2>/dev/null)
if echo "$out" | jq -e '.hash_match == true and (.keyword_overlap_count|type == "number")' >/dev/null; then
  pass "CLI check: JSON output has hash_match + keyword_overlap_count"
else
  fail "CLI check JSON malformed: $out"
fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
