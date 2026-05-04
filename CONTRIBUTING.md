# Contributing

Contributions are welcome. This document covers how to propose changes, the commit style, and the hard rules every contributor must follow.

## Quick start for contributors

- Clone the repo and run `make link` to symlink your checkout into the plugin cache.
- Edit files under `skills/cmux-tab-agents/`.
- Run `make lint` before committing.
- Run `make preview` to render the implementer prompt with sample values.

Full setup and iteration loop: [README — Local development](./README.md#local-development).

## Proposing changes

`main` is branch-protected. Direct pushes are blocked. All changes go via PR.

1. Branch from `main`. Conventional name: `<type>/<ticket-or-slug>` — e.g. `feat/CTADEV-42/add-x`, `fix/issue-7/parse-bug`, `docs/CTADEV-11/add-contributing`.
2. Push and open a PR: `gh pr create`.
3. PRs merge with 0 required approving reviews (solo-friendly), but the protection rule means you cannot bypass via direct push. Force-push and branch delete on `main` are also blocked.

## Commit style

Conventional commits. Subject under 72 characters. Body explains WHY, not WHAT.

Allowed types: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.

Scope is optional but preferred: `feat(skill): ...`, `fix(dev): ...`, `docs(readme): ...`.

Recent examples from the log:

```
fix(skill): auto-start tab-agents via initial user message
refactor(dev): link/unlink also handle legacy ~/.claude/skills/ path
docs(readme): add local development prerequisites
```

## TDD discipline

Write the failing test first. Watch it fail. Write minimal code to pass. No production code without a failing test.

Full rationale, the Iron Law, and Red-Green-Refactor detail: [`skills/cmux-tab-agents/prompts/implementer-tab-prompt.md`](./skills/cmux-tab-agents/prompts/implementer-tab-prompt.md). That file is the source of truth for the project's TDD position — this document does not duplicate it.

## Hook bypass is forbidden

NEVER use `git commit --no-verify`, `HUSKY=0`, `--no-gpg-sign`, `-c core.hooksPath=/dev/null`, or any equivalent. If a hook fails, read the failure and fix the underlying issue. Reviewers scan commits for evidence of bypass.

## Optional: dogfood the skill

For non-trivial changes, the maintainer runs the change through the plugin's own pipeline — implementer tab-agent, then spec-reviewer, then code-quality-reviewer. You don't need to do this yourself; a clean PR with a focused diff and tests is enough. If you developed your fix via the pipeline and want to mention that in the PR description, go for it.

## Filing issues

Open an issue on [GitHub Issues](https://github.com/AhmedElBanna80/cmux-tab-agents/issues). Include:

- Reproduction steps
- Expected vs. actual behavior
- `cmux --version` output (if available)
- Claude Code version
