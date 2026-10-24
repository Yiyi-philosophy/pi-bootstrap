#!/usr/bin/env bash
# R6: the transaction journal is untrusted DATA, never code.
#
# Every case here runs the real installer entry point (bash install.sh, no
# PI_BOOTSTRAP_TEST_ONLY) in an isolated HOME with a scratch agent directory,
# npm prefix, npm cache, TMPDIR and tmux config. Assertions are about the
# filesystem: which marker files exist afterwards, whether a restored file has
# its original bytes, whether the journal and backups survived, and whether npm
# or curl was invoked. Error text alone never counts as proof.
#
# Covered:
#   unsupported directory + malicious journal  refused before the journal is read
#   malformed journal in the supported dir     no record executes; evidence kept
#   valid interrupted transaction              recovers offline, restores bytes
#   journal / manifest tampering               no write outside managed roots
#   legacy (%q) journal                        recovered without execution
#   unparseable legacy journal                 refused, evidence kept
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

root="$(new_root)"
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"
install_stubs "$root"

agent="$PI_CODING_AGENT_DIR"
state="$agent/.pi-bootstrap"
backup="$state/backup"
journal="$state/transaction.env"
settings="$agent/settings.json"
extensions="$agent/extensions"

mkdir -p "$extensions" "$agent"

# --- helpers ---------------------------------------------------------------
tree_state() {
	local dir="$1"
	{
		if [[ -e "$dir" ]]; then
			find "$dir" -mindepth 1 -printf '%y %P\n' | LC_ALL=C sort
			find "$dir" -mindepth 1 -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
		fi
	} 2>/dev/null
}

agent_state() {
	local file
	{
		find "$agent" -mindepth 1 -path "$state" -prune -o -printf '%y %P\n' | LC_ALL=C sort
		for file in settings.json extensions/classifier-model.ts extensions/minimal-mode.ts keybindings.json; do
			if [[ -f "$agent/$file" ]]; then
				sha256sum "$agent/$file"
			else
				printf '%s absent\n' "$file"
			fi
		done
	} 2>/dev/null
}

# The state a successful recovery must reproduce: settings.json and
# classifier-model.ts as they were, and neither file the run created.
seed_agent_files() {
	rm -rf "$state" "$extensions"
	mkdir -p "$extensions"
	printf '{"theme":"previous","packages":[]}\n' >"$settings"
	printf 'export default function previousClassifier() {}\n' >"$extensions/classifier-model.ts"
	printf '{"app.thinking.cycle":"ctrl+tab","keep":true}\n' >"$agent/keybindings.json"
	rm -f "$agent/keybindings.json"
}

# A journal in the version-1 format, with the global fields spelled out only
# when a case passes them.
write_journal_v1() {
	local status="$1" phase="$2" prefix="${3:-}" package="${4:-}" bin="${5:-}" npm_root="${6:-}"
	mkdir -p "$state"
	{
		printf 'pi-bootstrap-journal 1\n'
		printf 'status=%s\n' "$status"
		printf 'phase=%s\n' "$phase"
		printf 'agent_dir=%s\n' "$agent"
		printf 'global_pi_package=%s\n' "$package"
		printf 'global_pi_bin=%s\n' "$bin"
		printf 'global_npm_prefix=%s\n' "$prefix"
		printf 'global_npm_root=%s\n' "$npm_root"
		printf 'pid=1\n'
	} >"$journal"
}

# A legitimate interrupted transaction plus the half-applied state a SIGKILL
# would leave: settings.json damaged, the two created files present with new
# bytes. Recovery must undo exactly that and nothing else.
seed_transaction() {
	seed_agent_files
	seed_state="$(agent_state)"
	mkdir -p "$backup/files"
	printf '{"theme":"previous","packages":[]}\n' >"$backup/settings.json"
	printf 'export default function previousClassifier() {}\n' >"$backup/files/001-classifier-model.ts"
	printf '%s\t%s\n' "$extensions/classifier-model.ts" "001-classifier-model.ts" >"$backup/files.tsv"
	printf '%s\n' "$extensions/minimal-mode.ts" >"$backup/created.list"
	printf '%s\n' "$agent/keybindings.json" >>"$backup/created.list"
	write_journal_v1 active activated-cli
	printf '{broken settings left by the crash' >"$settings"
	printf 'export default function interruptedClassifier() {}\n' >"$extensions/classifier-model.ts"
	printf 'export default function interruptedMinimal() {}\n' >"$extensions/minimal-mode.ts"
	printf '{"app.thinking.cycle":"interrupted"}\n' >"$agent/keybindings.json"
}

