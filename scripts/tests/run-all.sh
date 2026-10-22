#!/usr/bin/env bash
# Run the whole pi-bootstrap test suite.
#
# Every test gets its own scratch HOME; nothing here reads the developer's
# ~/.pi, ~/.tmux.conf, or any credential. A test that cannot run reports SKIP
# (exit 77) instead of PASS, so "not exercised" is never confused with "green".
#
# Usage:
#   scripts/tests/run-all.sh              # offline
#   scripts/tests/run-all.sh --fetch      # allow downloading test fixtures
#
# Real-runtime tests need Pi 1.4.0 installed. Point PI_BOOTSTRAP_PI_PACKAGE at
# the package directory (or let it resolve from `npm root -g`), and
# PI_BOOTSTRAP_PM_280 at a permission-modes 2.8.0 checkout.
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
run "embedded extension in sync" bash "$repo/scripts/check-embedded-extension.sh"
run "shellcheck install.sh" bash -c '
	if ! command -v shellcheck >/dev/null 2>&1; then
		echo "SKIP shellcheck: not installed"
		exit 77
	fi
	shellcheck --severity=warning "$1"' _ "$repo/install.sh"

echo "== installer behavior (isolated, stubbed, no network)"
run "settings migration (F1)" bash "$here/test-install-settings.sh"
run "installer run and rollback (F2/F3)" bash "$here/test-install-run.sh"
run "tmux branches (F5)" bash "$repo/scripts/test-tmux.sh"
run "pin helper (F7)" bash "$here/test-pin-helper.sh"

echo "== extension behavior"
run "classifier-model config battery" node "$here/test-classifier-config.mjs"

echo "== real runtime (needs Pi 1.4.0)"
run "git install lifecycle isolation (F2)" node "$here/test-install-lifecycle.mjs"
run "permission gate" node "$here/test-permission-gate.mjs"
run "classifier baseUrl regression" node "$here/test-classifier-baseurl.mjs"
run "RPC smoke" node "$here/test-rpc-smoke.mjs"
run "default stack load" node "$here/test-default-stack.mjs"

echo
echo "summary: ${pass_count} passed, ${skip_count} skipped, ${fail_count} failed"
if ((${#skipped[@]})); then
	printf 'skipped: %s\n' "${skipped[@]}"
fi
if ((${#failed[@]})); then
	printf 'failed: %s\n' "${failed[@]}"
	exit 1
fi
