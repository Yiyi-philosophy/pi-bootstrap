#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
export TMUX_CONFIG_FILE="$test_dir/tmux.conf"
PI_BOOTSTRAP_TEST_ONLY=1 source "$repo_dir/install.sh"
TMUX=""

tmux() {
	if [[ "$1" == "-V" ]]; then
		printf 'tmux %s\n' "$test_version"
	else
		return 1
	fi
}

assert_count() {
	local expected="$1" pattern="$2" count
	count="$(grep -Fxc "$pattern" "$TMUX_CONFIG" || true)"
	[[ "$count" == "$expected" ]] || {
		echo "Expected $expected copies of '$pattern'; found $count" >&2
		exit 1
	}
}

for test_version in 3.1 3.2 3.4 3.5 3.5a 3.6; do
	# v1 added the exact standalone line; preserve unrelated user settings.
	printf 'set -g mouse on\nset -g extended-keys on\nset -g status off\n' > "$TMUX_CONFIG"
	configure_tmux > "$test_dir/output" 2>&1
	grep -Fqx 'set -g mouse on' "$TMUX_CONFIG"
	grep -Fqx 'set -g status off' "$TMUX_CONFIG"

	case "$test_version" in
		3.1)
			assert_count 0 'set -g extended-keys on'
			assert_count 0 '# >>> pi-bootstrap >>>'
			grep -Fq 'requires tmux >= 3.2' "$test_dir/output"
			;;
		3.2|3.4)
			assert_count 1 'set -g extended-keys on'
			assert_count 0 'set -g extended-keys-format csi-u'
			assert_count 1 '# >>> pi-bootstrap >>>'
			;;
		*)
			assert_count 1 'set -g extended-keys on'
			assert_count 1 'set -g extended-keys-format csi-u'
			assert_count 1 '# >>> pi-bootstrap >>>'
			;;
	esac
	assert_count 1 'set -g status off'
	cp "$TMUX_CONFIG" "$test_dir/first.conf"
	configure_tmux > "$test_dir/output" 2>&1
	cmp "$test_dir/first.conf" "$TMUX_CONFIG"
done

echo 'tmux migration, version branches, and repeat-run idempotence passed'
