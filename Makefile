.PHONY: help link unlink status

help:
	@printf '%s\n' \
	  'cmux-tab-agents — local dev targets' \
	  '' \
	  '  make help     show this help (default)' \
	  '  make link     symlink this checkout into ~/.claude/plugins/cache/...' \
	  '  make unlink   remove the symlink (does not auto-restore backups)' \
	  '  make status   show whether the plugin is linked to this checkout'

link:
	@bash scripts/dev/link.sh

unlink:
	@bash scripts/dev/unlink.sh

status:
	@bash scripts/dev/status.sh
