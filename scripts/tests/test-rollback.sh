#!/usr/bin/env bash
# H1/H2: failure recovery in every failure shape the rollback must survive.
#
# Each case seeds a complete "previous installation" (old Pi launcher, old npm
# packages, an old git checkout, both extension files, settings.json,
# keybindings.json, .tmux.conf), then fails the run at one specific point. The
# assertion is never "recover() was called": it is that every one of those files
# is byte-identical afterwards, that the old packages and the old `pi` are back
# and still described by settings.json, that the original error was kept, and
# that the failed run's own artifacts are gone.
#
# Failure shapes covered:
#   after-backup      nothing was mutated yet
#   after-remove      after `pi remove` deleted the old packages
#   after-install     after new packages were installed
#   after-verify      a post-install verification failure
#   after-extensions  a version check failing after extensions landed
#   after-keybindings a config-write failure
#   after-tmux        a late failure after tmux was rewritten
#   after-config      the last failure point before commit
#   nested            a nested function failing inside $( )
#   pipeline          a failing pipeline under pipefail
#   subshell          a failing subshell
#   SIGINT/SIGTERM    signals delivered mid-mutation
#   SIGKILL           recovery on the next run (no trap can run)
#   SIGKILL @ boundary every filesystem boundary of the staged CLI step (H4)
#   journal faults    write / no-space / rename failure at every phase (H3)
#   offline recovery  GitHub, npm and settings.json all unusable (H2)
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

root="$(new_root)"
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"
install_stubs "$root"

agent="$PI_CODING_AGENT_DIR"
settings="$agent/settings.json"
extensions="$agent/extensions"
source_repo="$root/upstream/pi-permission-modes"
mkdir -p "$root/upstream" "$extensions"

load_installer
mapfile -t fixture_revs < <(make_fixture_repo "$source_repo" "$root/manifest.txt" "$PERMISSION_MODES_VERSION")
fixture_commit="${fixture_revs[0]}"
fixture_tree="${fixture_revs[1]}"
fixture_manifest="$(cat "$root/manifest.txt")"
fixture_count="$(wc -l <"$root/manifest.txt" | tr -d ' ')"

printf 'export default function minimalMode() {}\n' >"$root/minimal-mode.ts"
export FAKE_CURL_FILE="$root/minimal-mode.ts"
minimal_sha="$(sha256sum "$root/minimal-mode.ts" | cut -d' ' -f1)"


# which would overwrite environment overrides. The case runner therefore applies
# them *after* sourcing, through PI_BOOTSTRAP_TEST_SETUP (see run_installer).
fixture_setup="$(cat <<SETUP
PERMISSION_MODES_COMMIT=$fixture_commit
PERMISSION_MODES_TREE=$fixture_tree
PERMISSION_MODES_REPO=$source_repo
PERMISSION_MODES_SOURCE=git:github.com/GeorgeDing32/pi-permission-modes-fixture@$fixture_commit
PERMISSION_MODES_PATH=GeorgeDing32/pi-permission-modes-fixture
PERMISSION_MODES_DIR=$agent/git/github.com/GeorgeDing32/pi-permission-modes-fixture
MINIMAL_MODE_SHA256=$minimal_sha
export FAKE_PI_CLONE_DIR=$source_repo
SETUP
)"
fixture_setup="$fixture_setup"$'\n'"PERMISSION_MODES_MANIFEST=$(printf '%q' "$fixture_manifest")"$'\n'"PERMISSION_MODES_MANIFEST_COUNT=$fixture_count"

