#!/usr/bin/env bash
# Tests for dev-link.sh + dev-unlink.sh.
#
# All tests use a sandbox $PREFIX (passed via --prefix) instead of $HOME/.claude
# so they never touch the real user-scope plugin tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SCRIPTS="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK="$REPO_SCRIPTS/dev-link.sh"
UNLINK="$REPO_SCRIPTS/dev-unlink.sh"
[[ -x "$LINK"   ]] || { echo "missing $LINK" >&2; exit 1; }
[[ -x "$UNLINK" ]] || { echo "missing $UNLINK" >&2; exit 1; }

PASS=0
FAIL=0

assert() {
  local cond="$1" msg="$2"
  if eval "$cond"; then
    echo "PASS  $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $msg  ::  $cond"
    FAIL=$((FAIL + 1))
  fi
}

# Build a fake repo and a fake $PREFIX in $TMP.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
PREFIX="$TMP/dotclaude"
mkdir -p "$REPO/skills/cmux-tab-agents" "$REPO/commands" "$PREFIX/skills" "$PREFIX/commands"
echo "stub" > "$REPO/skills/cmux-tab-agents/SKILL.md"
echo "stub" > "$REPO/commands/setup.md"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit --allow-empty -q -m initial

# 1. Fresh link: creates both symlinks pointing into the repo.
"$LINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
assert "[[ -L '$PREFIX/skills/cmux-tab-agents' ]]" "1: skill symlink created"
assert "[[ \"\$(readlink '$PREFIX/skills/cmux-tab-agents')\" == '$REPO/skills/cmux-tab-agents' ]]" \
  "1: skill symlink target correct"
assert "[[ -L '$PREFIX/commands/cmux-tab-agents' ]]" "1: commands symlink created"
assert "[[ \"\$(readlink '$PREFIX/commands/cmux-tab-agents')\" == '$REPO/commands' ]]" \
  "1: commands symlink target correct"

# 2. Idempotent: re-running is a no-op (same symlinks).
"$LINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
assert "[[ \"\$(readlink '$PREFIX/skills/cmux-tab-agents')\" == '$REPO/skills/cmux-tab-agents' ]]" \
  "2: idempotent skill"
assert "[[ \"\$(readlink '$PREFIX/commands/cmux-tab-agents')\" == '$REPO/commands' ]]" \
  "2: idempotent commands"

# 3. Stale symlink (points elsewhere) gets replaced silently.
rm "$PREFIX/skills/cmux-tab-agents"
ln -s /tmp/somewhere-else "$PREFIX/skills/cmux-tab-agents"
"$LINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
assert "[[ \"\$(readlink '$PREFIX/skills/cmux-tab-agents')\" == '$REPO/skills/cmux-tab-agents' ]]" \
  "3: stale symlink replaced"

# 4. Real directory in the way: refuse without --force.
"$UNLINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
mkdir -p "$PREFIX/skills/cmux-tab-agents"
echo "real" > "$PREFIX/skills/cmux-tab-agents/some-file"
out=$("$LINK" --repo "$REPO" --prefix "$PREFIX" 2>&1)
rc=$?
assert "[[ $rc -ne 0 ]]" "4: refuses (exit !=0) when real dir present"
assert "[[ \"$out\" == *force* ]]" "4: error mentions --force"
assert "[[ -d '$PREFIX/skills/cmux-tab-agents' ]]" "4: real dir untouched"
assert "[[ -f '$PREFIX/skills/cmux-tab-agents/some-file' ]]" "4: real dir contents intact"

# 5. --force replaces the real directory.
"$LINK" --repo "$REPO" --prefix "$PREFIX" --force >/dev/null 2>&1
assert "[[ -L '$PREFIX/skills/cmux-tab-agents' ]]" "5: --force replaces real dir with symlink"

# 6. Refuses when --repo is not a git repo.
NOTREPO="$TMP/notgit"
mkdir -p "$NOTREPO/skills/cmux-tab-agents"
out=$("$LINK" --repo "$NOTREPO" --prefix "$PREFIX" 2>&1)
rc=$?
assert "[[ $rc -ne 0 ]]" "6: refuses when --repo is not a git repo"
assert "[[ \"$out\" == *git* ]]" "6: error mentions git"

# 7. Refuses when --repo is missing skills/cmux-tab-agents.
NOSKILL="$TMP/noskill"
mkdir -p "$NOSKILL"
git -C "$NOSKILL" init -q
git -C "$NOSKILL" -c user.email=t@t -c user.name=t commit --allow-empty -q -m initial
out=$("$LINK" --repo "$NOSKILL" --prefix "$PREFIX" 2>&1)
rc=$?
assert "[[ $rc -ne 0 ]]" "7: refuses when skills/cmux-tab-agents missing"
assert "[[ \"$out\" == *skills/cmux-tab-agents* ]]" "7: error names the missing path"

# 8. Pre-phase-2 worktree (no commands/ dir): only links the skill.
NOCOMMANDS="$TMP/nocmds"
mkdir -p "$NOCOMMANDS/skills/cmux-tab-agents"
git -C "$NOCOMMANDS" init -q
git -C "$NOCOMMANDS" -c user.email=t@t -c user.name=t commit --allow-empty -q -m initial
PREFIX2="$TMP/dotclaude2"
mkdir -p "$PREFIX2/skills" "$PREFIX2/commands"
out=$("$LINK" --repo "$NOCOMMANDS" --prefix "$PREFIX2" 2>&1)
rc=$?
assert "[[ $rc -eq 0 ]]" "8: succeeds when commands/ missing (skill only)"
assert "[[ -L '$PREFIX2/skills/cmux-tab-agents' ]]" "8: skill linked"
assert "[[ ! -e '$PREFIX2/commands/cmux-tab-agents' ]]" "8: commands not linked when source missing"
assert "[[ \"$out\" == *commands*missing* || \"$out\" == *commands*skip* ]]" \
  "8: notice mentions commands skip"

# 9. dev-unlink: removes only symlinks pointing into our repo.
"$LINK" --repo "$REPO" --prefix "$PREFIX" --force >/dev/null 2>&1
"$UNLINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
assert "[[ ! -e '$PREFIX/skills/cmux-tab-agents' ]]" "9: skill symlink removed"
assert "[[ ! -e '$PREFIX/commands/cmux-tab-agents' ]]" "9: commands symlink removed"

# 10. dev-unlink: refuses to remove a real directory.
mkdir -p "$PREFIX/skills/cmux-tab-agents"
echo "real-content" > "$PREFIX/skills/cmux-tab-agents/file"
"$UNLINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
assert "[[ -d '$PREFIX/skills/cmux-tab-agents' ]]" "10: real dir not removed by unlink"
assert "[[ -f '$PREFIX/skills/cmux-tab-agents/file' ]]" "10: real dir contents intact"

# 11. dev-unlink: leaves alone symlinks pointing at unrelated targets.
rm -rf "$PREFIX/skills/cmux-tab-agents"
ln -s /tmp/unrelated "$PREFIX/skills/cmux-tab-agents"
"$UNLINK" --repo "$REPO" --prefix "$PREFIX" >/dev/null 2>&1
assert "[[ -L '$PREFIX/skills/cmux-tab-agents' ]]" "11: unrelated symlink not removed"
rm "$PREFIX/skills/cmux-tab-agents"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
