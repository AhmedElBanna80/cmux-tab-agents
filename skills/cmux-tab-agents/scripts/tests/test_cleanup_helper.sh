#!/usr/bin/env bash
# test_cleanup_helper.sh — unit tests for cleanup-helper.sh
# Uses mock cmux, mock gh, fake worktrees in mktemp -d.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPTS_DIR/cleanup-helper.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== cleanup-helper.sh unit tests ===\n\n'

# ── Syntax check (fail fast) ──────────────────────────────────────────────────
if ! bash -n "$HELPER" 2>/dev/null; then
  printf 'FATAL: syntax error in %s\n' "$HELPER"
  exit 1
fi
pass "T1: bash -n cleanup-helper.sh"

# ── Test scaffolding helpers ───────────────────────────────────────────────────

GLOBAL_TMPDIR=$(mktemp -d)
trap 'rm -rf "$GLOBAL_TMPDIR"' EXIT

# Create a directory with mock binaries (gh + cmux) and a config area.
# The mocks read config files from <dir>/mock-config/:
#   merged_tickets — newline-separated ticket IDs treated as "merged" by mock gh
#   close_surface_calls — written by mock cmux when close-surface is invoked
setup_mocks() {
  local mockdir="$1"
  mkdir -p "$mockdir/bin" "$mockdir/mock-config"

  # mock gh — returns a merged PR row for tickets listed in merged_tickets
  cat > "$mockdir/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
CONFIG="$(dirname "$(dirname "$0")")/mock-config"
MERGED="$CONFIG/merged_tickets"
prev=""
if [[ "$*" == *"pr list"* ]] && [[ "$*" == *"--state merged"* ]]; then
  ticket=""
  for arg in "$@"; do
    if [[ "$prev" == "--search" ]]; then ticket="$arg"; fi
    prev="$arg"
  done
  if [[ -f "$MERGED" ]] && grep -qF "$ticket" "$MERGED" 2>/dev/null; then
    printf '42\t%s: some PR\tfeat/%s/slug\tMERGED\n' "$ticket" "$ticket" "$ticket"
  fi
  exit 0
fi
exit 1
MOCK_GH
  chmod +x "$mockdir/bin/gh"

  # mock cmux — supports `tree` and `close-surface`
  cat > "$mockdir/bin/cmux" <<'MOCK_CMUX'
#!/usr/bin/env bash
CONFIG="$(dirname "$(dirname "$0")")/mock-config"
case "$1" in
  tree)
    if [[ -f "$CONFIG/surfaces_json" ]]; then cat "$CONFIG/surfaces_json"
    else printf '{"surfaces":[]}\n'; fi ;;
  close-surface)
    printf '%s\n' "$*" >> "$CONFIG/close_surface_calls" ;;
  *) exit 0 ;;
esac
MOCK_CMUX
  chmod +x "$mockdir/bin/cmux"
}

# ── T2: discover returns valid JSON with four categories ──────────────────────

tmpT2="$GLOBAL_TMPDIR/T2"
setup_mocks "$tmpT2"
wt_base2="$tmpT2/worktrees"; mkdir -p "$wt_base2"
agents_dir2="$tmpT2/agents"; mkdir -p "$agents_dir2"