# Run the real entry point. Extra args are environment assignments.
# shellcheck disable=SC2120 # the unsupported-directory case passes assignments
run_installer() {
	local status=0
	env "$@" bash "$repo_dir/install.sh" >"$root/install.log" 2>&1 || status=$?
	return "$status"
}

# shellcheck disable=SC2120 # kept symmetric with run_installer
run_recover() {
	local status=0
	env "$@" PI_BOOTSTRAP_RECOVER_ONLY=1 bash "$repo_dir/install.sh" >"$root/install.log" 2>&1 || status=$?
	return "$status"
}

install_offline_stubs() {
	# A registry and a download host that record any call and then fail, so a
	# recovery that reaches for either is visible and cannot succeed by accident.
	: >"$root/npm.log"
	: >"$root/curl.log"
	cat >"$root/bin/npm" <<NPM
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >>"$root/npm.log"
echo "npm: simulated offline registry" >&2
exit 1
NPM
	cat >"$root/bin/curl" <<CURL
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >>"$root/curl.log"
echo "curl: simulated offline network" >&2
exit 7
CURL
	chmod +x "$root/bin/npm" "$root/bin/curl"
}

# --- 1. an unsupported agent directory is refused before its journal -------
# The journal would run a command if it were sourced. Nothing may be read out of
# that directory: no marker, no state directory, no byte changed.
unsupported="$root/unsupported-agent"
mkdir -p "$unsupported"
printf '{"packages":[]}\n' >"$unsupported/settings.json"
mkdir -p "$unsupported/.pi-bootstrap"
marker="$root/marker-unsupported"
{
	printf 'status=active\n'
	printf 'phase=backup\n'
	printf 'agent_dir=%s\n' "$unsupported"
	printf '$(touch %s)\n' "$marker"
	printf 'touch %s\n' "$root/marker-unsupported-plain"
} >"$unsupported/.pi-bootstrap/transaction.env"
unsupported_before="$(tree_state "$unsupported")"
unsupported_journal_before="$(sha256sum "$unsupported/.pi-bootstrap/transaction.env")"
if PI_CODING_AGENT_DIR="$unsupported" run_installer; then
	fail_test "unsupported directory: the installer accepted an unsupported agent directory"
fi
assert_contains "$(cat "$root/install.log")" "UNSUPPORTED" "unsupported directory: the refusal names the limitation"
assert_contains "$(cat "$root/install.log")" "nothing was changed" "unsupported directory: the refusal states nothing changed"
[[ ! -e "$marker" ]] || fail_test "unsupported directory: the journal was executed (marker created)"
[[ ! -e "$root/marker-unsupported-plain" ]] || fail_test "unsupported directory: the journal was executed (plain marker created)"
assert_eq "$unsupported_before" "$(tree_state "$unsupported")" "unsupported directory: its contents changed"
assert_eq "$unsupported_journal_before" "$(sha256sum "$unsupported/.pi-bootstrap/transaction.env")" \
	"unsupported directory: the journal was modified"
assert_not_contains "$(cat "$root/install.log")" "was interrupted" "unsupported directory: recovery ran anyway"
pass "unsupported directory: refused before its journal was read; journal, backups and marker untouched"

# --- 2. malformed journals in the supported directory never execute --------
# Each variant is placed where a legitimate journal lives. The installer must
# refuse, keep the journal and backups for diagnosis, and touch nothing.
malformed_case() {
	local label="$1" mutation="$2" extra_marker="${3:-}"
	seed_transaction
	local journal_before backup_before state_before
	"$mutation"
	journal_before="$(sha256sum "$journal")"
	backup_before="$(tree_state "$backup")"
	state_before="$(agent_state)"
	if run_recover; then
		fail_test "${label}: recovery accepted a malformed journal"
	fi
	assert_contains "$(cat "$root/install.log")" "could not be read safely" "${label}: the refusal says the journal is unsafe"
	assert_not_contains "$(cat "$root/install.log")" "rolling back" "${label}: no restore was attempted"
	assert_eq "$journal_before" "$(sha256sum "$journal")" "${label}: the journal was modified or removed"
	assert_eq "$backup_before" "$(tree_state "$backup")" "${label}: the backups were modified or removed"
	assert_eq "$state_before" "$(agent_state)" "${label}: the agent directory was modified"
	if [[ -n "$extra_marker" ]]; then
		[[ ! -e "$extra_marker" ]] || fail_test "${label}: a journal record was executed (marker created)"
	fi
	pass "${label}: refused, nothing executed, journal and backups preserved"
}

