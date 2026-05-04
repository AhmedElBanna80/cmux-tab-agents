#!/usr/bin/env bash
# Tests for _target-path.sh — CTADEV-10 refactor
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_PATH_SH="$REPO_ROOT/scripts/dev/_target-path.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== CTADEV-10 _target-path.sh tests ===\n\n'

# T1: bash syntax check
if bash -n "$TARGET_PATH_SH" 2>/dev/null; then pass "bash -n _target-path.sh"
else fail "bash -n _target-path.sh (syntax error)"; fi

# T2: _read_manifest_fields exists after sourcing
out=$(bash -c ". '$TARGET_PATH_SH'; declare -f _read_manifest_fields" 2>&1)
if printf '%s' "$out" | grep -q '_read_manifest_fields'; then pass "_read_manifest_fields is defined"
else fail "_read_manifest_fields not defined after sourcing"; fi

# T3: _read_manifest_fields echoes name and version (space-separated)
out=$(cd "$REPO_ROOT" && bash -c ". '$TARGET_PATH_SH'; _read_manifest_fields" 2>&1)
manifest="$REPO_ROOT/.claude-plugin/plugin.json"
expected_name=$(jq -r '.name' "$manifest" 2>/dev/null)
expected_version=$(jq -r '.version' "$manifest" 2>/dev/null)
if printf '%s' "$out" | grep -qF "${expected_name} ${expected_version}"; then
  pass "_read_manifest_fields returns 'name version'"
else
  fail "_read_manifest_fields: expected '${expected_name} ${expected_version}', got: ${out}"; fi

# T4: compute_target_path still produces a path containing name and version
out=$(cd "$REPO_ROOT" && bash -c ". '$TARGET_PATH_SH'; compute_target_path" 2>&1)
if printf '%s' "$out" | grep -qF "$expected_name" && printf '%s' "$out" | grep -qF "$expected_version"; then
  pass "compute_target_path output contains name and version"
else
  fail "compute_target_path output: $out"; fi

# T5: compute_legacy_target_path still produces ~/.claude/skills/<name>
out=$(cd "$REPO_ROOT" && bash -c ". '$TARGET_PATH_SH'; compute_legacy_target_path" 2>&1)
expected_legacy="${HOME}/.claude/skills/${expected_name}"
if [[ "$out" == "$expected_legacy" ]]; then pass "compute_legacy_target_path returns correct path"
else fail "compute_legacy_target_path: expected '$expected_legacy', got '$out'"; fi

# T6: _read_manifest_fields fails with error when run outside a git repo
tmpdir=$(mktemp -d)
out=$(cd "$tmpdir" && bash -c ". '$TARGET_PATH_SH'; _read_manifest_fields" 2>&1); rc=$?
rm -rf "$tmpdir"
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q "not inside a git repository"; then
  pass "_read_manifest_fields: error outside git repo"
else
  fail "_read_manifest_fields: expected git-repo error, got rc=$rc out=$out"; fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