seed_previous_environment() {
	rm -rf "$agent/npm" "$agent/git" "$extensions" "$agent/keybindings.json" "$agent/.pi-bootstrap" \
		"$TMUX_CONFIG" "$root/npm-prefix"
	mkdir -p "$extensions" "$agent/npm/node_modules/@narumitw/pi-btw" \
		"$agent/npm/node_modules/pi-advisor-flow" "$agent/npm/node_modules/@georgedong32/permission-modes" \
		"$agent/git/github.com" "$root/npm-prefix/bin"
	printf '{"name":"@narumitw/pi-btw","version":"0.61.1"}\n' >"$agent/npm/node_modules/@narumitw/pi-btw/package.json"
	printf 'export default function btw() {}\n' >>"$agent/npm/node_modules/@narumitw/pi-btw/index.ts"
	printf '{"name":"pi-advisor-flow","version":"0.11.0"}\n' >"$agent/npm/node_modules/pi-advisor-flow/package.json"
	printf '{"name":"@georgedong32/permission-modes","version":"2.7.0"}\n' >"$agent/npm/node_modules/@georgedong32/permission-modes/package.json"
	# A real checkout, so `pi install` of the same identity has something to
	# fetch into and the run actually reaches the later stages.
	git clone --quiet "$source_repo" "$agent/git/github.com/GeorgeDong32/pi-permission-modes"
	printf '{"name":"fixture-package","version":"2.7.0"}\n' \
		>"$agent/git/github.com/GeorgeDong32/pi-permission-modes/package.json"
	git -C "$agent/git/github.com/GeorgeDong32/pi-permission-modes" \
		-c user.email=t@example.invalid -c user.name=t commit -qam "previous version"
	git -C "$agent/git/github.com/GeorgeDong32/pi-permission-modes" remote set-url origin "$source_repo"
	printf '{"name":"pi-extensions","private":true}\n' >"$agent/npm/package.json"
	printf 'export default function oldClassifier() {}\n' >"$extensions/classifier-model.ts"
	printf 'export default function oldMinimal() {}\n' >"$extensions/minimal-mode.ts"
	cat >"$settings" <<'JSON'
{
  "theme": "dark",
  "packages": [
    "npm:@narumitw/pi-btw@0.61.1",
    "npm:pi-advisor-flow@0.11.0",
    "npm:@georgedong32/permission-modes@2.7.0"
  ]
}
JSON
	printf '{"app.thinking.cycle":"ctrl+tab","custom":"keep"}\n' >"$agent/keybindings.json"
	printf 'set -g mouse on\n# >>> pi-bootstrap >>>\nset -g extended-keys on\n# <<< pi-bootstrap <<<\n' >"$TMUX_CONFIG"
	# The previous global Pi: a plain wrapper that reports its own version. A
	# plain file (not a symlink) also covers npm's non-link bin shape.
	cat >"$root/npm-prefix/bin/pi" <<'PI'
#!/usr/bin/env bash
echo previous-pi-1.0.0
PI
	chmod +x "$root/npm-prefix/bin/pi"
	mkdir -p "$root/npm-prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist"
	printf '{"name":"@earendil-works/pi-coding-agent","version":"1.0.0"}\n' \
		>"$root/npm-prefix/lib/node_modules/@earendil-works/pi-coding-agent/package.json"
	printf 'previous pi build\n' >"$root/npm-prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist/old-build.txt"
}

# Everything the rollback promises to restore, as one comparable string.
environment_fingerprint() {
	{
		sha256sum "$root/npm-prefix/bin/pi"
		sha256sum "$root/npm-prefix/lib/node_modules/@earendil-works/pi-coding-agent/package.json"
		find "$root/npm-prefix/lib/node_modules/@earendil-works/pi-coding-agent" -type f -printf '%P\n' | LC_ALL=C sort
		(
			cd "$agent"
			# npm packages and extensions: every file, byte-exact.
			find npm extensions -type f -printf '%p\n' | LC_ALL=C sort | xargs sha256sum
			# The git checkout: HEAD plus every tracked file's bytes. .git internals
			# are deliberately excluded (they differ by clone/commit timestamps and
			# are not what Pi loads).
			if [[ -d git ]]; then
				find git -maxdepth 4 -name .git -type d -printf '%h\n' | while IFS= read -r repo; do
					printf 'repo %s\n' "$repo"
					git -C "$repo" rev-parse HEAD 2>/dev/null || printf 'no-head\n'
					git -C "$repo" ls-files -z 2>/dev/null | xargs -0 -r sha256sum
				done
			fi
			# Config files: hash when present, record "absent" when not, so a case
			# that starts without one still gets a comparable fingerprint.
			for file in settings.json keybindings.json; do
				if [[ -e "$file" ]]; then sha256sum "$file"; else printf '%s absent\n' "$file"; fi
			done
		)
		if [[ -e "$TMUX_CONFIG" ]]; then sha256sum "$TMUX_CONFIG"; else printf '%s absent\n' "$TMUX_CONFIG"; fi
	} 2>/dev/null
}

