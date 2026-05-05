#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Canonical allowlist — must match _dispatch_common.sh render_template mapping.
# PLANNER_SURFACE included for forward compatibility (not yet handled in dispatch).
ALLOWLIST="TICKET TITLE SLUG WORKTREE PLANNER_WORKSPACE PLANNER_SURFACE TASK IMPLEMENTER_SHA FEEDBACK SKILL_BASE FINISH_MODE LEAD_SURFACE MAX_LOOP_ITERATIONS OWN_SURFACE"

# Sample defaults used when --values does not override a key.
_DEF_TICKET="ALPM-DEV-1"
_DEF_TITLE="sample title"
_DEF_SLUG="sample-slug"
_DEF_WORKTREE="/tmp/sample-worktree"
_DEF_PLANNER_WORKSPACE="workspace:99"
_DEF_PLANNER_SURFACE="surface:99"
_DEF_IMPLEMENTER_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
_DEF_SKILL_BASE="$REPO_ROOT/skills/cmux-tab-agents"
# TASK and FEEDBACK go through env to sidestep quoting issues with multiline text.
_DEF_TASK='Sample task body. Replace via --values TASK="...".'
_DEF_FEEDBACK=""
_DEF_LEAD_SURFACE="surface:0"
_DEF_MAX_LOOP_ITERATIONS="5"
_DEF_OWN_SURFACE="surface:0"

PHASE=""
CHECK=0
VALUES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK=1; shift ;;
    --values)
      if [[ $# -lt 2 ]]; then
        echo "render-prompt.sh: --values requires an argument" >&2; exit 1
      fi
      VALUES="$2"; shift 2 ;;
    -*)
      echo "render-prompt.sh: unknown option '$1'" >&2; exit 1 ;;
    *)
      if [[ -z "$PHASE" ]]; then
        PHASE="$1"
      else
        echo "render-prompt.sh: unexpected argument '$1'" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$PHASE" ]]; then
  printf 'Usage: render-prompt.sh <implementer|spec-reviewer|code-reviewer> [--values KEY=VAL,...] [--check]\n' >&2
  exit 1
fi

case "$PHASE" in
  implementer|spec-reviewer|code-reviewer) ;;
  *)
    echo "render-prompt.sh: invalid phase '$PHASE' (valid: implementer, spec-reviewer, code-reviewer)" >&2
    exit 1 ;;
esac

TEMPLATE="$REPO_ROOT/skills/cmux-tab-agents/prompts/${PHASE}-tab-prompt.md"
if [[ ! -r "$TEMPLATE" ]]; then
  echo "render-prompt.sh: template not found: $TEMPLATE" >&2
  exit 1
fi

_RENDER_TASK="$_DEF_TASK" \
_RENDER_FEEDBACK="$_DEF_FEEDBACK" \
python3 - "$TEMPLATE" "$ALLOWLIST" "$VALUES" "$PHASE" "$CHECK" \
          "$_DEF_TICKET" "$_DEF_TITLE" "$_DEF_SLUG" "$_DEF_WORKTREE" \
          "$_DEF_PLANNER_WORKSPACE" "$_DEF_PLANNER_SURFACE" "$_DEF_IMPLEMENTER_SHA" "$_DEF_SKILL_BASE" \
          "keep" "$_DEF_LEAD_SURFACE" "$_DEF_MAX_LOOP_ITERATIONS" "$_DEF_OWN_SURFACE" <<'PY'
import sys, re, os

template_path  = sys.argv[1]
allowlist      = sys.argv[2].split()
values_str     = sys.argv[3]
phase          = sys.argv[4]
check_mode     = sys.argv[5] == "1"

defaults = {
    "TICKET":            sys.argv[6],
    "TITLE":             sys.argv[7],
    "SLUG":              sys.argv[8],
    "WORKTREE":          sys.argv[9],
    "PLANNER_WORKSPACE": sys.argv[10],
    "PLANNER_SURFACE":   sys.argv[11],
    "IMPLEMENTER_SHA":   sys.argv[12],
    "SKILL_BASE":        sys.argv[13],
    "FINISH_MODE":          sys.argv[14],
    "LEAD_SURFACE":         sys.argv[15],
    "MAX_LOOP_ITERATIONS":  sys.argv[16],
    "OWN_SURFACE":          sys.argv[17],
    "TASK":                 os.environ.get("_RENDER_TASK", ""),
    "FEEDBACK":             os.environ.get("_RENDER_FEEDBACK", ""),
}

overrides = {}
if values_str:
    for pair in values_str.split(","):
        eq = pair.find("=")
        if eq == -1:
            print("render-prompt.sh: malformed --values pair (no '='): " + repr(pair), file=sys.stderr)
            sys.exit(1)
        k, v = pair[:eq], pair[eq+1:]
        overrides[k] = v

mapping = {**defaults, **overrides}

with open(template_path, "r", encoding="utf-8") as f:
    body = f.read()

if check_mode:
    all_tokens = re.findall(r'{{(.*?)}}', body, re.DOTALL)
    bad_shape = [t for t in all_tokens if not re.match(r'^[A-Z_]+$', t)]
    if bad_shape:
        for t in bad_shape:
            print("error: malformed token {{" + t + "}} in " + template_path + " (must be {{[A-Z_]+}}-shaped)", file=sys.stderr)
        sys.exit(1)
    orphans = sorted(set(t for t in all_tokens if t not in allowlist))
    if orphans:
        for t in orphans:
            print("orphan token {{" + t + "}} in " + template_path + ": not in allowlist", file=sys.stderr)
        sys.exit(1)
    print("OK: " + phase + " template clean")
else:
    for k, v in mapping.items():
        body = body.replace("{{" + k + "}}", v)
    sys.stdout.write(body)
PY
