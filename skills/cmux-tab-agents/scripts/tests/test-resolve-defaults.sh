#!/usr/bin/env bash
# Test: resolve_default in _dispatch_common.sh.
# Resolution order: cli > env > per-repo TOML > user-global TOML > empty.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/../_dispatch_common.sh"
[[ -r "$COMMON" ]] || { echo "missing $COMMON" >&2; exit 1; }

PHASE="test"
# shellcheck source=../_dispatch_common.sh
source "$COMMON"
set +e

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS  $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $msg"
    echo "  got:  '$got'"
    echo "  want: '$want'"
    FAIL=$((FAIL + 1))
  fi
}

REPO_CFG="$TMP/repo.toml"
USER_CFG="$TMP/user.toml"
cat >"$REPO_CFG" <<'EOF'
default_model = "claude-sonnet-4-6"
default_effort = "high"
EOF
cat >"$USER_CFG" <<'EOF'
default_model = "claude-haiku-4-5-20251001"
default_effort = "medium"
EOF

unset CMUX_TAB_AGENTS_DEFAULT_MODEL CMUX_TAB_AGENTS_DEFAULT_EFFORT

# 1. CLI wins over env + both configs.
got=$(REPO_CONFIG="$REPO_CFG" USER_CONFIG="$USER_CFG" \
  CMUX_TAB_AGENTS_DEFAULT_MODEL="from-env" \
  resolve_default default_model CMUX_TAB_AGENTS_DEFAULT_MODEL "from-cli")
assert_eq "$got" "from-cli" "CLI > env > configs"

# 2. env wins over both configs when CLI empty.
got=$(REPO_CONFIG="$REPO_CFG" USER_CONFIG="$USER_CFG" \
  CMUX_TAB_AGENTS_DEFAULT_MODEL="from-env" \
  resolve_default default_model CMUX_TAB_AGENTS_DEFAULT_MODEL "")
assert_eq "$got" "from-env" "env > per-repo > user-global"

# 3. per-repo wins over user-global when CLI + env empty.
got=$(REPO_CONFIG="$REPO_CFG" USER_CONFIG="$USER_CFG" \
  resolve_default default_model CMUX_TAB_AGENTS_DEFAULT_MODEL "")
assert_eq "$got" "claude-sonnet-4-6" "per-repo > user-global"

# 4. user-global is consulted when per-repo is empty/unset.
got=$(REPO_CONFIG="" USER_CONFIG="$USER_CFG" \
  resolve_default default_model CMUX_TAB_AGENTS_DEFAULT_MODEL "")
assert_eq "$got" "claude-haiku-4-5-20251001" "user-global when no per-repo"

# 5. empty when nothing set anywhere.
got=$(REPO_CONFIG="" USER_CONFIG="" \
  resolve_default default_model CMUX_TAB_AGENTS_DEFAULT_MODEL "")
assert_eq "$got" "" "empty when nothing set"

# 6. effort uses the same machinery.
got=$(REPO_CONFIG="$REPO_CFG" USER_CONFIG="$USER_CFG" \
  resolve_default default_effort CMUX_TAB_AGENTS_DEFAULT_EFFORT "")
assert_eq "$got" "high" "effort: per-repo > user-global"

# 7. effort env override.
got=$(REPO_CONFIG="$REPO_CFG" USER_CONFIG="$USER_CFG" \
  CMUX_TAB_AGENTS_DEFAULT_EFFORT="xhigh" \
  resolve_default default_effort CMUX_TAB_AGENTS_DEFAULT_EFFORT "")
assert_eq "$got" "xhigh" "effort: env > configs"

# 8. per-repo file with only one key, user-global with both — fall through per key.
PARTIAL_REPO="$TMP/partial-repo.toml"
cat >"$PARTIAL_REPO" <<'EOF'
default_model = "only-model-here"
EOF
got=$(REPO_CONFIG="$PARTIAL_REPO" USER_CONFIG="$USER_CFG" \
  resolve_default default_effort CMUX_TAB_AGENTS_DEFAULT_EFFORT "")
assert_eq "$got" "medium" "per-key fall-through: missing in repo, present in user-global"

# 9. quoted single-quote values are unwrapped.
SQ_CFG="$TMP/sq.toml"
cat >"$SQ_CFG" <<'EOF'
default_effort = 'low'
EOF
got=$(REPO_CONFIG="" USER_CONFIG="$SQ_CFG" \
  resolve_default default_effort CMUX_TAB_AGENTS_DEFAULT_EFFORT "")
assert_eq "$got" "low" "single-quoted value unwrapped"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
