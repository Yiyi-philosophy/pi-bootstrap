#!/usr/bin/env bash
# Fake `tmux` for the pi-bootstrap tests. Reports FAKE_TMUX_VERSION and never
# touches a real tmux server.
set -euo pipefail

if [[ "${1:-}" == "-V" ]]; then
	printf 'tmux %s\n' "${FAKE_TMUX_VERSION:-3.4}"
	exit 0
fi

if [[ "${1:-}" == "source-file" ]]; then
	if [[ -n "${FAKE_TMUX_LOG:-}" ]]; then
		printf 'source-file %s\n' "${2:-}" >>"$FAKE_TMUX_LOG"
	fi
	exit "${FAKE_TMUX_SOURCE_STATUS:-0}"
fi

if [[ "${1:-}" == "kill-server" ]]; then
	echo "fake-tmux: refusing kill-server" >&2
	exit 1
fi

exit 0
