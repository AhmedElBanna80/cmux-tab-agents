# Beta Release Channel

`cmux-tab-agents` ships two plugin entries from a single repository:

| Channel | Plugin name | Branch | Versions |
|---------|-------------|--------|----------|
| Stable  | `cmux-tab-agents` | `main` | `0.9.x`, `1.0.0`, … |
| Beta    | `cmux-tab-agents-beta` | `beta` | `0.10.0-beta.1`, … |

## Installing

```bash
# stable (default)
/plugin install cmux-tab-agents

# beta (opt-in)
/plugin install cmux-tab-agents-beta
```

You can have both installed simultaneously — they resolve to separate cache directories.

## Contributing an experiment

1. Branch off `beta` (not `main`):
   ```bash
   git checkout beta
   git pull
   git checkout -b feat/my-experiment
   ```
2. Open a PR targeting `beta`.
3. After merge, release-please opens a beta release PR (`0.10.0-beta.N`). Merge it to publish.
4. Beta users get it on `/plugin update`.

## Graduating to stable

Once an experiment has been validated on the beta channel:

1. Open a second PR targeting `main` (cherry-pick or re-PR the same change).
2. After merge, release-please opens a stable release PR. Merge it.
3. Stable users get it on `/plugin update`.

## Keeping beta in sync with main

`beta` should periodically be rebased onto or merged from `main` so it always equals `main` + unmerged experiments:

```bash
git checkout beta
git merge main
```

## Release infrastructure

| File | Purpose |
|------|---------|
| `release-please-config.json` | Release-please config for the `main` branch (stable) |
| `release-please-config-beta.json` | Release-please config for the `beta` branch (pre-release) |
| `.github/workflows/release-please.yml` | Runs on pushes to `main` |
| `.github/workflows/release-please-beta.yml` | Runs on pushes to `beta` |
| `.claude-plugin/marketplace.json` `plugins[0]` | Stable plugin entry |
| `.claude-plugin/marketplace.json` `plugins[1]` | Beta plugin entry (version updated by beta release-please) |

## Pre-implementation verification findings

Documented as required by ISSUE-95:

1. **Semver pre-release isolation**: Claude Code's plugin loader respects semver pre-release tags per spec (`1.0.0 > 1.0.0-beta.1`). Stable users running `/plugin update` will NOT be upgraded to beta versions — the "two-name" approach (`cmux-tab-agents` vs `cmux-tab-agents-beta`) provides an additional guarantee by keeping the plugin names distinct. Users must explicitly `/plugin install cmux-tab-agents-beta` to opt in.

2. **Marketplace two-entry support**: The `marketplace.json` `plugins` array is a list; Claude Code's `/plugin install <name>` discriminates by `plugins[i].name`. Two entries with distinct names in the same file are structurally valid. Both entries share `"source": "./"` but the beta branch's checkout provides the beta-versioned code.

3. **Cache directory layout**: Plugin cache paths include the plugin name segment (`~/.claude/plugins/cache/<author>/<plugin-name>/<version>/`). `cmux-tab-agents-beta` resolves to a distinct sub-directory from `cmux-tab-agents`, so both can coexist without collision.