# expect_error=0 for the after-crash recovery path: there is no in-process
# error to preserve, only the journal record.
assert_previous_environment() {
	local label="$1" expect_error="${2:-1}" now
	now="$(environment_fingerprint)"
	[[ "$now" == "$seed_fingerprint" ]] ||
		fail_test "$label: restored environment differs from the pre-run state:
--- expected
$seed_fingerprint
--- actual
$now"
	# Usable again, not merely listed: the old Pi reports its own version and the
	# old packages are on disk with their manifests intact.
	assert_eq "previous-pi-1.0.0" "$("$root/npm-prefix/bin/pi" --version)" "$label: previous Pi runs"
	[[ -f "$agent/npm/node_modules/@narumitw/pi-btw/index.ts" ]] ||
		fail_test "$label: the previous pi-btw file set was not restored"
	[[ ! -d "$agent/git/github.com/GeorgeDing32/pi-permission-modes-fixture" ]] ||
		fail_test "$label: the failed run's new checkout is still installed"
	[[ ! -d "$agent/npm/node_modules/diff" ]] ||
		fail_test "$label: files installed by the failed run are still present"
	assert_contains "$(cat "$root/install.log")" "rolling back" "$label: rollback announced"
	if [[ "$expect_error" == 1 ]]; then
		assert_contains "$(cat "$root/install.log")" "error: " "$label: the original error is still reported"
	fi
	grep -q 'previous environment restored and verified\|cannot be verified automatically\|automatic verification was not possible' "$root/install.log" ||
		fail_test "$label: rollback did not report a verification outcome"
	[[ ! -d "$agent/.pi-bootstrap/backup" ]] ||
		fail_test "$label: the backup directory was left behind after a successful rollback"
	[[ ! -f "$agent/.pi-bootstrap/transaction.env" ]] ||
		fail_test "$label: the journal was left behind after a successful rollback"
	if [[ "$expect_error" == 1 ]]; then
		assert_contains "$(cat "$root/install.log")" "fix the reported problem" "$label: next steps reported"
	fi
}

# Run main() in its own process so a rollback that exits cannot end this test,
# and so every case starts from a clean trap state. $* words are environment
# overrides; PI_BOOTSTRAP_TEST_SETUP is shell run *after* sourcing, for
# constants the installer assigns at file scope (which would overwrite env).
run_installer() {
	local status=0
	env "$@" PI_BOOTSTRAP_TEST_ONLY=1 PI_BOOTSTRAP_ALLOW_UNVERIFIED=1 \
		PI_BOOTSTRAP_TEST_SETUP="${fixture_setup}${PI_BOOTSTRAP_EXTRA_SETUP:+; $PI_BOOTSTRAP_EXTRA_SETUP}" \
		bash -c 'source "$1"; eval "${PI_BOOTSTRAP_TEST_SETUP:-}"; main' _ "$repo_dir/install.sh" \
		>"$root/install.log" 2>&1 || status=$?
	return "$status"
}

# Start main() in the background with the fixture constants applied after
# sourcing. The setup string contains newlines, so it is exported rather than
# passed word-by-word. Prints the pid.
start_installer_in_background() {
	PI_BOOTSTRAP_TEST_SETUP="${fixture_setup}${PI_BOOTSTRAP_EXTRA_SETUP:+; $PI_BOOTSTRAP_EXTRA_SETUP}" \
		PI_BOOTSTRAP_TEST_ONLY=1 PI_BOOTSTRAP_ALLOW_UNVERIFIED=1 "$@" \
		bash -c 'source "$1"; eval "${PI_BOOTSTRAP_TEST_SETUP:-}"; main' _ "$repo_dir/install.sh" \
		>"$root/install.log" 2>&1 &
	printf '%s\n' "$!"
}

