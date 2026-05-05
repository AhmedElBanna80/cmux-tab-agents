# Changelog

All notable changes to cmux-tab-agents will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0](https://github.com/AhmedElBanna80/cmux-tab-agents/compare/cmux-tab-agents-v0.4.0...cmux-tab-agents-v0.5.0) (2026-05-05)


### Features

* **ISSUE-26:** implementer as task lead — agent-to-agent review loop without planner ([#50](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/50)) ([d8e7a2d](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/d8e7a2d29c4086853ed574d7d1f07f2c8789b004))

## [0.4.0](https://github.com/AhmedElBanna80/cmux-tab-agents/compare/cmux-tab-agents-v0.3.0...cmux-tab-agents-v0.4.0) (2026-05-05)


### Features

* **cmux-tab-agents:** trim SKILL.md by moving upstream-quote blocks to references ([7410d79](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/7410d7962c437049890af02def70651397277a3a))
* **DEMO-1:** add todo item — scaffold React app with TodoForm and TodoApp ([47f1370](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/47f1370fe604ab63320483a891cdfb48320c62ae))
* **dev:** add link/unlink scripts and base Makefile ([5dd0f1e](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/5dd0f1e98d5aef7cb7194671eff5a4896fbd92eb))
* **dev:** add lint.sh and render-prompt.sh with Makefile lint/preview targets ([3a216c6](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/3a216c6e74d2cbffffc95cfab6c4e0319b192a3d))
* **dev:** link/unlink also handle legacy ~/.claude/skills/ path ([8d7ee45](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/8d7ee4596d9a9c66199338e21cedf6bc3e50f36b))
* **ISSUE-16:** extract stable discipline to references, shrink seed prompts ([cdf8c2a](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/cdf8c2a3690f0dc3d75e20927bac9307fbf3812f))
* **ISSUE-17:** restructure seed prompts for cache-friendly rendering ([62b0487](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/62b04876843fd183e55791480fc40da76c0f4385))
* **ISSUE-18:** add per-phase model defaults in configuration ([c7efd55](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/c7efd55326c9b60da3878a0996a11c5a05d454b8))
* **ISSUE-19:** enforce result file size caps in reporting contract and seed prompts ([3d7b8ac](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/3d7b8ac4d7dc98bea833023882525704294e6b27))
* **ISSUE-19:** trim Size limits sections to fit line budgets ([a670f35](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/a670f35ecf91574fa2b9180a97203da83274890b))
* **ISSUE-20:** add heuristic for skipping code-quality review on trivial diffs ([e916fa4](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/e916fa4ad07a803e53036f82edace684a8818e50))
* **ISSUE-21:** add --fix-only re-dispatch mode for lightweight implementer fixes ([fdf5ae6](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/fdf5ae6d1951ee0ee4e68ad618180b49f8682f79))
* **ISSUE-23:** add verification artifact for implementer result ([b7b2c14](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/b7b2c14cdedea999065507bca69e0ad613a2ee15))
* **ISSUE-27:** add --finish-mode flag to automate post-review task completion ([#45](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/45)) ([700fd5a](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/700fd5a25131661ff8bd4d230830f74fb021799b))
* **ISSUE-37:** add copy-pastable focus shortcuts for surface refs ([2256d88](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/2256d88dc2c29c15c679df1d9b6385a4815dc917))
* **ISSUE-37:** add copy-pastable focus shortcuts for surface refs with cache-friendly architecture ([72d2d81](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/72d2d81a8cdb0e9b50029d2b33d4136854929795))
* **ISSUE-38:** add release-please-action for auto version bumping ([#42](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/42)) ([5485a0c](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/5485a0c47af5001a19bea5a10e43255221afd9d3))
* **ISSUE-39:** add make test target and wire all tests into CI ([#41](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/41)) ([c65e375](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/c65e3754d8de2267ff17b930b0caaa6ef7a927da))
* **issue-8:** v0.3.0 configurable model/effort defaults and setup command ([9cff6f5](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/9cff6f554f05446f3864d41338655526d4d36464)), closes [#8](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/8)
* **poll-result.sh:** add --full and --frontmatter-only flags for compact output ([12fbdf4](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/12fbdf439d9c6026cd8bd4889ad3260d6c8d8859))
* scaffold Vite+React+TS app with TodoForm and TodoApp ([40d3e4a](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/40d3e4aa3e961f337fd0a5052659bb28695fa7b5))
* **skill:** --fix-only re-dispatch mode ([#21](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/21)) ([d720336](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/d7203368f03b8e0fd7e8725b376c42f694b29e89))
* **skill:** cache-friendly seed prompt rendering ([#17](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/17)) ([9b0fb93](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/9b0fb93054bbfdb66bcabf8089ea3a6d72431411))
* **skill:** poll-result.sh --summary-only default ([#22](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/22)) ([5baed9a](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/5baed9aa694b36cce7ec529de6c7d326187bd959))
* **skill:** shrink seed prompts; move discipline to references ([#16](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/16)) ([7f6855c](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/7f6855cb05760f6e04c907dabc1fbaa90d76d227))
* **skill:** skip code-quality review on trivial diffs ([#20](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/20)) ([efe5bd4](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/efe5bd46d3822b202f9f1f6d197a30f9e36b2c9b))
* **skill:** verification artifact in implementer result ([#23](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/23)) ([0907dfa](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/0907dfa9358a173ca00851414820cb6779d9194b))
* v0.2.0 — active tab→planner push channel + --model flag ([1221c86](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/1221c86ebcafd701a9183597fefb2f54796a4ef4))


### Bug Fixes

* **ci:** silence SC2155 (split local+assign) and SC2064 (single-quote trap) ([5bdaee2](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/5bdaee2c0106df58a054d693460a9824058ae3b6))
* **ISSUE-20:** resolve SC2155 lint in test-should-skip-code-review.sh ([40f9750](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/40f97502fbec308e06659a41c613f741aca94bb7))
* **ISSUE-21:** reference discipline.md properly in fix-only prompt ([4ddaf91](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/4ddaf911bc1d0a34dbfcff6485873890142ed98c))
* **ISSUE-21:** SC2064 trap quoting in test files ([492915a](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/492915a8202cf194a2b6d3efeff42486282edde6))
* **ISSUE-22:** trap quoting (SC2064) ([8e8608f](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/8e8608fe067472170476e0068c3b5f658fece107))
* **ISSUE-25:** resolve discipline.md path for use outside cmux-tab-agents repo ([#43](https://github.com/AhmedElBanna80/cmux-tab-agents/issues/43)) ([8acdceb](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/8acdcebf71d5e6a4d7ef0a9792d49487560c758c))
* **ISSUE-37:** correct jq path for OWN_SURFACE extraction to use .focused.surface_ref ([405cdf1](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/405cdf1826581c5373fbebb28813affbc2fba266))
* **ISSUE-37:** restore Surface refs in reports convention to SKILL.md ([f1c0cca](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/f1c0cca95f76f1915bb6ee907263ad5e4bf7461a))
* **ISSUE-37:** trim SKILL.md and code-reviewer-tab-prompt.md to meet line targets ([25415f7](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/25415f799147b7f341250b475569ea79762ed410))
* **release-please:** remove invalid command input, fix extra-files path key ([b34f53e](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/b34f53ecdf9c7bcd814b58bb7b6426cc34d6cbee))
* remove unused token from code-reviewer prompt ([626d329](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/626d32936413cb6780f4493cb7cb72a93a152ae9))
* **skill:** auto-start tab-agents via initial user message ([0b4d17d](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/0b4d17d8a37a808515124c29ac97852295c1b7d4))
* **skill:** harden seed prompts against missing cmux subcommands ([178b827](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/178b827681015262b0a9a0b2c5dc43ac734f76e5))
* trim SKILL.md to exactly 250 lines after rebase merge ([22ca8d9](https://github.com/AhmedElBanna80/cmux-tab-agents/commit/22ca8d930d4f317aeb811039ac7d83e339835fcc))

## [Unreleased]

### Added

- **ISSUE-17: Cache-friendly seed prompt rendering** — Restructured all tab-agent seed prompts (implementer, spec-reviewer, code-reviewer) to separate static prefix from dynamic task context tail. The static prefix (containing ~95% of the prompt text) is now byte-identical across dispatches, enabling Anthropic's 5-minute auto-cache to reuse it across multiple tab-agent spawns. This reduces token costs by caching the stable prefix once and only paying for the small task-specific tail per dispatch.
  - `references/prompt-rendering.md` — Documents the prompt caching contract, explaining the prefix/tail structure and rules for maintaining cacheability when editing prompts.
  - `tests/test-prompt-prefix-caching.sh` — Automated test suite verifying that:
    - Prompt prefixes are byte-identical across dispatches with different task text
    - No placeholders appear in the cacheable prefix region
    - All placeholders are confined to the tail section
- **ISSUE-21: `--fix-only` re-dispatch mode** for `dispatch-implementer.sh`: Boot implementer with stripped seed (identity + worktree + result-file contract + reviewer feedback only, ~47 lines vs 502) for small, localized reviewer-driven fixes. Saves tokens and wall-time while preserving implementer's mental model. Requires `--feedback-from-previous-review`; task text becomes optional. See `references/dispatch-reference.md` for usage and decision tree.
- **ISSUE-22: poll-result.sh output modes** — Added output mode flags to reduce token cost during polling:
  - `--full` flag: Restore original behavior (emit entire result file)
  - `--frontmatter-only` flag: Emit only YAML frontmatter (cheapest read)
  - Default mode (no flags): Emit YAML frontmatter + first 30 lines of markdown body + truncation marker if longer
  - Updated SKILL.md with recommendations on when to use each mode
  - Added comprehensive test suite (poll-result.test.sh) covering all three modes
- **ISSUE-20:** Add heuristic for skipping code-quality review on trivial diffs
  - New helper script `scripts/should-skip-code-review.sh` automates the decision
  - New reference doc `references/skip-heuristics.md` describes the heuristic
  - Planner can now safely skip code-reviewer phase for test-only, doc-only, and changelog-only changes ≤30 lines
  - All changes require spec-reviewer approval with no concerns flagged
  - Skipping is optional; planner remains in control
- **Result file size caps (ISSUE-19)**: Enforced size limits in `references/reporting-contract.md` to prevent context bloat:
  - `summary` field: ≤ 200 words
  - `concerns` / issue sections: ≤ 10 bullets, each ≤ 25 words
  - Total result file: ≤ 200 lines (excluding YAML frontmatter)
  - Agents must write verbose detail (test output, traces, diffs) to sibling files (e.g., `.cmux-implementer-verification.txt`) and reference them from the result.
- Updated seed prompts (`implementer-tab-prompt.md`, `spec-reviewer-tab-prompt.md`, `code-reviewer-tab-prompt.md`) to enforce size limits and include self-check step before declaring completion.

### Changed

- **ISSUE-17: Prompt rendering** — Restructured seed prompts for cacheability across multiple tab-agent spawns
- **ISSUE-22: poll-result.sh** — Default output is now summary-only (frontmatter + 30 body lines), reducing planner token cost during routine polling
  - **SKILL.md**: Updated "Polling for results" section with documentation of new output modes
  - **references/reporting-contract.md**: Added examples and recommendations for selective polling modes

### Fixed

- **ISSUE-25: Discipline path resolution outside cmux-tab-agents repo** — Added `{{SKILL_BASE}}` placeholder that resolves to the installed skill directory. All seed prompts now read discipline.md from `{{SKILL_BASE}}/references/discipline.md` instead of `{{WORKTREE}}/skills/cmux-tab-agents/references/discipline.md`, so the path works when the skill is used from consumer repos where `skills/cmux-tab-agents/` doesn't exist.
  - `scripts/_dispatch_common.sh`: Computes `SKILL_BASE` from `SKILL_ROOT` and exports it to template substitution
  - `scripts/dev/render-prompt.sh`: Added `SKILL_BASE` to allowlist and computed default value
  - All four seed prompts updated to use `{{SKILL_BASE}}/references/discipline.md`
  - `references/prompt-rendering.md`: Documented `{{SKILL_BASE}}` and the distinction from `{{WORKTREE}}`
  - New test suite `scripts/dev/tests/test_skill_base_discipline_path.sh` validates discipline path resolution

### Compliance

All acceptance criteria from ISSUE-17 are met:
- ✅ No `{{...}}` placeholders appear outside the `## Task context` section
- ✅ Rendering two dispatches with different tickets produces byte-identical prefix output
- ✅ All placeholder substitutions happen in the clearly marked tail section
- ✅ Documentation defines the caching contract and editing rules
- ✅ Test suite validates prefix consistency automatically
