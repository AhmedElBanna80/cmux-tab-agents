# Contributing

This page documents the local-development workflow for cmux-tab-agents.

## TL;DR

```sh
git clone https://github.com/AhmedElBanna80/cmux-tab-agents.git
cd cmux-tab-agents
./scripts/dev-link.sh             # symlink the repo into ~/.claude
# … edit code …
# In Claude Code: /reload-plugins
# Test the change in a real cmux session.
./scripts/dev-unlink.sh           # when done; reverses the symlinks
```

## Why symlinks?

The plugin marketplace install copies a snapshot of the plugin into `~/.claude/plugins/cache/...`. Edits in your repo do **not** show up until you `/plugin update` (or reinstall). For development you want the opposite: *every* edit visible to Claude Code immediately, no reinstall.

`scripts/dev-link.sh` solves that by placing two symlinks in your user-scope `~/.claude/`:

| User-scope path                          | Target                              |
|------------------------------------------|-------------------------------------|
| `~/.claude/skills/cmux-tab-agents`       | `<repo>/skills/cmux-tab-agents`     |
| `~/.claude/commands/cmux-tab-agents`     | `<repo>/commands`                   |

User-scope skills and commands take precedence over plugin-installed ones, so `/cmux-tab-agents:setup` and the `cmux-tab-agents` skill resolve to your live worktree.

## Daily loop

1. Edit code in your worktree.
2. In any Claude Code session: `/reload-plugins`. Skills and slash commands re-scan immediately.
3. Trigger the skill (e.g. "execute this plan with cmux tab agents") or run the slash command (`/cmux-tab-agents:setup`) and watch the new behavior.
4. Iterate.

When you're done, run `./scripts/dev-unlink.sh`. It removes the two symlinks **only if they point into a cmux-tab-agents repo** — real directories and unrelated symlinks are left alone.

### Sandbox testing without symlinking

If you want to test a checkout *without* touching `~/.claude`, you can launch Claude Code with `--plugin-dir` pointed at this repo:

```sh
claude --plugin-dir .
```

The session loads only the plugins under `--plugin-dir`. Useful for one-off verification (PR review, regression test) without disturbing your normal install.

## Tests

Phase scripts live under `scripts/tests/` (top-level dev workflow tests) and `skills/cmux-tab-agents/scripts/tests/` (dispatch-helper tests).

```sh
# Top-level dev workflow
bash scripts/tests/test-dev-link.sh
bash scripts/tests/test-version-bump.sh

# Dispatch helpers
bash skills/cmux-tab-agents/scripts/tests/run-all.sh
```

All tests are pure bash + python3, no external deps.

## Release flow

1. Make sure `main` (or whichever branch you're cutting from) is clean and tests pass.
2. Bump the version in lockstep across both manifests:

   ```sh
   ./scripts/version-bump.sh patch    # 0.2.1 → 0.2.2
   ./scripts/version-bump.sh minor    # 0.2.1 → 0.3.0
   ./scripts/version-bump.sh major    # 0.2.1 → 1.0.0
   ```

   The script:
   - reads `version` from `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (refuses to proceed if they disagree);
   - rewrites both files in lockstep;
   - creates a `chore: bump to vX.Y.Z` commit;
   - tags `vX.Y.Z`.

   It refuses if the working tree is dirty, the bump kind is invalid, or the tag already exists. python3 only — no `jq` dependency.

3. Push the commit and the tag:

   ```sh
   git push origin <branch> --follow-tags
   ```

4. (Optional) Cut a GitHub release pointing at the tag.

## Hard rules for contributions

The discipline that the spawned tab-agents enforce applies to humans too:

- **No production code without a failing test first.** Add a test in `scripts/tests/` or `skills/cmux-tab-agents/scripts/tests/`, watch it fail, then implement.
- **No completion claims without fresh verification.** Run the test you just added; read the output; only then say "done."
- **No `git commit --no-verify`** (or any equivalent hook bypass — `--no-gpg-sign`, `HUSKY=0`, hook-config overrides, etc.). If a hook fails, fix the underlying code or escalate. Hooks exist because past commits broke things; bypassing them re-creates that breakage.
- **Stay inside this repo.** Don't reach into `~/.claude/` from inside automated tests or scripts that aren't `dev-link.sh` / `dev-unlink.sh` themselves. The two symlink scripts are the only ones authorized to touch user-scope state, and they're invoked manually.

## Layout

```
.
├── .claude-plugin/
│   ├── plugin.json            ← top-level version, name, etc.
│   └── marketplace.json       ← marketplace-side version (kept in lockstep)
├── commands/
│   └── setup.md               ← /cmux-tab-agents:setup slash command
├── skills/
│   └── cmux-tab-agents/
│       ├── SKILL.md
│       ├── scripts/           ← dispatch helpers
│       │   └── tests/         ← unit + integration tests for dispatch
│       ├── prompts/           ← seed prompts for spawned tab-agents
│       └── references/        ← config, contracts, divergences-from-upstream
├── scripts/
│   ├── dev-link.sh            ← symlink repo into ~/.claude
│   ├── dev-unlink.sh          ← reverse of dev-link
│   ├── version-bump.sh        ← bump + commit + tag in lockstep
│   └── tests/                 ← tests for the above
└── CONTRIBUTING.md            ← this file
```
