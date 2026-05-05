#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

failures=0

# Check 1: shellcheck
printf '==> shellcheck\n'
if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'WARN: shellcheck not installed; skipping shell lint. brew install shellcheck\n'
else
  shellcheck_ok=1
  for dir in "$REPO_ROOT/skills/cmux-tab-agents/scripts" "$REPO_ROOT/scripts/dev"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r f; do
        # -x: follow source directives so cross-file usage is visible.
        # --severity=warning: drop info-level noise like SC1091 when shellcheck
        # can't resolve a relative source path from the invocation cwd.
        # (SC2034 false positives are silenced via per-line disable directives
        # on the wrappers' PHASE assignments.)
        if ! shellcheck -x --severity=warning "$f"; then
          shellcheck_ok=0
        fi
      done < <(find "$dir" -name '*.sh' -type f 2>/dev/null | sort)
    fi
  done
  if [[ "$shellcheck_ok" -eq 1 ]]; then
    printf 'OK\n'
  else
    failures=$((failures + 1))
  fi
fi

# Check 2: JSON validation
printf '==> json-validation\n'
json_ok=1
for f in "$REPO_ROOT/.claude-plugin/plugin.json" "$REPO_ROOT/.claude-plugin/marketplace.json"; do
  if ! jq empty "$f" 2>/dev/null; then
    printf 'FAIL: %s\n' "$f"
    json_ok=0
  fi
done
if [[ "$json_ok" -eq 1 ]]; then
  printf 'OK\n'
else
  failures=$((failures + 1))
fi

# Check 3: cmux-gitignore
printf '==> cmux-gitignore\n'
if grep -qF '.cmux-*' "$REPO_ROOT/.gitignore" 2>/dev/null; then
  printf 'OK\n'
else
  printf 'FAIL: .gitignore must contain .cmux-* to prevent result file commits\n'
  failures=$((failures + 1))
fi

# Check 4: prompt-template lint
printf '==> prompt-template-lint\n'
prompt_ok=1
for phase in implementer spec-reviewer code-reviewer; do
  if ! bash "$SCRIPT_DIR/render-prompt.sh" "$phase" --check; then
    prompt_ok=0
  fi
done
if [[ "$prompt_ok" -eq 1 ]]; then
  printf 'OK\n'
else
  failures=$((failures + 1))
fi

printf '\nlint: 4 checks ran, %d failures\n' "$failures"
if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
