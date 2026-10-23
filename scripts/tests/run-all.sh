#!/usr/bin/env bash
# Run the whole pi-bootstrap test suite.
#
# Every test gets its own scratch HOME and TMPDIR; nothing here reads the
# developer's ~/.pi, ~/.tmux.conf, or any credential. A test that cannot run
# reports SKIP (exit 77) instead of PASS, and a component that is not at the
# pinned version is a SKIP too, so "not exercised" is never confused with green.
#
# Usage:
#   scripts/tests/run-all.sh            # offline: no network, no registry
#   scripts/tests/run-all.sh --fetch    # allow downloading test fixtures
#
# The real upgrade/rollback acceptance test (H1) installs Pi 1.0.2 and 1.4.0
# from npm and the pinned commit from GitHub into a scratch prefix. It runs only
# when explicitly enabled:
#   PI_BOOTSTRAP_REAL_UPGRADE=1 PI_BOOTSTRAP_ALLOW_NETWORK=1 scripts/tests/run-all.sh
#   PI_BOOTSTRAP_PI_PACKAGE=<dir> \
#   PI_BOOTSTRAP_PM_280=<dir> \
#   PI_BOOTSTRAP_AGENT_DIR=<dir> \
#     scripts/tests/run-all.sh          # also run the real-runtime tests
#
# Real-runtime tests need the exact pinned matrix: Pi 1.4.0, permission-modes
# 2.8.0 at commit cf77816 (a git checkout), pi-btw 0.62.0, pi-advisor-flow
# 0.14.2. Anything else is reported as SKIP with the version that was found.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export PI_BOOTSTRAP_FETCH=0
[[ "${1:-}" == "--fetch" ]] && export PI_BOOTSTRAP_FETCH=1

pass_count=0
skip_count=0
fail_count=0
failed=()
skipped=()

run() {
	local name="$1"
	shift
	local isolation status=0
	isolation="$(mktemp -d "${TMPDIR:-/tmp}/pi-bootstrap-run.XXXXXX")"
	TMPDIR="$isolation" HOME="$isolation" "$@" || status=$?
	rm -rf "$isolation"
	case "$status" in
		0) pass_count=$((pass_count + 1)) ;;
		77)
			skip_count=$((skip_count + 1))
			skipped+=("$name")
			;;
		*)
			fail_count=$((fail_count + 1))
			failed+=("$name (exit $status)")
			;;
	esac
}

echo "== static checks"
run "bash -n install.sh" bash -n "$repo/install.sh"
for script in "$repo"/scripts/*.sh "$here"/*.sh; do
	run "bash -n scripts/$(basename "$script")" bash -n "$script"
done
run "embedded sources in sync" bash "$repo/scripts/check-embedded-extension.sh"
run "version matrix matches the tests" bash "$here/test-version-matrix.sh"
run "shellcheck" bash -c '
	if ! command -v shellcheck >/dev/null 2>&1; then
		echo "SKIP shellcheck: not installed"
		exit 77
	fi
	shellcheck --severity=warning "$@"' _ \
	"$repo/install.sh" "$repo/scripts"/*.sh "$here"/*.sh "$here"/fixtures/*.sh

echo "== installer behavior (isolated, stubbed, no network)"
run "settings migration (F1)" bash "$here/test-install-settings.sh"
run "installer run and rollback (F2/F3)" bash "$here/test-install-run.sh"
run "failure recovery, every failure shape (H1/H2/M4)" bash "$here/test-rollback.sh"
run "tmux branches (F5/M4)" bash "$repo/scripts/test-tmux.sh"
run "pin helper atomicity (F7/M5)" bash "$here/test-pin-helper.sh"
run "isolation and version guards (M2/M3)" node "$here/test-isolation-guards.mjs"

echo "== extension behavior"
run "classifier-model config battery" node "$here/test-classifier-config.mjs"
run "classifier config path (M1)" bash "$here/test-config-path.sh"

echo "== real runtime (needs the exact pinned matrix)"
run "git install lifecycle isolation (F2)" node "$here/test-install-lifecycle.mjs"
run "permission gate" node "$here/test-permission-gate.mjs"
run "classifier baseUrl regression" node "$here/test-classifier-baseurl.mjs"
run "RPC smoke" node "$here/test-rpc-smoke.mjs"
run "default stack load" node "$here/test-default-stack.mjs"
if [[ "${PI_BOOTSTRAP_REAL_UPGRADE:-0}" == 1 ]]; then
	run "upgrade and rollback on the real CLI (H1)" node "$here/test-real-upgrade.mjs"
else
	run "upgrade and rollback on the real CLI (H1)" bash -c 'echo "SKIP real upgrade: set PI_BOOTSTRAP_REAL_UPGRADE=1 (needs npm + GitHub)"; exit 77'
fi

echo
echo "summary: ${pass_count} passed, ${skip_count} skipped, ${fail_count} failed"
if ((${#skipped[@]})); then
	printf 'skipped: %s\n' "${skipped[@]}"
fi
if ((${#failed[@]})); then
	printf 'failed: %s\n' "${failed[@]}"
	exit 1
fi
