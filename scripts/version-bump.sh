#!/usr/bin/env bash
# version-bump.sh — bump the plugin version in lockstep across both manifests,
# commit, and tag.
#
# Usage:
#   ./scripts/version-bump.sh <major|minor|patch> [--repo PATH]
#
# Touches:
#   .claude-plugin/plugin.json     (top-level "version")
#   .claude-plugin/marketplace.json ("plugins"[0]["version"])
#
# Then: `git add` both, `git commit -m "chore: bump to vX.Y.Z"`, `git tag vX.Y.Z`.
#
# Refuses if:
#   - bump kind is not major|minor|patch
#   - working tree is dirty
#   - the two manifests don't already agree on the current version
#   - a tag named vX.Y.Z already exists
#
# python3 only (no jq) to match the rest of the repo's tooling.

set -euo pipefail

KIND=""
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    major|minor|patch) KIND="$1"; shift ;;
    --repo)            REPO="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "version-bump: unknown arg '$1'. Pass one of: major | minor | patch." >&2; exit 1 ;;
  esac
done

if [[ -z "$KIND" ]]; then
  echo "version-bump: missing bump kind. Pass one of: major | minor | patch." >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || {
    echo "version-bump: not inside a git repo. Pass --repo PATH explicitly." >&2
    exit 1
  }
fi
REPO=$(cd "$REPO" && pwd)

PLUGIN_JSON="$REPO/.claude-plugin/plugin.json"
MARKET_JSON="$REPO/.claude-plugin/marketplace.json"
[[ -f "$PLUGIN_JSON" ]] || { echo "version-bump: missing $PLUGIN_JSON" >&2; exit 1; }
[[ -f "$MARKET_JSON" ]] || { echo "version-bump: missing $MARKET_JSON" >&2; exit 1; }

# 1. Working tree must be clean.
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo "version-bump: working tree is dirty. Commit or stash first; refusing to bump on top of unsaved work." >&2
  exit 1
fi

# 2. Read current versions and confirm they match.
read -r CUR_PLUGIN CUR_MARKET NEW_VER <<EOF_PY
$(python3 - "$PLUGIN_JSON" "$MARKET_JSON" "$KIND" <<'PY'
import json, sys
plugin_path, market_path, kind = sys.argv[1], sys.argv[2], sys.argv[3]
with open(plugin_path) as f: plugin = json.load(f)
with open(market_path) as f: market = json.load(f)
cur_plugin = plugin.get("version", "")
cur_market = market.get("plugins", [{}])[0].get("version", "")
def bump(v, k):
    parts = v.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        sys.stderr.write(f"version-bump: cannot parse semver '{v}'\n")
        sys.exit(1)
    a, b, c = (int(p) for p in parts)
    if k == "major": a, b, c = a + 1, 0, 0
    elif k == "minor": b, c = b + 1, 0
    elif k == "patch": c = c + 1
    return f"{a}.{b}.{c}"
new = bump(cur_plugin, kind) if cur_plugin else ""
print(f"{cur_plugin} {cur_market} {new}")
PY
)
EOF_PY

if [[ "$CUR_PLUGIN" != "$CUR_MARKET" ]]; then
  echo "version-bump: manifest version mismatch. plugin.json='$CUR_PLUGIN' marketplace.json='$CUR_MARKET'. Reconcile first." >&2
  exit 1
fi

if [[ -z "$NEW_VER" ]]; then
  echo "version-bump: could not compute new version (current='$CUR_PLUGIN')." >&2
  exit 1
fi

TAG="v$NEW_VER"

# 3. Tag must not already exist.
if git -C "$REPO" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "version-bump: tag $TAG already exists in $REPO. Refusing to overwrite." >&2
  exit 1
fi

# 4. Apply the bump in both manifests via python3 (preserves formatting style:
# 2-space indent, no trailing newline difference vs the originals as much as
# possible).
python3 - "$PLUGIN_JSON" "$MARKET_JSON" "$NEW_VER" <<'PY'
import json, sys
plugin_path, market_path, new = sys.argv[1], sys.argv[2], sys.argv[3]
def rewrite(path, mutate):
    with open(path) as f:
        data = json.load(f)
    mutate(data)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
def set_plugin(d):  d["version"] = new
def set_market(d):  d["plugins"][0]["version"] = new
rewrite(plugin_path, set_plugin)
rewrite(market_path, set_market)
PY

# 5. Commit + tag.
git -C "$REPO" add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git -C "$REPO" commit -m "chore: bump to $TAG" >/dev/null
git -C "$REPO" tag "$TAG"

echo "Bumped $CUR_PLUGIN → $NEW_VER  (commit + tag $TAG created)."