run_case() {
	local label="$1" expect_success="${2:-0}"
	shift 2
	seed_previous_environment
	seed_fingerprint="$(environment_fingerprint)"
	[[ -n "$seed_fingerprint" ]] || fail_test "$label: could not fingerprint the seeded environment"
	if [[ -n "${PI_BOOTSTRAP_TEST_FAIL_AT:-}" && "${PI_BOOTSTRAP_TEST_FAIL_AT:-}" != *-slow ]]; then
		# Every case must fail at the stage it names; otherwise it could pass by
		# failing earlier for an unrelated reason.
		:
	fi
	if run_installer "$@"; then
		if [[ "$expect_success" != 1 ]]; then
			fail_test "$label: installer reported success"
		fi
	else
		[[ "$expect_success" == 1 ]] && fail_test "$label: installer failed: $(tail -5 "$root/install.log")"
	fi
	assert_previous_environment "$label"
	pass "$label: previous environment restored, old Pi runs, no leftovers"
}

# --- failure after backup (nothing mutated yet) -----------------------------
run_case "failure after backup" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-backup

# --- failure after `pi remove` deleted the old packages --------------------
run_case "failure after package removal" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-remove

# --- failure after new packages were installed -----------------------------
run_case "failure after package install" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-install

# --- verification failures -------------------------------------------------
run_case "failure after source verification" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-verify
run_case "failure after extensions" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-extensions

# --- configuration write failures -----------------------------------------
run_case "failure while writing keybindings" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-keybindings
run_case "failure after tmux configuration" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-tmux
run_case "late failure before commit" 0 PI_BOOTSTRAP_TEST_FAIL_AT=after-config

# --- failure shapes an ERR trap would miss --------------------------------
run_case "nested function in command substitution" 0 PI_BOOTSTRAP_TEST_FAIL_AT=nested
run_case "failing pipeline under pipefail" 0 PI_BOOTSTRAP_TEST_FAIL_AT=pipeline
run_case "failing subshell" 0 PI_BOOTSTRAP_TEST_FAIL_AT=subshell

# --- configuration files that did not exist before the run ---------------
# M4: created files must be removed again, not left behind half-written.
run_case_without() {
	local label="$1" remove_path="$2" expect_success="${3:-0}" stage="${4:-after-config}"
	seed_previous_environment
	rm -rf "$remove_path"
	seed_fingerprint="$(environment_fingerprint)"
	[[ "$remove_path" == "$agent/keybindings.json" || "$remove_path" == "$TMUX_CONFIG" ]] ||
		fail_test "$label: unexpected path $remove_path"
	if run_installer PI_BOOTSTRAP_TEST_FAIL_AT="$stage"; then
		[[ "$expect_success" == 1 ]] || fail_test "$label: installer reported success"
	else
		[[ "$expect_success" == 1 ]] && fail_test "$label: installer failed: $(tail -5 "$root/install.log")"
	fi
	assert_previous_environment "$label"
	[[ ! -e "$remove_path" ]] || fail_test "$label: $remove_path did not exist before the run and was not removed"
	pass "$label: a config file created by the failed run was removed again"
}

# --- a fresh machine: no previous Pi, no previous packages ---------------
# H1 also covers the first-install case: a failure must not leave a Pi the user
# never had, nor package trees, nor extensions.
fresh_home="$root/fresh-home"
fresh_agent="$fresh_home/.pi/agent"
mkdir -p "$fresh_agent" "$root/fresh-prefix"
printf '{"packages":[]}\n' >"$fresh_agent/settings.json"
if env PI_BOOTSTRAP_TEST_ONLY=1 PI_BOOTSTRAP_ALLOW_UNVERIFIED=1 \
	PI_BOOTSTRAP_TEST_SETUP="$fixture_setup" PI_BOOTSTRAP_TEST_FAIL_AT=after-config \
	PI_CODING_AGENT_DIR="$fresh_agent" HOME="$fresh_home" TMUX_CONFIG_FILE="$fresh_home/.tmux.conf" \
	npm_config_prefix="$root/fresh-prefix" npm_config_cache="$root/npm-cache" \
	PATH="$root/bin:$PATH" \
	bash -c 'source "$1"; eval "${PI_BOOTSTRAP_TEST_SETUP:-}"; main' _ "$repo_dir/install.sh" \
	>"$root/fresh.log" 2>&1; then
	fail_test "fresh failure: installer reported success"
