# cmux-tab-agents skill structure

## File layout

```
~/.claude/skills/cmux-tab-agents/
├── SKILL.md                                # main skill documentation
├── scripts/
│   ├── ensure-worktree.sh                  # idempotent worktree provisioning
│   ├── dispatch-implementer.sh             # spawn implementer tab
│   ├── dispatch-spec-reviewer.sh           # spawn spec-reviewer tab
│   ├── dispatch-code-reviewer.sh           # spawn code-quality-reviewer tab
│   ├── poll-result.sh                      # planner helper: wait on result file
│   └── _dispatch_common.sh                 # shared dispatch logic (sourced)
├── prompts/
│   ├── implementer-tab-prompt.md           # forked + TDD + verification + hook-bypass
│   ├── spec-reviewer-tab-prompt.md         # forked + verification + hook-bypass
│   └── code-reviewer-tab-prompt.md         # forked + verification + hook-bypass
└── references/
    ├── upstream-quotes.md                  # verbatim text from upstream
    ├── skill-structure.md                  # this file
    ├── status-conventions.md               # icons, colors, status keys
    ├── reporting-contract.md               # result file schemas, polling pattern
    ├── divergences-from-upstream.md        # why and where this fork differs
    └── configuration.md                    # env var + per-repo .toml config
```
