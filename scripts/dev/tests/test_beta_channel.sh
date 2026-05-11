#!/usr/bin/env bash
# Acceptance tests for ISSUE-95: beta release channel infrastructure
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '=== ISSUE-95 beta channel acceptance tests ===\n\n'

MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
BETA_CONFIG="$REPO_ROOT/release-please-config-beta.json"
BETA_WORKFLOW="$REPO_ROOT/.github/workflows/release-please-beta.yml"
BETA_DOC="$REPO_ROOT/BETA.md"

# T1: marketplace.json has exactly 2 plugin entries
count=$(jq '.plugins | length' "$MARKETPLACE" 2>/dev/null || echo 0)
if [[ "$count" -eq 2 ]]; then pass "marketplace has 2 plugin entries"
else fail "marketplace has 2 plugin entries (got $count)"; fi

# T2: second entry name is cmux-tab-agents-beta
name=$(jq -r '.plugins[1].name' "$MARKETPLACE" 2>/dev/null || echo "")
if [[ "$name" == "cmux-tab-agents-beta" ]]; then pass "plugins[1].name is cmux-tab-agents-beta"
else fail "plugins[1].name is cmux-tab-agents-beta (got '$name')"; fi

# T3: beta entry has a version field
version=$(jq -r '.plugins[1].version' "$MARKETPLACE" 2>/dev/null || echo "null")
if [[ "$version" != "null" && -n "$version" ]]; then pass "plugins[1].version is set"
else fail "plugins[1].version is set (got '$version')"; fi

# T4: beta entry version looks like a pre-release (contains 'beta')
if printf '%s' "$version" | grep -q 'beta'; then pass "plugins[1].version is a beta pre-release"
else fail "plugins[1].version is a beta pre-release (got '$version')"; fi

# T5: release-please-config-beta.json exists
if [[ -f "$BETA_CONFIG" ]]; then pass "release-please-config-beta.json exists"
else fail "release-please-config-beta.json exists"; fi

# T6: beta config is valid JSON
if jq empty "$BETA_CONFIG" 2>/dev/null; then pass "release-please-config-beta.json is valid JSON"
else fail "release-please-config-beta.json is valid JSON"; fi

# T7: beta config has prerelease: true
prerelease=$(jq -r '.packages["."].prerelease' "$BETA_CONFIG" 2>/dev/null || echo "false")
if [[ "$prerelease" == "true" ]]; then pass "beta config has prerelease: true"
else fail "beta config has prerelease: true (got '$prerelease')"; fi

# T8: beta config has prerelease-type: beta
prerelease_type=$(jq -r '."packages"["."]["prerelease-type"]' "$BETA_CONFIG" 2>/dev/null || echo "")
if [[ "$prerelease_type" == "beta" ]]; then pass "beta config has prerelease-type: beta"
else fail "beta config has prerelease-type: beta (got '$prerelease_type')"; fi

# T9: beta config package-name is cmux-tab-agents-beta
pkg_name=$(jq -r '.packages["."]["package-name"]' "$BETA_CONFIG" 2>/dev/null || echo "")
if [[ "$pkg_name" == "cmux-tab-agents-beta" ]]; then pass "beta config package-name is cmux-tab-agents-beta"
else fail "beta config package-name is cmux-tab-agents-beta (got '$pkg_name')"; fi

# T10: beta workflow exists
if [[ -f "$BETA_WORKFLOW" ]]; then pass "release-please-beta.yml workflow exists"
else fail "release-please-beta.yml workflow exists"; fi

# T11: beta workflow triggers on beta branch
if grep -q 'beta' "$BETA_WORKFLOW" 2>/dev/null; then pass "beta workflow references beta branch"
else fail "beta workflow references beta branch"; fi

# T12: beta workflow uses beta config file
if grep -q 'release-please-config-beta.json' "$BETA_WORKFLOW" 2>/dev/null; then pass "beta workflow uses release-please-config-beta.json"
else fail "beta workflow uses release-please-config-beta.json"; fi

# T13: BETA.md exists
if [[ -f "$BETA_DOC" ]]; then pass "BETA.md exists"
else fail "BETA.md exists"; fi

# T14: BETA.md documents the beta branch workflow
if grep -q 'beta' "$BETA_DOC" 2>/dev/null; then pass "BETA.md mentions beta branch"
else fail "BETA.md mentions beta branch"; fi

printf '\n=== Results: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