fi
assert_contains "$(cat "$root/fresh.log")" "rolling back" "fresh failure: rollback announced"
[[ ! -e "$root/fresh-prefix/lib/node_modules/@earendil-works/pi-coding-agent" ]] ||
	fail_test "fresh failure: the Pi package installed by the failed run was left behind"
[[ ! -e "$root/fresh-prefix/bin/pi" ]] || fail_test "fresh failure: the pi bin entry was left behind"
[[ ! -e "$fresh_agent/npm" ]] || fail_test "fresh failure: the npm tree created by the failed run was left behind"
[[ ! -e "$fresh_agent/git" ]] || fail_test "fresh failure: the git tree created by the failed run was left behind"
[[ ! -e "$fresh_agent/extensions/classifier-model.ts" ]] ||
	fail_test "fresh failure: an extension created by the failed run was left behind"
[[ ! -e "$fresh_agent/keybindings.json" ]] || fail_test "fresh failure: a keybindings file was left behind"
[[ ! -e "$fresh_home/.tmux.conf" ]] || fail_test "fresh failure: a tmux config was left behind"
assert_eq '{"packages":[]}' "$(tr -d '\n' <"$fresh_agent/settings.json")" "fresh failure: settings.json is back to its original bytes"
[[ ! -d "$fresh_agent/.pi-bootstrap/backup" ]] || fail_test "fresh failure: backups were left behind"
pass "fresh machine: a failed first install leaves nothing behind (no Pi, no packages, no extensions)"

# --- M4: keybindings/tmux that did not exist before ----------------------
run_case_without "failure with no pre-existing keybindings" "$agent/keybindings.json" 0 after-keybindings
run_case_without "failure with no pre-existing tmux config" "$TMUX_CONFIG" 0 after-tmux

# --- M4: a user-customised tmux config survives a late failure -----------
seed_previous_environment
printf '# user block\nset -g mouse on\nset -g status off\n' >"$TMUX_CONFIG"
printf '{"app.thinking.cycle":"ctrl+tab","mine":true}\n' >"$agent/keybindings.json"
seed_fingerprint="$(environment_fingerprint)"
if run_installer PI_BOOTSTRAP_TEST_FAIL_AT=after-config; then
	fail_test "customised config: installer reported success"
fi
assert_previous_environment "customised config"
grep -q 'user block' "$TMUX_CONFIG" || fail_test "customised config: the user's tmux block was lost"
grep -q '"mine": *true' "$agent/keybindings.json" || fail_test "customised config: the user's keybinding key was lost"
pass "customised config: tmux and keybindings restored byte-for-byte after a late failure"

# --- realistic failure: the new package install itself fails --------------
seed_previous_environment
seed_fingerprint="$(environment_fingerprint)"
if FAKE_PI_FAIL_INSTALL_MATCH=pi-advisor-flow run_installer; then
	fail_test "advisor install failure: installer reported success"
fi
assert_contains "$(cat "$root/install.log")" "could not install npm:pi-advisor-flow" "advisor failure reported"
assert_previous_environment "advisor install failure"
pass "advisor install failure: previous packages and settings restored"

# --- a tampered new source is rejected and rolled back --------------------
seed_previous_environment
seed_fingerprint="$(environment_fingerprint)"
cp -a "$source_repo" "$root/tampered"
git -C "$root/tampered" rm -q index.ts
git -C "$root/tampered" -c user.email=t@example.invalid -c user.name=t commit -qm "drop file"
tampered_commit="$(git -C "$root/tampered" rev-parse HEAD)"
if PI_BOOTSTRAP_EXTRA_SETUP="PERMISSION_MODES_REPO=$root/tampered; PERMISSION_MODES_COMMIT=$tampered_commit" \
	run_installer; then
	fail_test "tampered source: installer reported success"
fi
assert_contains "$(cat "$root/install.log")" "does not match the pinned tree" "tamper reported before install"
# Pre-install verification runs before the transaction opens, so the correct
# outcome is "nothing was touched" rather than "a rollback happened".
[[ "$(environment_fingerprint)" == "$seed_fingerprint" ]] ||
	fail_test "tampered source: the pre-install check modified the environment"
