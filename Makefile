.PHONY: help link unlink status lint test preview

help:
	@printf '%s\n' \
	  'cmux-tab-agents — local dev targets' \
	  '' \
	  '  make help     show this help (default)' \
	  '  make link     symlink this checkout into ~/.claude/plugins/cache/...' \
	  '  make unlink   remove the symlink (does not auto-restore backups)' \
	  '  make status   show whether the plugin is linked to this checkout' \
	  '  make lint     run shellcheck + JSON + prompt-template lint' \
	  '  make test     run all tests' \
	  '  make preview  preview the implementer prompt with sample values'

link:
	@bash scripts/dev/link.sh

unlink:
	@bash scripts/dev/unlink.sh

status:
	@bash scripts/dev/status.sh

lint:
	@bash scripts/dev/lint.sh

test:
	@for f in \
		skills/cmux-tab-agents/tests/test-*.sh \
		skills/cmux-tab-agents/scripts/test-*.sh \
		skills/cmux-tab-agents/scripts/tests/test_*.sh \
		scripts/dev/tests/test_*.sh \
		scripts/dev/tests/test-*.sh; do \
		[ -f "$$f" ] || continue; \
		bash "$$f" || exit 1; \
	done

preview:
	@bash scripts/dev/render-prompt.sh implementer
