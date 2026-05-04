#!/usr/bin/env bash
# Tests for version-bump.sh — bumps `version` in plugin.json AND
# marketplace.json in lockstep, makes a commit, tags vX.Y.Z. Refuses if dirty.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="$(cd "$SCRIPT_DIR/.." && pwd)/version-bump.sh"
[[ -x "$BUMP" ]] || { echo "missing $BUMP" >&2; exit 1; }

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS  $msg"; PASS=$((PASS + 1))
  else
    echo "FAIL  $msg"; echo "  got: '$got'"; echo "  want: '$want'"; FAIL=$((FAIL + 1))
  fi
}
assert() {
  if eval "$1"; then echo "PASS  $2"; PASS=$((PASS + 1)); else echo "FAIL  $2  ::  $1"; FAIL=$((FAIL + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build a fake repo with the two manifests.
REPO="$TMP/repo"
mkdir -p "$REPO/.claude-plugin"
cat >"$REPO/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "cmux-tab-agents",
  "version": "0.2.1",
  "description": "x"
}
EOF
cat >"$REPO/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "cmux-tab-agents",
  "plugins": [
    {
      "name": "cmux-tab-agents",
      "version": "0.2.1"
    }
  ]
}
EOF
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t add . >/dev/null
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "initial 0.2.1"

# Helper: read the current version from each manifest.
plugin_v() { python3 -c "import json,sys; print(json.load(open('$REPO/.claude-plugin/plugin.json'))['version'])"; }
market_v() { python3 -c "import json,sys; print(json.load(open('$REPO/.claude-plugin/marketplace.json'))['plugins'][0]['version'])"; }

# 1. patch bump on a clean repo: 0.2.1 → 0.2.2.
(cd "$REPO" && git config user.email t@t && git config user.name t)
"$BUMP" patch --repo "$REPO" >/dev/null 2>&1
rc=$?
assert_eq "$rc" "0" "1: patch exit 0"
assert_eq "$(plugin_v)" "0.2.2" "1: plugin.json bumped"
assert_eq "$(market_v)" "0.2.2" "1: marketplace.json bumped in lockstep"
assert "git -C '$REPO' tag -l v0.2.2 | grep -q ." "1: tag v0.2.2 created"
assert "git -C '$REPO' log --oneline -1 | grep -q '0.2.2'" "1: commit references 0.2.2"

# 2. minor bump: 0.2.2 → 0.3.0.
"$BUMP" minor --repo "$REPO" >/dev/null 2>&1
assert_eq "$(plugin_v)" "0.3.0" "2: minor → 0.3.0"
assert_eq "$(market_v)" "0.3.0" "2: marketplace 0.3.0"
assert "git -C '$REPO' tag -l v0.3.0 | grep -q ." "2: tag v0.3.0"

# 3. major bump: 0.3.0 → 1.0.0.
"$BUMP" major --repo "$REPO" >/dev/null 2>&1
assert_eq "$(plugin_v)" "1.0.0" "3: major → 1.0.0"
assert_eq "$(market_v)" "1.0.0" "3: marketplace 1.0.0"
assert "git -C '$REPO' tag -l v1.0.0 | grep -q ." "3: tag v1.0.0"

# 4. refuses on dirty working tree.
echo "scratch" >"$REPO/dirty.txt"
out=$("$BUMP" patch --repo "$REPO" 2>&1)
rc=$?
assert "[[ $rc -ne 0 ]]" "4: refuses when dirty"
assert "[[ \"$out\" == *dirty* || \"$out\" == *clean* ]]" "4: error mentions dirty/clean"
assert_eq "$(plugin_v)" "1.0.0" "4: version unchanged after refusal"
rm "$REPO/dirty.txt"

# 5. refuses unknown bump kind.
out=$("$BUMP" wat --repo "$REPO" 2>&1)
rc=$?
assert "[[ $rc -ne 0 ]]" "5: refuses unknown bump"
assert "[[ \"$out\" == *major* && \"$out\" == *minor* && \"$out\" == *patch* ]]" \
  "5: error lists valid kinds"

# 6. refuses if a tag for the new version already exists.
git -C "$REPO" tag v1.0.1 2>/dev/null
out=$("$BUMP" patch --repo "$REPO" 2>&1)
rc=$?
assert "[[ $rc -ne 0 ]]" "6: refuses pre-existing tag"
assert "[[ \"$out\" == *v1.0.1* ]]" "6: error names the conflicting tag"

# 7. mismatched versions across manifests: refuse with clear message.
git -C "$REPO" tag -d v1.0.1 >/dev/null 2>&1
python3 -c "import json; p='$REPO/.claude-plugin/marketplace.json'; d=json.load(open(p)); d['plugins'][0]['version']='9.9.9'; open(p,'w').write(json.dumps(d, indent=2))"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -aq -m "deliberate mismatch"
out=$("$BUMP" patch --repo "$REPO" 2>&1)
rc=$?
# Either it refuses (preferred) or it bumps based on plugin.json — make the contract:
# refuse, since lockstep means caller must reconcile first.
assert "[[ $rc -ne 0 ]]" "7: refuses on manifest version mismatch"
assert "[[ \"$out\" == *mismatch* || \"$out\" == *9.9.9* ]]" "7: error names the mismatch"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