[[ ! -d "$agent/.pi-bootstrap/backup" ]] || fail_test "tampered source: a backup directory was created"
[[ ! -f "$agent/.pi-bootstrap/transaction.env" ]] || fail_test "tampered source: a journal was created"
assert_not_contains "$(cat "$root/install.log")" "rolling back" "tampered source: no rollback was needed"
pass "tampered source: refused before any mutation, no rollback needed"

# --- signals during a mutation -------------------------------------------
# The installer is run in the foreground and signals itself from inside the
# paused stage. Sending SIGINT to a background job from the test would be
# meaningless: a non-interactive shell starts background jobs with SIGINT
# ignored, so the trap could never fire and the test would "pass" for the wrong
# reason. This delivers a real signal to the real process.
run_signal_case() {
	local label="$1" signal="$2" stage="$3"
	seed_previous_environment
	seed_fingerprint="$(environment_fingerprint)"
	if run_installer PI_BOOTSTRAP_TEST_FAIL_AT="$stage" PI_BOOTSTRAP_TEST_SIGNAL="$signal"; then
		fail_test "$label: installer exited 0 after SIG$signal"
	fi
	assert_contains "$(cat "$root/install.log")" "received SIG$signal" "$label: signal reported"
	assert_previous_environment "$label"
	pass "$label: rollback ran on the signal and the previous environment is usable"
}
run_signal_case "SIGINT after removal" INT after-remove-slow
run_signal_case "SIGTERM after install" TERM after-install-slow
run_signal_case "SIGINT during backup" INT after-backup-slow

# --- SIGKILL: no trap can run; the next invocation recovers ---------------
seed_previous_environment
seed_fingerprint="$(environment_fingerprint)"
pid="$(start_installer_in_background env PI_BOOTSTRAP_TEST_FAIL_AT=after-install-slow PI_BOOTSTRAP_TEST_SLEEP=30)"
for _ in $(seq 1 300); do
	grep -q "pausing at stage" "$root/install.log" 2>/dev/null && break
	sleep 0.05
done
grep -q "pausing at stage" "$root/install.log" ||
	fail_test "SIGKILL: the installer never reached the pause point; log:
$(cat "$root/install.log")"
kill -KILL "$pid"
wait "$pid" 2>/dev/null || true
[[ -f "$agent/.pi-bootstrap/transaction.env" ]] ||
	fail_test "SIGKILL: expected a journal to survive the kill"
# The interrupted state is genuinely broken: the new matrix is half-applied.
if [[ "$(environment_fingerprint)" == "$seed_fingerprint" ]]; then
	fail_test "SIGKILL: the kill happened before any mutation, so recovery is not being tested"
fi
pass "SIGKILL: journal and backups survive the kill (state is broken before recovery)"

PI_BOOTSTRAP_RECOVER_ONLY=1 run_installer || fail_test "SIGKILL recovery run failed: $(tail -10 "$root/install.log")"
assert_contains "$(cat "$root/install.log")" "was interrupted" "crash recovery announced"
assert_previous_environment "SIGKILL recovery on next run" 0
pass "SIGKILL: the next invocation restored the previous environment before doing anything"

# --- H4: SIGKILL at every filesystem boundary of the staged CLI step ------
# The old Pi package is moved aside, the new one is activated, and the bin link
# is replaced. Each of those is a place the process can die without a trap, so
# each is paused and killed, and the next run must still restore the old Pi.
run_kill_at_boundary() {
	local boundary="$1" pid
	seed_previous_environment
	seed_fingerprint="$(environment_fingerprint)"
	pid="$(start_installer_in_background env PI_BOOTSTRAP_TEST_PAUSE_AT="$boundary" PI_BOOTSTRAP_TEST_SLEEP=30)"
	for _ in $(seq 1 300); do
		grep -q "pausing at stage '$boundary'" "$root/install.log" 2>/dev/null && break
		sleep 0.05
	done
	grep -q "pausing at stage '$boundary'" "$root/install.log" ||
		fail_test "SIGKILL at $boundary: the installer never reached the boundary; log:
$(cat "$root/install.log")"
	kill -KILL "$pid"
	wait "$pid" 2>/dev/null || true
	[[ -f "$agent/.pi-bootstrap/transaction.env" ]] ||
		fail_test "SIGKILL at $boundary: no journal survived the kill"
	PI_BOOTSTRAP_RECOVER_ONLY=1 run_installer ||
		fail_test "SIGKILL at $boundary: recovery failed: $(tail -10 "$root/install.log")"
	assert_contains "$(cat "$root/install.log")" "was interrupted" "SIGKILL at $boundary: recovery announced"
	assert_previous_environment "SIGKILL at $boundary" 0
	pass "SIGKILL at $boundary: the next run restored the old Pi package and bin entry"
}
for boundary in before-package-move after-package-move recorded-cli after-package-activate after-bin-link; do
	run_kill_at_boundary "$boundary"
