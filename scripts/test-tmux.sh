#!/usr/bin/env bash
# tmux version branches, config migration, and repeat-run idempotence.
#
# Runs in an isolated HOME with a stubbed `tmux`, so no real tmux server or
# user configuration is touched. Covers every version the docs claim:
# 3.1, 3.2, 3.3a, 3.4, 3.5, 3.5a, 3.6 (plus an unparseable version).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/lib.sh"

root="$(new_root)"
# install.sh installs its own EXIT trap; keep cleanup working after sourcing.
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"
put_stub "$root" fake-tmux tmux
export FAKE_TMUX_LOG="$root/tmux.log"

load_installer
TMUX_CONFIG="$root/home/.tmux.conf"

assert_count() {
	local expected="$1" pattern="$2" count
	count="$(grep -Fxc "$pattern" "$TMUX_CONFIG" || true)"
	assert_eq "$expected" "$count" "count of '$pattern'"
}

# v1 of this repository added the bare line; a v1 install also has user lines.
seed() {
	printf 'set -g mouse on\nset -g extended-keys on\nset -g status off\n' >"$TMUX_CONFIG"
}

for test_version in 3.1 3.2 3.3a 3.4 3.5 3.5a 3.6; do
	export FAKE_TMUX_VERSION="$test_version"
	seed
	configure_tmux >"$root/output" 2>&1 || fail_test "configure_tmux failed for ${test_version}"

	# User configuration survives every branch.
	grep -Fqx 'set -g mouse on' "$TMUX_CONFIG" || fail_test "${test_version}: user setting dropped"
	grep -Fqx 'set -g status off' "$TMUX_CONFIG" || fail_test "${test_version}: user setting dropped"

	case "$test_version" in
		3.1)
			assert_count 0 'set -g extended-keys on'
			assert_count 0 '# >>> pi-bootstrap >>>'
			assert_contains "$(cat "$root/output")" "requires tmux >= 3.2" "3.1 warning"
			;;
		3.2 | 3.3a | 3.4)
			assert_count 1 'set -g extended-keys on'
			assert_count 0 'set -g extended-keys-format csi-u'
			assert_count 1 '# >>> pi-bootstrap >>>'
			;;
		3.5 | 3.5a | 3.6)
			assert_count 1 'set -g extended-keys on'
			assert_count 1 'set -g extended-keys-format csi-u'
			assert_count 1 '# >>> pi-bootstrap >>>'
			;;
	esac
	assert_count 1 'set -g status off'

	# Repeat run must be byte-identical (idempotence, not just idempotent counts).
	cp "$TMUX_CONFIG" "$root/first.conf"
	configure_tmux >"$root/output2" 2>&1 || fail_test "repeat configure_tmux failed for ${test_version}"
	cmp "$root/first.conf" "$TMUX_CONFIG" || fail_test "${test_version}: repeat run changed the file"
done
pass "tmux 3.1/3.2/3.3a/3.4/3.5/3.5a/3.6: correct branch, user settings kept, repeat run stable"

# Downgrade path: a 3.5 config must be cleaned up when tmux 3.1 is detected.
export FAKE_TMUX_VERSION=3.5
seed
configure_tmux >/dev/null 2>&1
export FAKE_TMUX_VERSION=3.1
configure_tmux >/dev/null 2>&1
assert_count 0 'set -g extended-keys on'
assert_count 0 '# >>> pi-bootstrap >>>'
grep -Fqx 'set -g mouse on' "$TMUX_CONFIG" || fail_test "downgrade dropped user settings"
pass "downgrade to 3.1 removes bootstrap settings and keeps user lines"

# Config with no trailing newline is still handled and stays readable.
export FAKE_TMUX_VERSION=3.4
printf 'set -g mouse on' >"$TMUX_CONFIG"
configure_tmux >/dev/null 2>&1
grep -Fqx 'set -g mouse on' "$TMUX_CONFIG" || fail_test "no-trailing-newline config corrupted"
assert_count 1 '# >>> pi-bootstrap >>>'
pass "config without a trailing newline handled"

# Unparseable version changes nothing.
printf 'set -g mouse on\n' >"$TMUX_CONFIG"
cp "$TMUX_CONFIG" "$root/before-unknown.conf"
export FAKE_TMUX_VERSION="garbage"
configure_tmux >"$root/unknown.log" 2>&1
cmp -s "$root/before-unknown.conf" "$TMUX_CONFIG" || fail_test "unknown version modified the config"
assert_contains "$(cat "$root/unknown.log")" "could not parse tmux version" "unknown version warned"
pass "unparseable tmux version: warned, config untouched"

# Inside tmux, a reload failure only warns.
export FAKE_TMUX_VERSION=3.5
TMUX="fake" FAKE_TMUX_SOURCE_STATUS=1 configure_tmux >"$root/source.log" 2>&1 ||
	fail_test "a tmux source-file failure must not abort the install"
assert_contains "$(cat "$root/source.log")" "could not reload tmux configuration" "reload failure warned"
TMUX="fake" configure_tmux >"$root/source-ok.log" 2>&1
grep -q '^source-file ' "$FAKE_TMUX_LOG" || fail_test "tmux source-file was not attempted"
pass "tmux reload: failure warns instead of aborting"

echo 'tmux migration, version branches, and repeat-run idempotence passed'