m_exec_record() {
	printf 'touch %s\n' "$root/marker-exec-record" >>"$journal"
}
m_unknown_key() {
	printf 'evil=1\n' >>"$journal"
}
m_duplicate_key() {
	printf 'status=active\n' >>"$journal"
}
m_invalid_status() {
	sed -i 's/^status=active$/status=root/' "$journal"
}
m_command_substitution() {
	sed -i "s|^status=active\$|status=\$(touch $root/marker-status)|" "$journal"
}
m_control_character() {
	printf 'pid=1\001\n' >>"$journal"
}
m_symlink_journal() {
	mv "$journal" "$root/outside-journal"
	ln -s "$root/outside-journal" "$journal"
}

malformed_case "journal with an executable-looking record" m_exec_record "$root/marker-exec-record"
malformed_case "journal with an unknown key" m_unknown_key
malformed_case "journal with a duplicate key" m_duplicate_key
malformed_case "journal with an invalid status" m_invalid_status
malformed_case "journal with a command substitution as a value" m_command_substitution "$root/marker-status"
malformed_case "journal with a control character" m_control_character
malformed_case "journal that is a symlink" m_symlink_journal

# --- 3. a valid interrupted transaction recovers offline -------------------
# seed_transaction records the clean pre-crash state in $seed_state before it
# damages anything, so the assertion below compares against the real original.
seed_transaction
install_offline_stubs
if ! run_recover; then
	fail_test "valid recovery: recovery failed offline:
$(cat "$root/install.log")"
fi
assert_contains "$(cat "$root/install.log")" "was interrupted" "valid recovery: the interrupted run is announced"
assert_eq "$seed_state" "$(agent_state)" "valid recovery: the pre-crash agent state was not restored"
assert_eq '{"theme":"previous","packages":[]}' "$(tr -d '\n' <"$settings")" "valid recovery: settings.json bytes"
[[ ! -e "$extensions/minimal-mode.ts" ]] || fail_test "valid recovery: a file the run created was left behind"
[[ ! -e "$agent/keybindings.json" ]] || fail_test "valid recovery: a file the run created was left behind"
[[ ! -e "$journal" ]] || fail_test "valid recovery: the journal was left behind after a successful restore"
[[ ! -e "$backup" ]] || fail_test "valid recovery: the backups were left behind after a successful restore"
[[ ! -s "$root/npm.log" ]] || fail_test "valid recovery: npm was invoked:
$(cat "$root/npm.log")"
[[ ! -s "$root/curl.log" ]] || fail_test "valid recovery: curl was invoked:
$(cat "$root/curl.log")"
assert_not_contains "$(cat "$root/install.log")" "could not fetch" "valid recovery: no fetch was attempted"
pass "valid recovery: offline restore of a damaged settings.json, no npm/curl/GitHub use"

# --- 4. crafted journals and manifests cannot write outside managed roots ---
outside="$root/outside"
mkdir -p "$outside"
printf 'original victim\n' >"$outside/victim"
outside_before="$(tree_state "$outside")"

# 4a. A journal that describes another directory must not drive this one.
seed_transaction
write_journal_v1 active backup "" "" "" ""
sed -i "s|^agent_dir=.*|agent_dir=$outside/agent|" "$journal"
journal_before="$(sha256sum "$journal")"
backup_before="$(tree_state "$backup")"
if run_recover; then
	fail_test "agent-dir tampering: recovery accepted a journal for another directory"
fi
assert_contains "$(cat "$root/install.log")" "the journal describes" "agent-dir tampering: the mismatch is named"
assert_eq "$journal_before" "$(sha256sum "$journal")" "agent-dir tampering: the journal was modified"
assert_eq "$backup_before" "$(tree_state "$backup")" "agent-dir tampering: the backups were modified"
assert_eq "$outside_before" "$(tree_state "$outside")" "agent-dir tampering: something was written outside"
pass "journal path tampering: a foreign agent directory is refused, nothing written"

# 4b. A crafted global package path is not a location recovery will write.
seed_transaction
write_journal_v1 active activated-cli "$root/npm-prefix" "$outside/@earendil-works/pi-coding-agent" \
	"$root/npm-prefix/bin/pi" "$root/npm-prefix/lib/node_modules"