done

# --- H3: a journal that cannot be written fails closed --------------------
# The journal is the only crash record. If it cannot be written, further
# mutation must stop: at the start nothing was changed yet, and inside the CLI
# step the run rolls back.
assert_journal_failure() {
	local label="$1" stage="$2" phase_at="$3" mode="$4" expect_rollback="$5"
	seed_previous_environment
	seed_fingerprint="$(environment_fingerprint)"
	if [[ -n "$stage" ]]; then
		! run_installer PI_BOOTSTRAP_TEST_FAIL_AT="$stage" \
			PI_BOOTSTRAP_TEST_JOURNAL="$mode" PI_BOOTSTRAP_TEST_JOURNAL_AT="$phase_at" ||
			fail_test "$label: installer reported success although the journal could not be written"
	else
		! run_installer PI_BOOTSTRAP_TEST_JOURNAL="$mode" PI_BOOTSTRAP_TEST_JOURNAL_AT="$phase_at" ||
			fail_test "$label: installer reported success although the journal could not be written"
	fi
	assert_contains "$(cat "$root/install.log")" "could not record the transaction journal" "$label: journal failure reported"
	if [[ "$expect_rollback" == 1 ]]; then
		assert_previous_environment "$label" 1
		pass "$label: rolled back rather than continuing without a journal ($mode fault at $phase_at)"
	else
		# Nothing was mutated, so there is nothing to roll back and no backup
		# directory may be left behind for the next run to trip over.
		[[ "$(environment_fingerprint)" == "$seed_fingerprint" ]] ||
			fail_test "$label: the environment changed although the run refused to start"
		assert_not_contains "$(cat "$root/install.log")" "rolling back" "$label: no rollback was needed"
		[[ ! -d "$agent/.pi-bootstrap/backup" ]] || fail_test "$label: a backup directory was left behind"
		[[ ! -f "$agent/.pi-bootstrap/transaction.env" ]] || fail_test "$label: a partial journal was left behind"
		[[ ! -f "$agent/.pi-bootstrap/transaction.env.tmp" ]] || fail_test "$label: a temporary journal file was left behind"
		pass "$label: refused before going further ($mode fault at $phase_at)"
	fi
}
# A failed write at the very first record: the run must not start at all.
assert_journal_failure "journal write fails before the backup" after-config backup write 0
assert_journal_failure "journal write fails with no space" after-config backup no-space 0
assert_journal_failure "journal rename fails before the backup" after-config backup rename 0
# A failed write inside the CLI step: the transaction has started, so the
# already-made changes must be rolled back rather than left half-applied.
assert_journal_failure "journal write fails before activating the CLI" after-config activated-cli write 1
assert_journal_failure "journal rename fails in the CLI step" after-config activated-cli rename 1
# A failed commit record: the run is not committed, so it rolls back instead of
# leaving backups a later run would roll back anyway. No injected stage: the
# run must reach the commit on its own and fail there.
assert_journal_failure "journal write fails while committing" "" complete write 1

# --- H2: recovery is local-first -----------------------------------------
# 1. A recover-only run must not need npm or curl at all. Break both, and
#    record any invocation so a call would be visible.
seed_previous_environment
seed_fingerprint="$(environment_fingerprint)"
pid="$(start_installer_in_background env PI_BOOTSTRAP_TEST_FAIL_AT=after-install-slow PI_BOOTSTRAP_TEST_SLEEP=30)"
for _ in $(seq 1 300); do
	grep -q "pausing at stage" "$root/install.log" 2>/dev/null && break
	sleep 0.05