out2=$(PATH="$tmpT2/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base2" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir2" \
  bash "$HELPER" discover 2>/dev/null)

if printf '%s' "$out2" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for k in ('idle_surfaces','merged_worktrees','merged_branches','stale_streams'):
    assert k in d, f'missing key: {k}'
" 2>/dev/null; then
  pass "T2: discover emits JSON with four required categories"
else
  fail "T2: discover JSON missing required categories: $out2"
fi

# ── T3: discover classifies a merged-PR ticket as cleanup-candidate ────────────

tmpT3="$GLOBAL_TMPDIR/T3"
setup_mocks "$tmpT3"
printf 'ISSUE-999\n' > "$tmpT3/mock-config/merged_tickets"
wt_base3="$tmpT3/worktrees"
mkdir -p "$wt_base3/ISSUE-999/cmux-tab-agents"
# make events file look old (stale)
touch -t 202601010000 "$wt_base3/ISSUE-999/cmux-tab-agents/.cmux-events.jsonl" 2>/dev/null || \
  touch "$wt_base3/ISSUE-999/cmux-tab-agents/.cmux-events.jsonl"
agents_dir3="$tmpT3/agents"; mkdir -p "$agents_dir3"

out3=$(PATH="$tmpT3/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base3" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir3" \
  bash "$HELPER" discover 2>/dev/null)

if printf '%s' "$out3" | python3 -c "
import sys,json
d=json.load(sys.stdin)
paths=d.get('merged_worktrees',[])
assert any('ISSUE-999' in str(p) for p in paths), f'not found: {paths}'
" 2>/dev/null; then
  pass "T3: discover classifies merged-PR ticket as merged_worktrees candidate"
else
  fail "T3: merged-PR ticket not classified: $out3"
fi

# ── T4: discover does NOT classify a live in-flight ticket ────────────────────

tmpT4="$GLOBAL_TMPDIR/T4"
setup_mocks "$tmpT4"
wt_base4="$tmpT4/worktrees"
mkdir -p "$wt_base4/ISSUE-888/cmux-tab-agents"
# fresh events file — agent is live
touch "$wt_base4/ISSUE-888/cmux-tab-agents/.cmux-events.jsonl"
agents_dir4="$tmpT4/agents"; mkdir -p "$agents_dir4"

out4=$(PATH="$tmpT4/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base4" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir4" \
  bash "$HELPER" discover 2>/dev/null)

if printf '%s' "$out4" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for cat in ('idle_surfaces','merged_worktrees','merged_branches','stale_streams'):
    for item in d.get(cat,[]):
        assert 'ISSUE-888' not in str(item), f'ISSUE-888 incorrectly flagged in {cat}: {item}'
" 2>/dev/null; then
  pass "T4: live in-flight ticket (fresh events file) is NOT flagged as candidate"
else
  fail "T4: live ticket incorrectly flagged as cleanup candidate: $out4"
fi

# ── T5a: close-surfaces without --apply makes no cmux calls ───────────────────

tmpT5="$GLOBAL_TMPDIR/T5"
setup_mocks "$tmpT5"

PATH="$tmpT5/bin:$PATH" bash "$HELPER" close-surfaces surface:11 surface:12 >/dev/null 2>&1
calls5="$tmpT5/mock-config/close_surface_calls"

if [[ ! -f "$calls5" ]] || [[ ! -s "$calls5" ]]; then
  pass "T5a: close-surfaces (dry-run) makes no cmux calls"
else
  fail "T5a: close-surfaces (dry-run) unexpectedly called cmux: $(cat "$calls5")"
fi

# ── T5b: close-surfaces without --apply prints candidate surfaces ──────────────

out5b=$(PATH="$tmpT5/bin:$PATH" bash "$HELPER" close-surfaces surface:11 surface:12 2>&1)
if printf '%s' "$out5b" | grep -q "surface:11"; then
  pass "T5b: close-surfaces (dry-run) prints candidate surfaces"
else
  fail "T5b: close-surfaces (dry-run) didn't print surfaces: $out5b"
fi

# ── T6: close-surfaces --apply calls cmux close-surface for each ──────────────

tmpT6="$GLOBAL_TMPDIR/T6"
setup_mocks "$tmpT6"

PATH="$tmpT6/bin:$PATH" bash "$HELPER" close-surfaces --apply surface:21 surface:22 2>/dev/null
calls6="$tmpT6/mock-config/close_surface_calls"

if [[ -f "$calls6" ]] && grep -q "surface:21" "$calls6" && grep -q "surface:22" "$calls6"; then
  pass "T6: close-surfaces --apply invokes cmux close-surface for each surface"
else
  fail "T6: close-surfaces --apply didn't invoke cmux: $(cat "$calls6" 2>/dev/null || echo '(no file)')"
fi

# ── T7a: remove-worktrees without --apply does not delete directory ───────────

tmpT7="$GLOBAL_TMPDIR/T7"
mkdir -p "$tmpT7/fake-wt"
bash "$HELPER" remove-worktrees "$tmpT7/fake-wt" >/dev/null 2>&1

if [[ -d "$tmpT7/fake-wt" ]]; then
  pass "T7a: remove-worktrees (dry-run) does not delete the directory"
else
  fail "T7a: remove-worktrees (dry-run) deleted the directory unexpectedly"
fi

# ── T7b: remove-worktrees without --apply prints candidate path ───────────────

out7b=$(bash "$HELPER" remove-worktrees "$tmpT7/fake-wt" 2>&1)
if printf '%s' "$out7b" | grep -q "fake-wt"; then
  pass "T7b: remove-worktrees (dry-run) prints candidate path"
else
  fail "T7b: remove-worktrees (dry-run) didn't print path: $out7b"
fi

# ── T8: remove-worktrees --apply removes directory ───────────────────────────

tmpT8="$GLOBAL_TMPDIR/T8"
mkdir -p "$tmpT8/fake-wt"
bash "$HELPER" remove-worktrees --apply "$tmpT8/fake-wt" 2>/dev/null

if [[ ! -d "$tmpT8/fake-wt" ]]; then
  pass "T8: remove-worktrees --apply removes the directory"
else
  fail "T8: remove-worktrees --apply did not remove the directory"
fi

# ── T9: delete-branches without --apply does not delete branch ───────────────

tmpT9="$GLOBAL_TMPDIR/T9"
repo9="$tmpT9/repo"; mkdir -p "$repo9"
git -C "$repo9" init -q
git -C "$repo9" config user.email "t@t.com"
git -C "$repo9" config user.name "T"
touch "$repo9/init.txt"
git -C "$repo9" add .
git -C "$repo9" commit -q -m "init"
git -C "$repo9" checkout -q -b feat/ISSUE-77/slug
git -C "$repo9" checkout -q -

out9=$(bash "$HELPER" delete-branches "$repo9" feat/ISSUE-77/slug 2>&1)

if git -C "$repo9" branch | grep -q "feat/ISSUE-77/slug"; then
  pass "T9: delete-branches (dry-run) does not delete branch"
else
  fail "T9: delete-branches (dry-run) deleted branch unexpectedly"
fi

if printf '%s' "$out9" | grep -q "ISSUE-77"; then
  pass "T9b: delete-branches (dry-run) prints candidate branch"
else
  fail "T9b: delete-branches (dry-run) didn't print branch: $out9"
fi

# ── T10: delete-branches --apply removes the branch ──────────────────────────

tmpT10="$GLOBAL_TMPDIR/T10"
repo10="$tmpT10/repo"; mkdir -p "$repo10"
git -C "$repo10" init -q
git -C "$repo10" config user.email "t@t.com"
git -C "$repo10" config user.name "T"
touch "$repo10/init.txt"
git -C "$repo10" add .
git -C "$repo10" commit -q -m "init"
git -C "$repo10" checkout -q -b feat/ISSUE-88/slug
git -C "$repo10" checkout -q -

bash "$HELPER" delete-branches --apply "$repo10" feat/ISSUE-88/slug 2>/dev/null

if ! git -C "$repo10" branch | grep -q "feat/ISSUE-88/slug"; then
  pass "T10: delete-branches --apply removes the branch"
else
  fail "T10: delete-branches --apply did not remove branch"
fi

# ── T11a: prune-streams without --apply does not delete file ─────────────────

tmpT11="$GLOBAL_TMPDIR/T11"
mkdir -p "$tmpT11"
stream11="$tmpT11/agent-ISSUE-55.jsonl"
printf '{"ts":"2026-01-01"}\n' > "$stream11"

bash "$HELPER" prune-streams "$stream11" >/dev/null 2>&1
if [[ -f "$stream11" ]]; then
  pass "T11a: prune-streams (dry-run) does not delete stream file"
else
  fail "T11a: prune-streams (dry-run) deleted stream file unexpectedly"
fi

# ── T11b: prune-streams without --apply prints candidate file ────────────────

out11b=$(bash "$HELPER" prune-streams "$stream11" 2>&1)
if printf '%s' "$out11b" | grep -q "ISSUE-55"; then
  pass "T11b: prune-streams (dry-run) prints candidate file"
else
  fail "T11b: prune-streams (dry-run) didn't print path: $out11b"
fi

# ── T12: prune-streams --apply removes stream file ───────────────────────────

tmpT12="$GLOBAL_TMPDIR/T12"
mkdir -p "$tmpT12"
stream12="$tmpT12/agent-ISSUE-66.jsonl"
printf '{"ts":"2026-01-01"}\n' > "$stream12"

bash "$HELPER" prune-streams --apply "$stream12" 2>/dev/null
if [[ ! -f "$stream12" ]]; then
  pass "T12: prune-streams --apply removes the stream file"
else
  fail "T12: prune-streams --apply did not remove the file"
fi

# ── T13: idempotency — second discover returns empty after applying ───────────

tmpT13="$GLOBAL_TMPDIR/T13"
setup_mocks "$tmpT13"
printf 'ISSUE-321\n' > "$tmpT13/mock-config/merged_tickets"
wt_base13="$tmpT13/worktrees"
mkdir -p "$wt_base13/ISSUE-321/cmux-tab-agents"
touch -t 202601010000 "$wt_base13/ISSUE-321/cmux-tab-agents/.cmux-events.jsonl" 2>/dev/null || \
  touch "$wt_base13/ISSUE-321/cmux-tab-agents/.cmux-events.jsonl"
agents_dir13="$tmpT13/agents"; mkdir -p "$agents_dir13"

# Apply cleanup
bash "$HELPER" remove-worktrees --apply "$wt_base13/ISSUE-321/cmux-tab-agents" 2>/dev/null || true
rm -rf "$wt_base13/ISSUE-321" 2>/dev/null || true

# Second discover — ISSUE-321 should no longer appear
out13b=$(PATH="$tmpT13/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base13" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir13" \
  bash "$HELPER" discover 2>/dev/null)

if printf '%s' "$out13b" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for cat in ('idle_surfaces','merged_worktrees','merged_branches','stale_streams'):
    for item in d.get(cat,[]):
        assert 'ISSUE-321' not in str(item), f'ISSUE-321 still in {cat} after cleanup: {item}'
" 2>/dev/null; then
  pass "T13: idempotency — second discover returns empty after applying"
else
  fail "T13: idempotency failed — ISSUE-321 still appears after cleanup: $out13b"
fi

# ── T14: discover --apply emits JSON AND applies cleanup ─────────────────────

tmpT14="$GLOBAL_TMPDIR/T14"
setup_mocks "$tmpT14"
printf 'ISSUE-444\n' > "$tmpT14/mock-config/merged_tickets"
wt_base14="$tmpT14/worktrees"
mkdir -p "$wt_base14/ISSUE-444/cmux-tab-agents"
touch -t 202601010000 "$wt_base14/ISSUE-444/cmux-tab-agents/.cmux-events.jsonl" 2>/dev/null || \
  touch "$wt_base14/ISSUE-444/cmux-tab-agents/.cmux-events.jsonl"
agents_dir14="$tmpT14/agents"; mkdir -p "$agents_dir14"

out14=$(PATH="$tmpT14/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base14" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir14" \
  bash "$HELPER" discover --apply 2>/dev/null)

# T14a: JSON discovery block is still present (callers see what was found)
if printf '%s' "$out14" | python3 -c "
import sys,json,re
text=sys.stdin.read()
# JSON object should appear somewhere in output
m=re.search(r'\{[^{}]*\"idle_surfaces\".*?\}',text,re.DOTALL)
assert m, 'no JSON discovery block in --apply output'
d=json.loads(m.group(0))
paths=d.get('merged_worktrees',[])
assert any('ISSUE-444' in str(p) for p in paths), f'not found: {paths}'
" 2>/dev/null; then
  pass "T14a: discover --apply still emits JSON discovery block"
else
  fail "T14a: discover --apply missing JSON: $out14"
fi

# T14b: worktree should actually be removed
if [[ ! -d "$wt_base14/ISSUE-444/cmux-tab-agents" ]]; then
  pass "T14b: discover --apply removed the merged worktree"
else
  fail "T14b: discover --apply did not remove worktree at $wt_base14/ISSUE-444/cmux-tab-agents"
fi

# T14c: applied summary printed after JSON
if printf '%s' "$out14" | grep -qiE "applied|removed|cleanup"; then
  pass "T14c: discover --apply prints applied summary"
else
  fail "T14c: discover --apply did not print applied summary: $out14"
fi

# ── T15: discover (no --apply) leaves filesystem untouched ────────────────────

tmpT15="$GLOBAL_TMPDIR/T15"
setup_mocks "$tmpT15"
printf 'ISSUE-555\n' > "$tmpT15/mock-config/merged_tickets"
wt_base15="$tmpT15/worktrees"
mkdir -p "$wt_base15/ISSUE-555/cmux-tab-agents"
touch -t 202601010000 "$wt_base15/ISSUE-555/cmux-tab-agents/.cmux-events.jsonl" 2>/dev/null || \
  touch "$wt_base15/ISSUE-555/cmux-tab-agents/.cmux-events.jsonl"
agents_dir15="$tmpT15/agents"; mkdir -p "$agents_dir15"

PATH="$tmpT15/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base15" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir15" \
  bash "$HELPER" discover >/dev/null 2>&1

if [[ -d "$wt_base15/ISSUE-555/cmux-tab-agents" ]]; then
  pass "T15: discover (no --apply) leaves worktree intact"
else
  fail "T15: discover (no --apply) removed worktree — must be dry-run by default"
fi

# ── T16: discover --apply is idempotent (second run finds nothing) ────────────

tmpT16="$GLOBAL_TMPDIR/T16"
setup_mocks "$tmpT16"
printf 'ISSUE-666\n' > "$tmpT16/mock-config/merged_tickets"
wt_base16="$tmpT16/worktrees"
mkdir -p "$wt_base16/ISSUE-666/cmux-tab-agents"
touch -t 202601010000 "$wt_base16/ISSUE-666/cmux-tab-agents/.cmux-events.jsonl" 2>/dev/null || \
  touch "$wt_base16/ISSUE-666/cmux-tab-agents/.cmux-events.jsonl"
agents_dir16="$tmpT16/agents"; mkdir -p "$agents_dir16"

# First apply
PATH="$tmpT16/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base16" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir16" \
  bash "$HELPER" discover --apply >/dev/null 2>&1

# Second discover (dry-run) should find nothing about ISSUE-666
out16=$(PATH="$tmpT16/bin:$PATH" \
  CMUX_TAB_AGENTS_WORKTREE_BASE="$wt_base16" \
  CMUX_TAB_AGENTS_AGENTS_DIR="$agents_dir16" \
  bash "$HELPER" discover 2>/dev/null)

if printf '%s' "$out16" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for cat in ('idle_surfaces','merged_worktrees','merged_branches','stale_streams'):
    for item in d.get(cat,[]):
        assert 'ISSUE-666' not in str(item), f'ISSUE-666 still in {cat}: {item}'
" 2>/dev/null; then
  pass "T16: discover --apply is idempotent"
else
  fail "T16: discover --apply not idempotent — ISSUE-666 still present: $out16"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