mkdir -p "$backup/cli"
: >"$backup/cli/package.existed"
mkdir -p "$backup/cli/package"
printf 'not really a pi package\n' >"$backup/cli/package/sentinel"
outside_pkg_before="$(tree_state "$outside")"
if run_recover; then
	fail_test "package-path tampering: recovery accepted a package outside the recorded npm root"
fi
assert_contains "$(cat "$root/install.log")" "is not <prefix>/lib/node_modules" "package-path tampering: the path is rejected"
assert_eq "$outside_pkg_before" "$(tree_state "$outside")" "package-path tampering: something was written outside"
[[ ! -e "$outside/@earendil-works/pi-coding-agent" ]] ||
	fail_test "package-path tampering: the crafted package path was created"
assert_eq "original victim" "$(cat "$outside/victim")" "package-path tampering: an unrelated file changed"
pass "journal path tampering: a crafted global package path is refused, no writes outside"

# 4c. A backup manifest entry outside the managed paths stops the restore
# BEFORE the first destructive step (the classifier is still the crashed one).
manifest_tamper_case() {
	local label="$1" manifest="$2" entry="$3"
	seed_transaction
	printf '%s\n' "$entry" >>"$backup/$manifest"
	install_offline_stubs
	local journal_before backup_before
	journal_before="$(sha256sum "$journal")"
	backup_before="$(tree_state "$backup")"
	if run_recover; then
		fail_test "${label}: recovery accepted a manifest entry outside the managed paths"
	fi
	assert_contains "$(cat "$root/install.log")" "which is not a path this installer manages" "${label}: the entry is rejected"
	assert_eq "$journal_before" "$(sha256sum "$journal")" "${label}: the journal was modified"
	assert_eq "$backup_before" "$(tree_state "$backup")" "${label}: the backups were modified"
	# The crashed classifier is still in place: validation finished before the
	# first restore write, so the restore never started.
	assert_contains "$(cat "$extensions/classifier-model.ts")" "interruptedClassifier" \
		"${label}: the restore started before validation finished"
	assert_eq "original victim" "$(cat "$outside/victim")" "${label}: an unrelated file changed"
	assert_eq "$outside_before" "$(tree_state "$outside")" "${label}: something was written outside"
	pass "${label}: refused before any write, manifests preserved"
}
manifest_tamper_case "files.tsv tampering" "files.tsv" "$(printf '%s\t002-evil' "$outside/victim")"
manifest_tamper_case "created.list tampering" "created.list" "$outside/created-by-manifest"

# 4d. A prefix that this environment cannot confirm is not written to. The
# crafted prefix exists and carries a sentinel, so "nothing happened" is
# visible in the filesystem rather than inferred from the log.
crafted_prefix="$root/crafted-prefix"
mkdir -p "$crafted_prefix/bin" "$crafted_prefix/lib/node_modules"
printf 'sentinel\n' >"$crafted_prefix/bin/keep-me"
printf 'sentinel\n' >"$crafted_prefix/lib/node_modules/keep-me"
seed_transaction
write_journal_v1 active activated-cli "$crafted_prefix" \
	"$crafted_prefix/lib/node_modules/@earendil-works/pi-coding-agent" \
	"$crafted_prefix/bin/pi" "$crafted_prefix/lib/node_modules"
mkdir -p "$backup/cli"
: >"$backup/cli/package.existed"
: >"$backup/cli/bin.existed"
mkdir -p "$backup/cli/package"
printf 'previous package\n' >"$backup/cli/package/sentinel"
crafted_prefix_before="$(tree_state "$crafted_prefix")"
if run_recover; then
	fail_test "prefix tampering: recovery accepted an npm prefix this environment does not confirm"
fi
assert_contains "$(cat "$root/install.log")" "not the npm prefix configured for this environment" "prefix tampering: the prefix mismatch is named"
assert_eq "$crafted_prefix_before" "$(tree_state "$crafted_prefix")" "prefix tampering: the crafted prefix was written to"
[[ -f "$backup/cli/package/sentinel" ]] || fail_test "prefix tampering: the backup was consumed"
[[ -f "$journal" ]] || fail_test "prefix tampering: the journal was removed"
pass "journal path tampering: a prefix this environment does not confirm is refused"