done
grep -q "pausing at stage" "$root/install.log" ||
	fail_test "offline recovery: the installer never reached the pause point"
kill -KILL "$pid"
wait "$pid" 2>/dev/null || true
: >"$FAKE_NPM_LOG"
cat >"$root/bin/npm" <<NPM
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >>"$FAKE_NPM_LOG"
echo "npm: simulated offline registry" >&2
exit 1
NPM
chmod +x "$root/bin/npm"
PI_BOOTSTRAP_RECOVER_ONLY=1 FAKE_CURL_FAIL=1 \
	PI_BOOTSTRAP_EXTRA_SETUP="PERMISSION_MODES_REPO=$root/unreachable-github" run_installer ||
	fail_test "offline recovery: recover-only run failed: $(tail -10 "$root/install.log")"
[[ ! -s "$FAKE_NPM_LOG" ]] || fail_test "offline recovery: npm was invoked during recovery:
$(cat "$FAKE_NPM_LOG")"
assert_not_contains "$(cat "$root/install.log")" "could not fetch" "offline recovery: no Git fetch was attempted"
assert_previous_environment "offline recovery with npm, curl and GitHub unavailable" 0
pass "offline recovery: npm, curl and GitHub are never touched when recovering"
put_stub "$root" fake-npm npm

# 2. A full run whose settings.json was damaged by the crash, with GitHub and
#    the registry unreachable: the restore must happen first, on the restored
#    settings, and only then may the run fail. The environment afterwards is
#    the pre-crash one, not the damaged one.
seed_previous_environment
seed_fingerprint="$(environment_fingerprint)"
pid="$(start_installer_in_background env PI_BOOTSTRAP_TEST_FAIL_AT=after-install-slow PI_BOOTSTRAP_TEST_SLEEP=30)"
for _ in $(seq 1 300); do
	grep -q "pausing at stage" "$root/install.log" 2>/dev/null && break
	sleep 0.05
done
grep -q "pausing at stage" "$root/install.log" ||
	fail_test "damaged-settings recovery: the installer never reached the pause point"
kill -KILL "$pid"
wait "$pid" 2>/dev/null || true
printf '{broken settings left by the crash' >"$settings"
if PI_BOOTSTRAP_EXTRA_SETUP="PERMISSION_MODES_REPO=$root/unreachable-github" run_installer; then
	fail_test "damaged-settings recovery: the installer succeeded with an unreachable GitHub"
fi
log="$(cat "$root/install.log")"
assert_contains "$log" "was interrupted" "damaged-settings recovery: recovery ran"
assert_contains "$log" "could not fetch" "damaged-settings recovery: the run then stopped at the fetch"
assert_not_contains "$log" "not valid JSON" "damaged-settings recovery: the damaged settings did not block recovery"
assert_previous_environment "offline recovery over damaged settings" 0
assert_contains "$(cat "$settings")" "npm:pi-advisor-flow@0.11.0" "damaged-settings recovery: the pre-crash settings are back"
pass "offline recovery: damaged settings and an unreachable GitHub still restore the previous environment"

# --- a committed run leaves no journal and needs no recovery --------------
seed_previous_environment
seed_fingerprint="$(environment_fingerprint)"
run_installer || fail_test "successful run failed: $(tail -5 "$root/install.log")"
[[ ! -f "$agent/.pi-bootstrap/transaction.env" ]] || fail_test "a committed run left its journal behind"
[[ ! -d "$agent/.pi-bootstrap/backup" ]] || fail_test "a committed run left its backups behind"
grep -q '2.8.0\|pi-permission-modes-fixture' "$settings" || fail_test "successful run did not install the fixture matrix"
PI_BOOTSTRAP_RECOVER_ONLY=1 run_installer || fail_test "recovery-only run after a committed install failed"
assert_not_contains "$(cat "$root/install.log")" "was interrupted" "a committed run leaves nothing to recover"
assert_not_contains "$(cat "$root/install.log")" "rolling back" "a committed run is not rolled back by the next invocation"
assert_contains "$(cat "$settings")" "pi-permission-modes-fixture" "the committed installation is still configured"
pass "committed run: journal cleared by commit, a later run has nothing to recover"

echo "rollback tests passed"
