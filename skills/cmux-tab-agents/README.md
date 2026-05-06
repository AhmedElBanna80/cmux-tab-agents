
## Session Persistence with crex

cmux-tab-agents integrates [crex (cmux-resurrect)](https://github.com/neurosnap/cmux-resurrect) for session persistence. When an implementer completes work, their cmux tab state is saved, enabling reviewers to resurrect dead tabs if they need to send feedback.

### Installation

**macOS:**
```bash
brew install crex
```

**Linux:**
```bash
# via cargo
cargo install cmux-resurrect
# or check https://github.com/neurosnap/cmux-resurrect for releases
```

**Verify installation:**
```bash
crex --version
```

### How It Works

1. **Implementer saves workspace** — After writing result file and before exit, implementer runs `crex save <SESSION_NAME>`
2. **Session stored** — Crex snapshot captured in `~/.cmux-resurrect/` 
3. **Reviewers resurrect** — If spec-reviewer or code-reviewer needs to send feedback, they run `crex restore <SESSION_NAME>` to bring back the implementer's tab
4. **Full cycle continues** — Feedback sent, implementer fixes, re-runs review cycle

### Setup (Optional: Auto-save on Session Exit)

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "stop": "crex save $(date +%Y%m%d-%H%M%S) 2>/dev/null || true"
  }
}
```

This auto-saves your entire cmux workspace when Claude exits, useful for interruption recovery.

### Troubleshooting

**"crex: command not found"**
- Crex is optional; the integration gracefully degrades without it
- Install if you want session persistence features

**"Cannot restore session"**
- Verify session exists: `crex list`
- Check session name in `.cmux-implementer-result.md` field `crex_session:`
- Manually explore: `ls ~/.cmux-resurrect/`

**More info:** See `references/session-persistence.md` for detailed workflow guide.