# --- 5. legacy (%q) journals: parsed, never executed ----------------------
legacy_case_recover() {
	seed_transaction
	local journal_before
	{
		printf 'status=%q\n' "active"
		printf 'phase=%q\n' "activated-cli"
		printf 'agent_dir=%q\n' "$agent"
		printf 'pid=%q\n' "4242"
	} >"$journal"
	printf '{broken settings left by the crash' >"$settings"
	journal_before="$(sha256sum "$journal")"
	if ! run_recover; then
		fail_test "legacy journal: a valid pre-R7 journal was not recovered:
$(cat "$root/install.log")"
	fi
	assert_contains "$(cat "$root/install.log")" "was interrupted" "legacy journal: the interrupted run is announced"
	assert_eq '{"theme":"previous","packages":[]}' "$(tr -d '\n' <"$settings")" "legacy journal: settings.json bytes"
	[[ ! -e "$journal" ]] || fail_test "legacy journal: the journal was left behind after recovery"
	[[ ! -e "$marker" ]] || fail_test "legacy journal: a journal record was executed"
	[[ -n "$journal_before" ]] || fail_test "legacy journal: could not hash the journal"
	pass "legacy journal: recovered without executing it"
}

legacy_case_recover

# A pre-R4 journal records only the package and bin (lowercase names), with no
# npm prefix. It must still recover: the prefix is derived from those paths and
# validated like any other (here against the isolation tree's configured npm
# prefix), and the restore never needs the network.
legacy_prefix_derivation_case() {
	seed_transaction
	local derived_prefix="${npm_config_prefix%/}"
	[[ -n "$derived_prefix" ]] || fail_test "legacy pre-R4 journal: the test needs npm_config_prefix set"
	mkdir -p "$derived_prefix/bin" "$derived_prefix/lib/node_modules"
	{
		printf 'status=%q\n' "active"
		printf 'phase=%q\n' "activated-cli"
		printf 'agent_dir=%q\n' "$agent"
		printf 'global_package=%q\n' "$derived_prefix/lib/node_modules/@earendil-works/pi-coding-agent"
		printf 'global_bin=%q\n' "$derived_prefix/bin/pi"
		printf 'pid=%q\n' "4242"
	} >"$journal"
	printf '{broken settings left by the crash' >"$settings"
	if ! run_recover; then
		fail_test "legacy pre-R4 journal: it was not recovered:
$(cat "$root/install.log")"
	fi
	assert_eq '{"theme":"previous","packages":[]}' "$(tr -d '\n' <"$settings")" "legacy pre-R4 journal: settings.json bytes"
	[[ ! -e "$journal" ]] || fail_test "legacy pre-R4 journal: the journal was left behind after recovery"
	pass "legacy pre-R4 journal: prefix derived from the recorded package/bin, recovered without execution"
}

legacy_prefix_derivation_case

legacy_refusal_case() {
	local label="$1" body="$2" extra_marker="${3:-}"
	seed_transaction
	printf '%s\n' "$body" >"$journal"
	local journal_before backup_before state_before
	journal_before="$(sha256sum "$journal")"
	backup_before="$(tree_state "$backup")"
	state_before="$(agent_state)"
	if run_recover; then
		fail_test "${label}: recovery accepted a journal it cannot parse safely"
	fi
	assert_contains "$(cat "$root/install.log")" "could not be read safely" "${label}: the read failure is reported"
	assert_eq "$journal_before" "$(sha256sum "$journal")" "${label}: the journal was modified"
	assert_eq "$backup_before" "$(tree_state "$backup")" "${label}: the backups were modified"
	assert_eq "$state_before" "$(agent_state)" "${label}: the agent directory was modified"
	if [[ -n "$extra_marker" ]]; then
		[[ ! -e "$extra_marker" ]] || fail_test "${label}: a journal record was executed"
	fi
	pass "${label}: refused, journal and backups preserved"
}

legacy_refusal_case "legacy journal with \$'...' quoting" \
	"agent_dir=\$'$agent'"
legacy_refusal_case "legacy journal with an unknown record" \
	"evil=\$(touch $root/marker-legacy-unknown)
status=active"
[[ ! -e "$root/marker-legacy-unknown" ]] || fail_test "legacy refusal: an unknown record was executed"
legacy_refusal_case "legacy journal with duplicate aliases" \
	"GLOBAL_PI_PACKAGE=/one
global_package=/two"

# --- 6. nothing in this suite reached the developer's real environment -----
[[ "$HOME" == "$root"/* ]] || fail_test "isolation: HOME is not the scratch tree"
[[ "$PI_CODING_AGENT_DIR" == "$root"/* ]] || fail_test "isolation: the agent directory is not inside the scratch tree"
[[ ! -e "$HOME/.pi/agent/transaction.env" ]] || fail_test "isolation: a journal leaked into the real agent directory"

echo "journal trust boundary tests passed"
