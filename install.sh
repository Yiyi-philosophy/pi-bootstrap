#!/usr/bin/env bash
set -euo pipefail

# Tested version matrix. Keep this file self-contained for curl | bash installs.
# permission-modes is installed from an immutable upstream commit because the
# 2.8.0 source snapshot is not published on npm. It is a source-built pin, not
# an official npm release, and is verified against the manifest below.
PI_VERSION="1.4.0"
PI_BTW_VERSION="0.62.0"
PI_ADVISOR_FLOW_VERSION="0.14.2"
PERMISSION_MODES_VERSION="2.8.0"
PERMISSION_MODES_COMMIT="cf77816f28e102409dddbf8e537e4cf57aa092f0"
# SHA1 of the git tree object for PERMISSION_MODES_COMMIT. Together with the
# per-file SHA256 manifest this detects added, removed, and modified files.
PERMISSION_MODES_TREE="480649739171c272f355850cf6b6228ffa823c0c"
PERMISSION_MODES_HOST="github.com"
PERMISSION_MODES_PATH="GeorgeDong32/pi-permission-modes"
PERMISSION_MODES_REPO="https://${PERMISSION_MODES_HOST}/${PERMISSION_MODES_PATH}"
PERMISSION_MODES_NPM_NAME="@georgedong32/permission-modes"
PERMISSION_MODES_SOURCE="git:${PERMISSION_MODES_HOST}/${PERMISSION_MODES_PATH}@${PERMISSION_MODES_COMMIT}"
PI_BTW_SOURCE="npm:@narumitw/pi-btw@${PI_BTW_VERSION}"
PI_ADVISOR_FLOW_SOURCE="npm:pi-advisor-flow@${PI_ADVISOR_FLOW_VERSION}"
MINIMAL_MODE_URL="https://raw.githubusercontent.com/earendil-works/pi/v${PI_VERSION}/packages/coding-agent/examples/extensions/minimal-mode.ts"
MINIMAL_MODE_SHA256="040cbc7619b2e903888c8626e2fa55ca5e3f820535dfd1aadcb2060e156a8770"

# Pi resolves its config directory from PI_CODING_AGENT_DIR. PI_AGENT_DIR is
# this repository's historical override and keeps working for existing tests.
AGENT_DIR="${PI_AGENT_DIR:-${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}}"
EXTENSIONS_DIR="$AGENT_DIR/extensions"
KEYBINDINGS_FILE="$AGENT_DIR/keybindings.json"
SETTINGS_FILE="$AGENT_DIR/settings.json"
STATE_DIR="$AGENT_DIR/.pi-bootstrap"
PERMISSION_MODES_DIR="$AGENT_DIR/git/$PERMISSION_MODES_HOST/$PERMISSION_MODES_PATH"
TMUX_CONFIG="${TMUX_CONFIG_FILE:-$HOME/.tmux.conf}"

# SHA256 of every tracked file in the permission-modes source snapshot.
# Generated from a verified checkout of ${PERMISSION_MODES_COMMIT} by
# scripts/update-permission-modes-pin.sh, which also verifies the checkout is
# clean before rewriting anything. The per-file listing (rather than one
# aggregate hash) is kept deliberately: a mismatch names the exact file, which
# is what makes a low-cost review possible. Together with the pinned git tree
# it detects added, removed, and modified files.
PERMISSION_MODES_MANIFEST_COUNT=69
PERMISSION_MODES_MANIFEST="$(cat <<'PM_MANIFEST'
7387ce1305cf3b40c59ca3a121ccd82266b78f460d9c717694bb39429f3d5ca5  .github/workflows/release.yml
4d7f80ba3222d8510981d5302def0f5e934ecc98a110c5e54fc5c3cac05a2943  .github/workflows/test.yml
b8ef2be276125fde8eeb8e9aa64047e2eeecdefca46c4ec26be31f90ec074109  .gitignore
8f6c12d90033922d595c78fc90bd1701a90cd9ecef39cee659b3f55d7ee59087  AGENTS.md
f38d00ff9378e09c50a0b453baf42751bafe5b71d09e6195325b05f4eea04b4c  CHANGELOG.md
413ba30bd9d467f06ad6f9dd48b00c20b2a0f1c09c7f3580b3443db066df0d3b  CLAUDE.md
5f3e97c3e8cef9edb584f7d7785cc623966eb4fb8eefd1c5421e8a2797055206  LICENSE
8a789bc8d82783a9441fca0de3952e3d22dd3e611b2463d51c5bdcf1940a25a7  README.md
3561df3bed68d3c4babc0f5a3b31453f6af72f2c6bb204f04a980b3f024d8ba1  bash-permission-match.test.ts
f1371507650db63ae732be3e3794c92680fe11d296c16784f2dd6483ec1008e7  bash-permission-match.ts
83e1fcc9a63b9cd2d806b10b206946e7c69362df51a2c33c068c38bb8e46deec  branch-stats.test.ts
05b392a5f9bdadda000f0f508cd98ffb64ce97d2057d2c3abbb64e65ea58f926  branch-stats.ts
298f7b7f6611de4d40ced84ccce50a0a827a3b56fe35abb50ad35329c6dc96e5  cc-alignment.test.ts
d4b144d0ca5ecdd26a25ddde3de1293ecb198fcc46cdd87ae73090fd6f31c1af  classifier-client.test.ts
aea667388d565a9a6da6b629db079669c30859accc0a2a096b44ba68f529ae53  classifier-client.ts
48ca6742009dc62e518d6dbcf02327b861e726c1a2931e52172033ac73a53ae4  classifier-messages.ts
b17174bbc9f4e26d1cc45192f64a4cb5c66737e34526eac2c03a21dcc54ebb95  classifier-prompt.test.ts
6d49d8683f01806701f8528e28e968e946b55a3646bf440662ae9121d64b99c9  classifier-prompt.ts
eb04b2d2d3e2e276ac04fe31211ae1021db19c3e8139dd92613a02671147a51f  classifier-prompts/auto_mode_system_prompt.txt
3936ba0465c634d46bf0a6f899ecee1a4362fa718085db66137509dec7466e24  classifier-prompts/permissions_external.txt
be73ef8106c30b67d4007e924270f6ac62a021206681b01ce2736d88996679b6  classifier-redact.ts
13a53d959a77ad18af2b10dc5f1e4268df1504173f9869491584abe8d2946623  classifier-tool-projection.test.ts
b8f1cf2f92e652fe053be2b9a6a6d68ed94822dff2e579f4a8a3049e923dc13d  classifier-tool-projection.ts
23a358bc9a0e0267dd38fef1916829bd6c7a5da0b72cd41568546e3e5a3350eb  classifier-tool.ts
5454a1662158c0cb9c6c77cf46e975b4ce10ab27b2563e8e5e40b6c531d66aba  classifier-transcript.test.ts
2854f726cb922ca3ffe40fd102750e863f5ea06a42de07cbd8581e882b3ac49c  classifier-transcript.ts
5db5add1eba1cc5d009d98283746006af9ac359e64c2bb9c14cdde07ea780527  config-cache.test.ts
cfea6ae407c44bf138d0a681fb1a365408847c83acbbf005da556745d36eb485  config.ts
7745d4c2abba79cb0274bc7fd7aa332147ff1fd0a541094474c332a552f66134  dangerous-permissions.test.ts
b774ca4b7ade4f7fb302b89b2efb8488f546c9991e661a0baea934c72fa73f92  dangerous-permissions.ts
2a196771b00d18896f82ed53f8c4a0997675f13f28812af436ae085a50650cd7  denial-tracking.ts
b4578e974e65339c161fa6ae3e377e56e05ae0854faa3caa72bcb49c74fbd2ff  docs/PRD.md
e6ace746004f5a89347bd2ca5382988dca0f9ea213ae1e8af50b35523560e741  docs/bash-risk-adjudication-2026-09-12.md
79a94acf32ad802978ed348cf1364840538b3fe186610505f3d68b9edbc1e3b3  docs/project-intelligence.md
ea0492adb8f5b5c4b78379485cb23dbb5c80f56e5923765d6aa637f4d1a0e296  docs/prompts/ask-mode-prompts.md
f36e80036a091ccfe72c80caa7007ea994b686b50c9d97b1aa3b3702ad0f0a99  docs/prompts/auto-mode-prompts.md
4e3b0477b19f0fcd153786231f6a70633cd56d5b3ec5a8f6cf4e6c9afe812767  docs/prompts/plan-mode-prompts.md
90f62ef14d62cd215bb2e24bd6608cd73ba780ffd45bf293115b9bc8ad6e42ce  docs/suggestions.md
299fe37daf8c6933b8ccb4c86f2233a7b48111126304ebdd543a7657aa649a62  fusion-tools.test.ts
0ffb4f32762218a61f0d1f2759e91ac0117a24ae6c958db8c5612368f6eac561  fusion-tools.ts
55ff435b0c9f24667b9e090a58c3c575b4a66042af967caef49313576f13ba03  index.test.ts
3e86b5f7d4df1698e919582304951f01b8538cc0e990f72fd56f03c2fcfdc666  index.ts
2b191b13e28f59cde118d7b39049a7b597d3026f29e37f042bc54653101dd0ee  injection-probe.ts
6a42deeafa5bc3d942ecbf3c4376dafd4a942af65292b746e0bb82b8eff16d04  mode-inherit.test.ts
ebda851e77b8d49cba83e523ea2cd767ca3bf313c36a0f43cf2ca30c62073348  mode-inherit.ts
c90bcb3d9a17507941ae3627d6f866a8d8d34f0ce6fdbd9781a05608d54c748d  package.json
ba710320e2b9c5a3984f535defe277213d54092183617fcca3867cedaaa3616f  path-permission-match.test.ts
41f01665520ca173ad0d7957d650bdb7174656dccd3ef19a5b8cb324ffe5f8f5  path-permission-match.ts
dc72c59d22366262f3397e3123e6326c15d56cebe88d5b2e2974d04b13f22ad2  permission-forwarding.test.ts
fd10b0a2e60526c8732af919e2187cf5a5cb0367954cbc6c51fe474893dc44b2  permission-forwarding.ts
adfd6090201235ac7e1268d1467b8bcb443ce3b6c5de40200a10e98b5d036c23  permission-rule-parser.test.ts
28f94f11f409df425cca3a2a7f55a65009ee186fb6645fc13642e426ba7ee86d  permission-rule-parser.ts
5dc0ccdac1f2a8624a3d7839c1546abf2b33a6b62a11c973d5cbcf59f14db1b6  permissions-loader.test.ts
82dcdd8195ebb634c0f32b3f5809aaf710e201e476a794cb1f158ecc6e66f383  permissions-loader.ts
b0b0bc3d78bfe77b2be1d599ae9743f42d87b91f2f521b498101c499fbd53ce5  permissions.test.ts
a9e822fe49d3a1ff1ceb82913aefbf9a5dfb1ca6fd4bd44b9b9ffc594478d6e1  permissions.ts
b93d8dabb6dcef9e84533c5d35b34dd426fdf0c46eefe4e3bf4c6fdb19c38667  plan-approval-dialog.test.ts
fa7e7e1684b5da4cfc666181c28d68588711bae06c150d571bdf4489f8b0638e  plan-approval-dialog.ts
907f136fc1288f02ab49b116c622608add23b3e49b95d53775d742bb64323f3c  profiles.test.ts
4d24f32b8404419843dd4ba3fee022cc8b81e6292629a1358aa2e6f54ee29dad  profiles.ts
17f7606ce1f5ada4e56d9b936146e492f379a94b8c4cfad917f9a74fcf0692e9  session-branch.test.ts
e157c991d9bc0899a95232161e5239507d9f920d0cd95bf1cbae598e184af174  session-branch.ts
e54438c46b1596aab853972c641400dbda8a400ac8e12ac07d560f6836d8d2de  shell-rule-matching.test.ts
127edf33e57a3027087ce5bd606e4d9d3969f30adbb5099cf3511b1b7e72a72c  shell-rule-matching.ts
6e1a04c4eacc1a64a6d3476ecb394931871d613c6e48259381ce5a77ad955f77  test-fixtures.ts
136879e749f1de74090a556f351a6db686d25d7205d0c0cc480114b52098660f  tsconfig.json
b0e1f24fbd4e41e543cc228b539e80ebf5a4eb5a09281932c884c18e540f6ffc  utils.test.ts
b9f642fe19dffd7f489bc7fceb64d7651b9a4795207d56f265ddf96806d5e9e5  utils.ts
9e0ad94910a9e6938ba163ef354c748265ea25e2d44110ef3d26875ac297b55a  vitest.config.ts
PM_MANIFEST
)"
# Packages this bootstrap manages: for each, the source it wants installed and
# the Pi package identities that belong to it. Identities mirror Pi's own
# matching (npm package name; git host/path without a ref), so an old npm
# permission-modes entry is still recognized as this bootstrap's business while
# an unrelated package keeps its place.
managed_spec() {
	cat <<SPEC
[
	{"desired": "${PI_BTW_SOURCE}", "identities": ["npm:@narumitw/pi-btw"]},
	{"desired": "${PI_ADVISOR_FLOW_SOURCE}", "identities": ["npm:pi-advisor-flow"]},
	{"desired": "${PERMISSION_MODES_SOURCE}", "identities": ["npm:${PERMISSION_MODES_NPM_NAME}", "git:${PERMISSION_MODES_HOST}/${PERMISSION_MODES_PATH}"]}
]
SPEC
}

tmp_files=()
cleanup() {
	if ((${#tmp_files[@]})); then
		rm -rf "${tmp_files[@]}"
	fi
}

# ---------------------------------------------------------------------------
# Failure handling
#
# Rollback is driven entirely by the EXIT trap plus an on-disk journal, not by
# an ERR trap. That is deliberate:
#
#   * Bash does not inherit an ERR trap into functions, command substitutions,
#     or subshells unless `set -E` is on, so `trap ... ERR` silently misses the
#     nested-call failures that matter most.
#   * `set -e` does exit from any function or command substitution, and an EXIT
#     trap installed in `main` runs in the process that owns the mutation, so
#     every failure path (explicit `fail`, errexit, a signal) reaches the same
#     recovery code exactly once.
#   * SIGKILL and power loss cannot run any trap. Every destructive step is
#     therefore preceded by an on-disk record (journal + immutable backups), so
#     the next invocation restores the previous environment before doing
#     anything else.
#
# The recovery code is idempotent and reads its instructions from the backup
# directory, so the trap path and the after-crash path share one implementation.
# ---------------------------------------------------------------------------
RUN_PID=""
MUTATION_STARTED=0
RUN_COMMITTED=0
RECOVERY_ACTIVE=0
FAIL_REPORTED=0
BACKUP_DIR="$STATE_DIR/backup"
JOURNAL="$STATE_DIR/transaction.env"

journal_write() {
	local status="$1" phase="$2"
	local failure="could not record the transaction journal $JOURNAL"
	if [[ ! -d "$STATE_DIR" ]]; then
		warn "$failure: $STATE_DIR does not exist"
		return 1
	fi
	if journal_fault "$phase" write; then
		warn "$failure (write failed)"
		return 1
	fi
	# Every path recovery needs is stored here as a shell assignment, so a
	# recovery run never has to ask npm, git, or the network where the global
	# Pi lives.
	{
		printf 'status=%q\n' "$status"
		printf 'phase=%q\n' "$phase"
		printf 'agent_dir=%q\n' "$AGENT_DIR"
		printf 'GLOBAL_PI_PACKAGE=%q\n' "${GLOBAL_PI_PACKAGE:-}"
		printf 'GLOBAL_PI_BIN=%q\n' "${GLOBAL_PI_BIN:-}"
		printf 'GLOBAL_NPM_PREFIX=%q\n' "${GLOBAL_NPM_PREFIX:-}"
		printf 'GLOBAL_NPM_ROOT=%q\n' "${GLOBAL_NPM_ROOT:-}"
		printf 'pid=%q\n' "$$"
	} >"$JOURNAL.tmp" || {
		warn "$failure (write failed)"
		rm -f "$JOURNAL.tmp"
		return 1
	}
	if journal_fault "$phase" rename; then
		warn "$failure (atomic rename failed)"
		rm -f "$JOURNAL.tmp"
		return 1
	fi
	mv -f "$JOURNAL.tmp" "$JOURNAL" || {
		warn "$failure (rename failed)"
		rm -f "$JOURNAL.tmp"
		return 1
	}
}

# Test-only fault injection for the journal, exercised by
# scripts/tests/test-rollback.sh:
#   PI_BOOTSTRAP_TEST_JOURNAL=write|rename|no-space
#   PI_BOOTSTRAP_TEST_JOURNAL_AT=<phase>   restrict the fault to one phase
# "no-space" models ENOSPC: the temporary file cannot be written at all.
journal_fault() {
	local phase="$1" step="$2" mode="${PI_BOOTSTRAP_TEST_JOURNAL:-}"
	[[ -n "$mode" ]] || return 1
	[[ -z "${PI_BOOTSTRAP_TEST_JOURNAL_AT:-}" || "$PI_BOOTSTRAP_TEST_JOURNAL_AT" == "$phase" ]] || return 1
	case "$mode" in
		"$step") return 0 ;;
		no-space) [[ "$step" == write ]] && return 0 ;;
	esac
	return 1
}

warn() {
	echo "pi-bootstrap: warning: $*" >&2
}

fail() {
	echo "pi-bootstrap: error: $*" >&2
	FAIL_REPORTED=1
	exit 1
}

# Test-only fault injection. Failure stages are documented in README.md and
# exercised by scripts/tests/test-rollback.sh; an ordinary install never sets
# this. The nested and pipeline stages exist to prove rollback does not depend
# on an ERR trap being inherited into functions, command substitutions, or
# pipelines.
test_hook() {
	local stage="$1"
	[[ -n "${PI_BOOTSTRAP_TEST_FAIL_AT:-}" && "${PI_BOOTSTRAP_TEST_FAIL_AT}" == "$stage" ]] || return 0
	case "$stage" in
		nested)
			# Called directly (not in a || list): errexit must end the run on its
			# own, without an ERR trap, which is the property under test.
			test_nested_failure
			;;
		pipeline)
			test_pipeline_failure
			;;
		subshell)
			test_subshell_failure
			;;
		sleep | after-remove-slow | after-install-slow | after-backup-slow)
			# Not a failure: hold the run here so a test can deliver a signal.
			test_pause "$stage"
			;;
		*)
			fail "injected failure at stage '${stage}' (PI_BOOTSTRAP_TEST_FAIL_AT)"
			;;
	esac
}

# Named crash boundary inside the destructive CLI step, used by the SIGKILL
# matrix in scripts/tests/test-rollback.sh: every filesystem operation that
# recovery depends on is a place the process may die without running a trap.
test_boundary() {
	local stage="$1"
	[[ -n "${PI_BOOTSTRAP_TEST_PAUSE_AT:-}" && "${PI_BOOTSTRAP_TEST_PAUSE_AT}" == "$stage" ]] || return 0
	test_pause "$stage"
}

test_pause() {
	local stage="$1"
	echo "pi-bootstrap: test: pausing at stage '${stage}'" >&2
	if [[ -n "${PI_BOOTSTRAP_TEST_SIGNAL:-}" ]]; then
		# Deliver a real signal to this process (a signal test must not
		# depend on the shell's job-control SIG_IGN behavior for
		# background jobs).
		kill -"${PI_BOOTSTRAP_TEST_SIGNAL}" "$BASHPID"
		return 0
	fi
	# Background sleep + wait so the shell handles a signal immediately;
	# a foreground `sleep` defers trap handling until it returns.
	sleep "${PI_BOOTSTRAP_TEST_SLEEP:-5}" &
	wait $! 2>/dev/null || true
}

test_nested_failure() {
	# A failing command inside a nested function reached through a command
	# substitution: the classic case a non-errtrace ERR trap misses.
	test_inner_failure() {
		echo "partial output"
		return 7
	}
	test_outer_failure() {
		local captured
		captured="$(test_inner_failure)"
		echo "unreachable: ${captured}"
	}
	test_outer_failure
}

test_pipeline_failure() {
	# pipefail makes the pipeline fail even though the last stage succeeds.
	printf 'x\n' | grep -q 'definitely-absent' | cat
}

test_subshell_failure() {
	( exit 9 )
}

on_signal() {
	local name="$1" number="$2"
	echo "pi-bootstrap: received SIG${name}; rolling back" >&2
	# A second signal during rollback keeps the default (terminating) behavior:
	# the journal and backups remain, and the next run recovers from them.
	trap - INT TERM HUP
	exit $((128 + number))
}

on_exit() {
	local status=$?
	trap - EXIT INT TERM HUP ERR
	if [[ -n "$RUN_PID" && "$BASHPID" != "$RUN_PID" ]]; then
		# A subshell inherited the trap. The process that owns the transaction
		# performs recovery; this one only cleans up its own temporary files.
		cleanup
		exit "$status"
	fi
	if ((MUTATION_STARTED && !RUN_COMMITTED)); then
		if ((!FAIL_REPORTED && status == 0)); then
			echo "pi-bootstrap: error: install exited before completing" >&2
		elif ((!FAIL_REPORTED)); then
			echo "pi-bootstrap: error: unexpected failure (exit ${status})" >&2
		fi
		recover
	fi
	cleanup
	exit "$status"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		fail "checksum verification requires sha256sum or shasum"
	fi
}

# Move a path, falling back to copy+delete when source and destination are on
# different filesystems (a staging prefix under TMPDIR often is). The copy goes
# to a temporary sibling that is renamed into place only when complete, so a
# crash mid-copy never leaves a destination that recovery would mistake for a
# finished backup.
move_path() {
	local src="$1" dst="$2" staging
	if mv -f "$src" "$dst" 2>/dev/null; then
		return 0
	fi
	staging="${dst}.incoming.$$"
	rm -rf "$staging"
	cp -a "$src" "$staging" || {
		rm -rf "$staging"
		return 1
	}
	rm -rf "$dst" || {
		rm -rf "$staging"
		return 1
	}
	mv -f "$staging" "$dst" || {
		rm -rf "$staging"
		return 1
	}
	rm -rf "$src" || return 1
}

require_node_version() {
	local version major minor patch
	version="$(node -p 'process.versions.node')"
	if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
		fail "could not parse Node.js version: ${version}"
	fi
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	patch="${BASH_REMATCH[3]}"
	if ((major < 22 || (major == 22 && minor < 19))); then
		fail "Pi ${PI_VERSION} requires Node.js >=22.19.0; found ${major}.${minor}.${patch}"
	fi
}

# Return csi-u, extended, unsupported, or unknown. Accepts "3.5a" or "tmux 3.5a".
tmux_strategy_for_version() {
	local version="$1"
	version="${version#tmux }"
	if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+) ]]; then
		echo "unknown"
		return 0
	fi

	local major="${BASH_REMATCH[1]}"
	local minor="${BASH_REMATCH[2]}"
	if ((major > 3 || (major == 3 && minor >= 5))); then
		echo "csi-u"
	elif ((major == 3 && minor >= 2)); then
		echo "extended"
	else
		echo "unsupported"
	fi
}

# Inspect settings.json and report managed-package migration work as tabs:
#   conflict<TAB>message   settings are unusable or ambiguous; change nothing
#   remove<TAB>source      stale managed entry; remove before installing
#   missing<TAB>source     verify mode only: the desired source is not present
# Never edits settings.json; `pi remove` and `pi install` stay authoritative.
settings_tool() {
	local mode="$1"
	node - "$mode" "$SETTINGS_FILE" "$(managed_spec)" <<'NODE'
const fs = require("node:fs");
const [mode, file, specJson] = process.argv.slice(2);
const out = [];
const emit = (kind, value) => out.push(kind + "\t" + value);

let spec;
try {
	spec = JSON.parse(specJson);
} catch (error) {
	emit("conflict", "internal error: unreadable managed-package spec");
	process.stdout.write(out.join("\n") + "\n");
	process.exit(0);
}

// Mirror Pi's package identity: npm is the package name, git is host/path
// without the ref (see dist/core/package-manager.js getSourceMatchKey*).
function identity(source) {
	if (typeof source !== "string" || source.length === 0 || /[\t\n\r]/.test(source)) return undefined;
	if (source.startsWith("npm:")) {
		const match = source.slice(4).trim().match(/^(@?[^@]+(?:\/[^@]+)?)(?:@(.+))?$/);
		return match && match[1] ? "npm:" + match[1] : undefined;
	}
	let url = source.startsWith("git:") ? source.slice(4).trim() : source;
	let host, packagePath;
	const scp = url.match(/^git@([^:]+):(.+)$/);
	if (scp) {
		host = scp[1];
		packagePath = scp[2];
	} else if (/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) {
		try {
			const parsed = new URL(url);
			host = parsed.hostname;
			packagePath = parsed.pathname.replace(/^\/+/, "");
		} catch {
			return undefined;
		}
	} else {
		const slash = url.indexOf("/");
		if (slash < 0) return undefined;
		host = url.slice(0, slash);
		packagePath = url.slice(slash + 1);
		if (!host.includes(".") && host !== "localhost") return undefined;
	}
	const separator = packagePath.search(/[@#]/);
	if (separator >= 0) packagePath = packagePath.slice(0, separator);
	packagePath = packagePath.replace(/^\/+/, "").replace(/\.git$/, "");
	if (!host || !packagePath) return undefined;
	return `git:${host}/${packagePath}`;
}

const desiredByIdentity = new Map();
for (const item of spec) for (const id of item.identities) desiredByIdentity.set(id, item.desired);

let config = {};
if (fs.existsSync(file)) {
	let text;
	try {
		text = fs.readFileSync(file, "utf8");
	} catch (error) {
		emit("conflict", `cannot read ${file}: ${error.code || error.message}`);
	}
	if (text !== undefined && text.trim() !== "") {
		try {
			config = JSON.parse(text);
		} catch (error) {
			emit("conflict", `${file} is not valid JSON (${error.message}); fix or move it before running the installer`);
		}
		if (config === null || typeof config !== "object" || Array.isArray(config)) {
			emit("conflict", `${file} must contain a JSON object`);
			config = {};
		}
	}
}

let entries = [];
if (Object.prototype.hasOwnProperty.call(config, "packages")) {
	if (!Array.isArray(config.packages)) {
		emit("conflict", `${file} has a "packages" value that is not an array`);
	} else {
		entries = config.packages;
	}
}

// At most one removal per package identity: Pi matches removals by identity,
// so a second `pi remove` for the same package would fail with "not found".
const removals = new Map();
const present = new Set();
entries.forEach((entry, index) => {
	let source;
	if (typeof entry === "string") {
		source = entry;
	} else if (entry !== null && typeof entry === "object" && typeof entry.source === "string") {
		source = entry.source;
	} else {
		emit("conflict", `${file} packages[${index}] is neither a source string nor an object with a string "source"`);
		return;
	}
	const id = identity(source);
	if (!id || !desiredByIdentity.has(id)) return; // not managed by this bootstrap
	const desired = desiredByIdentity.get(id);
	if (source === desired) {
		present.add(desired);
		return;
	}
	if (typeof entry === "object") {
		// Pi keeps unknown keys when it rewrites an entry, so any extra key means
		// hand migration is needed rather than silently dropping user settings.
		const extra = Object.keys(entry).filter((key) => key !== "source");
		if (extra.length > 0) {
			emit("conflict", `${file} packages[${index}] keeps extra keys (${extra.join(", ")}) on managed package ${source}; migrating it automatically would drop them, so update this entry to ${desired} by hand`);
			return;
		}
	}
	if (!removals.has(id)) removals.set(id, source);
});

for (const source of removals.values()) emit("remove", source);
if (mode === "verify") {
	for (const item of spec) {
		if (!present.has(item.desired)) emit("missing", item.desired);
	}
}
process.stdout.write(out.length ? out.join("\n") + "\n" : "");
NODE
}

# Parse `settings_tool MODE` output into PLAN_CONFLICTS and PLAN_FINDINGS.
# Returns non-zero when settings.json cannot be inspected at all.
PLAN_CONFLICTS=()
PLAN_FINDINGS=()
read_settings_plan() {
	local mode="$1" plan line kind value
	PLAN_CONFLICTS=()
	PLAN_FINDINGS=()
	plan="$(settings_tool "$mode")" || return 1
	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		kind="${line%%$'\t'*}"
		value="${line#*$'\t'}"
		case "$kind" in
			conflict) PLAN_CONFLICTS+=("$value") ;;
			remove | missing) PLAN_FINDINGS+=("$value") ;;
		esac
	done <<<"$plan"
	return 0
}

report_conflicts() {
	((${#PLAN_CONFLICTS[@]})) || return 0
	printf 'pi-bootstrap: %s\n' "${PLAN_CONFLICTS[@]}" >&2
	fail "refusing to modify $SETTINGS_FILE until the conflict(s) above are resolved"
}

# Fail closed unless settings.json can be read and migrated unambiguously.
check_settings() {
	local mode="$1"
	read_settings_plan "$mode" || fail "could not inspect $SETTINGS_FILE"
	report_conflicts
	if [[ "$mode" == "verify" && ${#PLAN_FINDINGS[@]} -gt 0 ]]; then
		printf 'pi-bootstrap: package entry missing or stale: %s\n' "${PLAN_FINDINGS[@]}" >&2
		fail "settings.json does not list the expected package sources"
	fi
}

# Remove managed entries that do not match the pinned matrix. Entries for other
# packages are never touched; `pi remove` failing is fatal (Pi deletes files
# before checking settings, so a silent failure could leave a broken install).
# The files `pi remove` deletes are already snapshotted by begin_transaction().
migrate_managed_packages() {
	local value
	read_settings_plan plan || fail "could not inspect $SETTINGS_FILE"
	report_conflicts

	for value in ${PLAN_FINDINGS[@]+"${PLAN_FINDINGS[@]}"}; do
		echo "Removing stale package entry: ${value}"
		if ! "$PI_BIN" remove "$value"; then
			fail "pi remove failed for ${value}; Pi may already have deleted the package files"
		fi
	done
	test_hook after-remove

	read_settings_plan plan || fail "could not re-inspect $SETTINGS_FILE after removal"
	if ((${#PLAN_FINDINGS[@]})); then
		printf 'pi-bootstrap: still stale after removal: %s\n' "${PLAN_FINDINGS[@]}" >&2
		fail "stale managed package entries are still present in $SETTINGS_FILE"
	fi
}

# Verify a source checkout against the pinned commit, tree, and file manifest.
verify_source_tree() {
	local dir="$1" expect_commit="$2" expect_tree="$3"
	local head tree status expected rel actual count=0 failures=0 tracked

	head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
	[[ "$head" == "$expect_commit" ]] || fail "source checkout is at ${head:-unknown}, expected ${expect_commit}"
	tree="$(git -C "$dir" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
	[[ "$tree" == "$expect_tree" ]] || fail "source tree ${tree:-unknown} does not match the pinned tree ${expect_tree}"
	status="$(git -C "$dir" status --porcelain 2>/dev/null || true)"
	[[ -z "$status" ]] || fail "source checkout at $dir has local modifications:
$status"

	while read -r expected rel; do
		[[ -n "$expected" && -n "$rel" ]] || continue
		if [[ ! -f "$dir/$rel" ]]; then
			echo "pi-bootstrap: manifest file missing: $rel" >&2
			failures=$((failures + 1))
			continue
		fi
		actual="$(hash_file "$dir/$rel")"
		if [[ "$actual" != "$expected" ]]; then
			echo "pi-bootstrap: checksum mismatch: $rel" >&2
			failures=$((failures + 1))
		fi
		count=$((count + 1))
	done < <(printf '%s\n' "$PERMISSION_MODES_MANIFEST")

	if ((count != PERMISSION_MODES_MANIFEST_COUNT)); then
		fail "verified ${count}/${PERMISSION_MODES_MANIFEST_COUNT} manifest entries"
	fi
	tracked="$(git -C "$dir" ls-files | wc -l | tr -d ' ')"
	if [[ "$tracked" != "$PERMISSION_MODES_MANIFEST_COUNT" ]]; then
		fail "source checkout tracks ${tracked} files, expected ${PERMISSION_MODES_MANIFEST_COUNT}"
	fi
	if ((failures > 0)); then
		fail "source verification failed (${failures} problem(s))"
	fi
}

verify_permission_modes() {
	local dir="$1"
	verify_source_tree "$dir" "$PERMISSION_MODES_COMMIT" "$PERMISSION_MODES_TREE"
	echo "permission-modes ${PERMISSION_MODES_VERSION} source verified: commit ${PERMISSION_MODES_COMMIT:0:12}, tree ${PERMISSION_MODES_TREE:0:12}, ${PERMISSION_MODES_MANIFEST_COUNT} files match the SHA256 manifest."
}

# Fetch the pinned commit into an isolated directory and verify it before
# anything runs from it. `pi install` still performs its own clone of the same
# immutable commit; the post-install check re-verifies that checkout.
prepare_source_snapshot() {
	local repo="$1" commit="$2" tree="$3"
	local staging
	staging="$(mktemp -d)"
	tmp_files+=("$staging")

	echo "Fetching permission-modes source for pre-install verification..."
	git init --quiet "$staging/repo" || fail "could not create a staging repository"
	git -C "$staging/repo" remote add origin "$repo" || fail "could not configure the staging remote"
	git -C "$staging/repo" fetch --quiet --depth 1 origin "$commit" ||
		fail "could not fetch ${commit} from ${repo}"
	git -C "$staging/repo" -c advice.detachedHead=false checkout --quiet FETCH_HEAD ||
		fail "could not check out ${commit} in the staging repository"
	verify_source_tree "$staging/repo" "$commit" "$tree"
	echo "Pre-install verification passed: ${commit:0:12} contains exactly the audited files."
}

prepare_permission_modes_snapshot() {
	prepare_source_snapshot "$PERMISSION_MODES_REPO" "$PERMISSION_MODES_COMMIT" "$PERMISSION_MODES_TREE"
}

# Pi's git install runs `npm install --omit=dev --legacy-peer-deps` inside the
# checkout before writing settings, and Pi has no flag to suppress lifecycle
# scripts. npm_config_ignore_scripts removes that code-execution surface; these
# packages ship prebuilt, so no build step is lost.
install_managed_packages() {
	export npm_config_ignore_scripts=1
	test_hook after-remove-slow

	echo "Installing default Pi extensions..."
	"$PI_BIN" install "$PI_BTW_SOURCE" || fail "could not install $PI_BTW_SOURCE"
	"$PI_BIN" install "$PI_ADVISOR_FLOW_SOURCE" || fail "could not install $PI_ADVISOR_FLOW_SOURCE"

	echo "Installing permission-modes ${PERMISSION_MODES_VERSION} from pinned upstream commit ${PERMISSION_MODES_COMMIT:0:12}..."
	echo "(source built from the pinned commit, not an official npm release; SHA256-verified)"
	"$PI_BIN" install "$PERMISSION_MODES_SOURCE" || fail "could not install $PERMISSION_MODES_SOURCE"
	test_hook after-install
	test_hook after-install-slow
}

# ---------------------------------------------------------------------------
# Global Pi CLI: staged install, non-destructive activation
#
# `npm install -g` writes into the live prefix, so a failure mid-install could
# leave a broken `pi` behind. Instead the package is installed into a throwaway
# prefix, verified, and only then activated by moving the old package aside and
# the new one into place (same filesystem => rename, not copy). Recovery moves
# the old package back and restores the bin link byte-for-byte.
# ---------------------------------------------------------------------------
resolve_global_paths() {
	GLOBAL_NPM_PREFIX="$(npm prefix -g 2>/dev/null | tr -d '\r' | tail -n 1)" || GLOBAL_NPM_PREFIX=""
	GLOBAL_NPM_ROOT="$(npm root -g 2>/dev/null | tr -d '\r' | tail -n 1)" || GLOBAL_NPM_ROOT=""
	# Some npm configurations (and the test stub) answer only one of the two;
	# each is derivable from the other for a standard prefix layout.
	if [[ -z "$GLOBAL_NPM_PREFIX" && -n "$GLOBAL_NPM_ROOT" ]]; then
		GLOBAL_NPM_PREFIX="$(dirname "$(dirname "$GLOBAL_NPM_ROOT")")"
	fi
	if [[ -z "$GLOBAL_NPM_ROOT" && -n "$GLOBAL_NPM_PREFIX" && -n "${GLOBAL_PI_PACKAGE:-}" ]]; then
		GLOBAL_NPM_ROOT="$(dirname "$(dirname "$GLOBAL_PI_PACKAGE")")"
	fi
	if [[ -z "$GLOBAL_NPM_ROOT" && -n "$GLOBAL_NPM_PREFIX" ]]; then
		GLOBAL_NPM_ROOT="$GLOBAL_NPM_PREFIX/lib/node_modules"
	fi
	[[ -n "$GLOBAL_NPM_ROOT" ]] || fail "could not determine the npm global root (npm root -g / npm prefix -g)"
	[[ -n "$GLOBAL_NPM_PREFIX" ]] || fail "could not determine the npm global prefix (npm prefix -g)"
	GLOBAL_PI_PACKAGE="$GLOBAL_NPM_ROOT/@earendil-works/pi-coding-agent"
	GLOBAL_PI_BIN="$GLOBAL_NPM_PREFIX/bin/pi"
}

# The activation step moves the old Pi package aside, so the global prefix must
# be writable by this user. Check that before any backup is taken: a root-owned
# npm prefix would otherwise fail halfway through with a confusing message.
require_writable_global_prefix() {
	local package_parent bin_dir
	package_parent="$(dirname "$GLOBAL_PI_PACKAGE")"
	bin_dir="$GLOBAL_NPM_PREFIX/bin"
	[[ -d "$package_parent" ]] || mkdir -p "$package_parent" 2>/dev/null || true
	[[ -d "$bin_dir" ]] || mkdir -p "$bin_dir" 2>/dev/null || true
	for dir in "$package_parent" "$bin_dir"; do
		[[ -w "$dir" ]] || fail "the npm global directory $dir is not writable by this user; run the installer with the same privileges used to install Pi (for example a user-owned prefix via \`npm config set prefix\`)"
	done
}

read_package_version() {
	local manifest="$1"
	node -e 'try { const m = require(process.argv[1]); process.stdout.write(String(m.version || "")); } catch { process.exit(1); }' "$manifest" 2>/dev/null
}

install_pi_cli_staged() {
	local stage staged_pkg staged_version cli_rel bin_target
	stage="$(mktemp -d)"
	tmp_files+=("$stage")

	resolve_global_paths

	echo "Installing Pi Coding Agent ${PI_VERSION} into a staging prefix..."
	npm install -g --ignore-scripts --prefix "$stage" "@earendil-works/pi-coding-agent@${PI_VERSION}" ||
		fail "npm could not stage Pi ${PI_VERSION}"
	staged_pkg="$stage/lib/node_modules/@earendil-works/pi-coding-agent"
	[[ -f "$staged_pkg/package.json" ]] || fail "the staged Pi install has no package.json (looked in $staged_pkg)"
	staged_version="$(read_package_version "$staged_pkg/package.json")" ||
		fail "could not read the staged Pi version"
	[[ "$staged_version" == "$PI_VERSION" ]] ||
		fail "staged Pi is version ${staged_version}, expected ${PI_VERSION}"

	cli_rel="$(node -e '
		const fs = require("node:fs");
		const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
		const bin = typeof manifest.bin === "string" ? manifest.bin : manifest.bin && manifest.bin.pi;
		if (!bin) process.exit(1);
		process.stdout.write(bin);
	' "$staged_pkg/package.json")" || fail "the staged Pi package declares no pi bin entry"
	[[ -f "$staged_pkg/$cli_rel" ]] || fail "the staged Pi CLI entry point is missing: $staged_pkg/$cli_rel"

	mkdir -p "$BACKUP_DIR/cli" || fail "could not create $BACKUP_DIR/cli"
	rm -f "$BACKUP_DIR/cli/package.created" \
		"$BACKUP_DIR/cli/bin.existed" "$BACKUP_DIR/cli/bin.created" \
		"$BACKUP_DIR/cli/bin-target" "$BACKUP_DIR/cli/bin-file"

	# The journal carries the global paths before any of them is touched, so a
	# recovery run never has to ask npm (or the network) where Pi lives.
	journal_write active activated-cli ||
		fail "could not record the transaction journal $JOURNAL; the global Pi was not touched"

	# Every decision is recorded BEFORE the filesystem operation it describes
	# (H4). A crash between the two then leaves a record that is merely
	# conservative: the marker says "there was a package" while the package is
	# still in place, which recovery handles because the moved tree itself is
	# the authoritative backup (see restore_from_backup). Recording after the
	# move, as before, could strand a moved-away Pi package with no record of
	# where it came from.
	if [[ -e "$GLOBAL_PI_PACKAGE" ]]; then
		: >"$BACKUP_DIR/cli/package.existed" || fail "could not record the existing Pi package"
		# The H4 window: the record exists, the package has not moved yet.
		test_boundary before-package-move
		move_path "$GLOBAL_PI_PACKAGE" "$BACKUP_DIR/cli/package" ||
			fail "could not move the existing Pi package aside ($GLOBAL_PI_PACKAGE)"
		test_boundary after-package-move
	else
		# There was no global Pi before: a rollback must remove the one this run
		# activates, or the machine is left with a Pi the user never installed.
		: >"$BACKUP_DIR/cli/package.created" || fail "could not record the missing Pi package"
	fi
	if [[ -e "$GLOBAL_PI_BIN" || -L "$GLOBAL_PI_BIN" ]]; then
		local old_target
		: >"$BACKUP_DIR/cli/bin.existed" || fail "could not record the existing pi bin entry"
		if [[ -L "$GLOBAL_PI_BIN" ]]; then
			old_target="$(readlink "$GLOBAL_PI_BIN" 2>/dev/null || true)"
			[[ -z "$old_target" ]] || printf '%s\n' "$old_target" >"$BACKUP_DIR/cli/bin-target" ||
				fail "could not record the pi bin link target"
			rm -f "$BACKUP_DIR/cli/bin-file"
		else
			# npm normally links the bin entry, but a plain wrapper script is a
			# legitimate global install shape and must be restored byte-for-byte.
			cp -p "$GLOBAL_PI_BIN" "$BACKUP_DIR/cli/bin-file" ||
				fail "could not back up $GLOBAL_PI_BIN"
			rm -f "$BACKUP_DIR/cli/bin-target"
		fi
	else
		# Likewise for the bin entry: record that it must be removed again.
		: >"$BACKUP_DIR/cli/bin.created" || fail "could not record the missing pi bin entry"
	fi
	test_boundary recorded-cli

	mkdir -p "$(dirname "$GLOBAL_PI_PACKAGE")" "$GLOBAL_NPM_PREFIX/bin" ||
		fail "could not create the npm global directories"
	move_path "$staged_pkg" "$GLOBAL_PI_PACKAGE" || fail "could not activate the staged Pi package"
	test_boundary after-package-activate
	bin_target="$(node -e '
		const path = require("node:path");
		process.stdout.write(path.relative(process.argv[1], process.argv[2]));
	' "$GLOBAL_NPM_PREFIX/bin" "$GLOBAL_PI_PACKAGE/$cli_rel")" || fail "could not compute the pi bin link target"
	ln -sfn "$bin_target" "$GLOBAL_PI_BIN" || fail "could not create the pi bin link at $GLOBAL_PI_BIN"
	test_boundary after-bin-link

	PI_BIN="$GLOBAL_PI_BIN"
	verify_pi_version "$PI_BIN"
	test_hook after-pi-install
}

verify_pi_version() {
	local bin="$1" output version
	output="$("$bin" --version 2>/dev/null | tr -d '\r')" ||
		fail "could not read the installed Pi version from $bin"
	version="${output##* }"
	[[ "$version" == "$PI_VERSION" ]] ||
		fail "Pi ${version:-unknown} is installed at $bin, expected exactly ${PI_VERSION}"
}

# The pinned npm packages and the pinned source must be the versions the matrix
# names, not merely "some version that loads".
verify_installed_versions() {
	local btw_manifest advisor_manifest pm_manifest installed minimal_hash
	btw_manifest="$AGENT_DIR/npm/node_modules/@narumitw/pi-btw/package.json"
	advisor_manifest="$AGENT_DIR/npm/node_modules/pi-advisor-flow/package.json"
	pm_manifest="$PERMISSION_MODES_DIR/package.json"

	local name path expected actual
	while read -r name path expected; do
		[[ -f "$path" ]] || fail "${name} is not installed at ${path}"
		actual="$(read_package_version "$path")" || fail "could not read the version of ${name}"
		[[ "$actual" == "$expected" ]] ||
			fail "${name} ${actual} is installed, expected exactly ${expected}"
	done <<VERSIONS
pi-btw ${btw_manifest} ${PI_BTW_VERSION}
pi-advisor-flow ${advisor_manifest} ${PI_ADVISOR_FLOW_VERSION}
permission-modes ${pm_manifest} ${PERMISSION_MODES_VERSION}
VERSIONS

	installed="$EXTENSIONS_DIR/minimal-mode.ts"
	[[ -f "$installed" ]] || fail "minimal-mode.ts is not installed at ${installed}"
	minimal_hash="$(hash_file "$installed")"
	[[ "$minimal_hash" == "$MINIMAL_MODE_SHA256" ]] ||
		fail "installed minimal-mode.ts does not match the pinned checksum"
}

# ---------------------------------------------------------------------------
# Real-runtime verification (embedded copy of scripts/lib/verify-stack.mjs)
# ---------------------------------------------------------------------------
VERIFY_STACK_JS=""
materialize_verify_stack() {
	local dir
	dir="$(mktemp -d)"
	tmp_files+=("$dir")
	# Node picks the module type from the extension, so the file must keep .mjs.
	VERIFY_STACK_JS="$dir/verify-stack.mjs"
	cat >"$VERIFY_STACK_JS" <<'VERIFY_STACK_JS_BODY'
#!/usr/bin/env node
// Load the managed stack through the REAL Pi extension loader.
//
// The installer embeds this file (see install.sh, VERIFY_STACK_JS) so that a
// `curl | bash` install can verify its own result without a checkout. It is
// used in two ways:
//
//   capture  before a mutation: record the Pi version and the commands the
//            current installation actually registers.
//   verify   after a rollback (or at the end of a successful install): prove
//            that Pi and the managed packages still load and that the recorded
//            commands are registered again.
//
// Only packages this bootstrap manages are loaded, plus the two extension files
// it writes. Unrelated user packages are never executed by this check.
//
// Paired copy: the same source lives in scripts/lib/verify-stack.mjs;
// scripts/check-embedded-extension.sh keeps the two byte-identical.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const PI_PACKAGE = "@earendil-works/pi-coding-agent";

// Identities this bootstrap manages. Mirrors managed_spec() in install.sh.
const MANAGED = [
	"npm:@narumitw/pi-btw",
	"npm:pi-advisor-flow",
	"npm:@georgedong32/permission-modes",
	"git:github.com/GeorgeDong32/pi-permission-modes",
];

const EXTENSION_FILES = ["classifier-model.ts", "minimal-mode.ts"];

function usage(message) {
	if (message) console.error(message);
	console.error(
		"usage: verify-stack.mjs --pi-bin <path> --agent-dir <dir> [--mode capture|verify] [--expect <file>] [--json-out <file>] [--require-command <name>]",
	);
	process.exit(2);
}

function parseArgs(argv) {
	const options = { mode: "capture", expectFrom: undefined, jsonOut: undefined, requireCommands: [] };
	for (let i = 0; i < argv.length; i += 1) {
		const flag = argv[i];
		const value = argv[i + 1];
		switch (flag) {
			case "--mode":
				if (value !== "capture" && value !== "verify") usage(`--mode must be capture or verify, got ${value}`);
				options.mode = value;
				i += 1;
				break;
			case "--pi-bin":
				options.piBin = value;
				i += 1;
				break;
			case "--agent-dir":
				options.agentDir = value;
				i += 1;
				break;
			case "--expect":
				options.mode = "verify";
				options.expectFrom = value;
				i += 1;
				break;
			case "--require-command":
				if (!value) usage("--require-command needs a command name");
				options.requireCommands.push(value);
				i += 1;
				break;
			case "--json-out":
				options.jsonOut = value;
				i += 1;
				break;
			default:
				usage(`unknown argument: ${flag}`);
		}
	}
	if (!options.piBin || !options.agentDir) usage("--pi-bin and --agent-dir are required");
	return options;
}

// Resolve the Pi package directory from the CLI path npm created for it. The
// bin entry is a symlink into the package, so walk up until the manifest that
// belongs to this package is found.
function resolvePiPackage(piBin) {
	let current;
	try {
		current = fs.realpathSync(piBin);
	} catch {
		return undefined;
	}
	if (fs.statSync(current).isDirectory()) current = path.join(current, "package.json");
	for (;;) {
		const manifestPath = path.join(current, "package.json");
		if (fs.existsSync(manifestPath)) {
			try {
				const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
				if (manifest.name === PI_PACKAGE) return { dir: current, version: manifest.version, manifest };
			} catch {
				// unreadable manifest: keep walking
			}
		}
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function identity(source) {
	if (typeof source !== "string" || source.length === 0) return undefined;
	if (source.startsWith("npm:")) {
		const match = source.slice(4).trim().match(/^(@?[^@]+(?:\/[^@]+)?)(?:@(.+))?$/);
		return match && match[1] ? `npm:${match[1]}` : undefined;
	}
	let url = source.startsWith("git:") ? source.slice(4).trim() : source;
	let host;
	let packagePath;
	const scp = url.match(/^git@([^:]+):(.+)$/);
	if (scp) {
		host = scp[1];
		packagePath = scp[2];
	} else if (/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) {
		try {
			const parsed = new URL(url);
			host = parsed.hostname;
			packagePath = parsed.pathname.replace(/^\/+/, "");
		} catch {
			return undefined;
		}
	} else {
		const slash = url.indexOf("/");
		if (slash < 0) return undefined;
		host = url.slice(0, slash);
		packagePath = url.slice(slash + 1);
		if (!host.includes(".") && host !== "localhost") return undefined;
	}
	const separator = packagePath.search(/[@#]/);
	if (separator >= 0) packagePath = packagePath.slice(0, separator);
	packagePath = packagePath.replace(/^\/+/, "").replace(/\.git$/, "");
	if (!host || !packagePath) return undefined;
	return `git:${host}/${packagePath}`;
}

function installPath(agentDir, id) {
	if (id.startsWith("npm:")) return path.join(agentDir, "npm", "node_modules", id.slice(4));
	return path.join(agentDir, "git", id.slice(4));
}

function readJson(file) {
	try {
		return JSON.parse(fs.readFileSync(file, "utf8"));
	} catch {
		return undefined;
	}
}

// Entry points declared by a package manifest ("pi.extensions"), else index.ts
// / index.js, matching Pi's own resolveExtensionEntries().
function packageEntries(dir) {
	const manifest = readJson(path.join(dir, "package.json"));
	const declared = manifest?.pi?.extensions;
	if (Array.isArray(declared) && declared.length > 0) return declared.map((entry) => path.join(dir, entry));
	for (const candidate of ["index.ts", "index.js"]) {
		const full = path.join(dir, candidate);
		if (fs.existsSync(full)) return [full];
	}
	return [];
}

function describeSource(agentDir, id) {
	const dir = installPath(agentDir, id);
	const manifest = readJson(path.join(dir, "package.json"));
	const info = { id, path: dir, version: manifest?.version, present: fs.existsSync(dir) };
	if (manifest?.name) info.name = manifest.name;
	return info;
}

const options = parseArgs(process.argv.slice(2));
const pi = resolvePiPackage(options.piBin);
if (!pi) {
	const payload = {
		ok: true,
		skipped: true,
		reason: `could not resolve the ${PI_PACKAGE} package from ${options.piBin}`,
	};
	if (options.jsonOut) fs.writeFileSync(options.jsonOut, `${JSON.stringify(payload, null, 2)}\n`);
	console.log(`SKIP stack verification: ${payload.reason}`);
	// 3 = "nothing could be verified". Distinct from PASS (0) so a caller can
	// never mistake an unproven environment for a working one.
	process.exit(3);
}

const agentDir = path.resolve(options.agentDir);
const settings = readJson(path.join(agentDir, "settings.json")) ?? {};
const configured = new Map();
for (const entry of Array.isArray(settings.packages) ? settings.packages : []) {
	const source = typeof entry === "string" ? entry : entry && entry.source;
	const id = identity(source);
	if (id && MANAGED.includes(id) && !configured.has(id)) configured.set(id, source);
}

const packages = [];
const entryFiles = [];
for (const [id, source] of configured) {
	const info = describeSource(agentDir, id);
	info.source = source;
	if (info.present) {
		const entries = packageEntries(info.path);
		info.entries = entries;
		if (entries.length === 0) info.error = "no extension entry point";
		for (const entry of entries) entryFiles.push(entry);
	} else {
		info.error = "installed directory is missing";
	}
	packages.push(info);
}

const extensions = [];
for (const file of EXTENSION_FILES) {
	const full = path.join(agentDir, "extensions", file);
	if (fs.existsSync(full)) {
		extensions.push(full);
		entryFiles.push(full);
	}
}

const workDir = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "pi-bootstrap-verify."));
process.env.PI_OFFLINE = "1";
process.env.PI_SKIP_VERSION_CHECK = "1";
process.env.PI_CODING_AGENT_DIR = agentDir;

let loaded;
let loadError;
let skipped = false;
try {
	const loaderPath = path.join(pi.dir, "dist", "core", "extensions", "loader.js");
	if (!fs.existsSync(loaderPath)) {
		skipped = true;
		loadError = `Pi ${pi.version} at ${pi.dir} has no extension loader (${loaderPath})`;
		throw new Error(loadError);
	}
	const { loadExtensions, createExtensionRuntime } = await import(pathToFileURL(loaderPath).href);
	const runtime = createExtensionRuntime();
	for (const method of ["sendMessage", "sendUserMessage", "appendEntry", "setSessionName", "setLabel", "setActiveTools"]) {
		if (typeof runtime[method] === "function") runtime[method] = () => undefined;
	}
	runtime.getSessionName = () => "pi-bootstrap-verify";
	runtime.getSettings = () => ({});
	runtime.getActiveTools = runtime.getAllTools = () => [];
	loaded = await loadExtensions(entryFiles, workDir, undefined, runtime);
} catch (error) {
	loadError = error instanceof Error ? error.message : String(error);
} finally {
	fs.rmSync(workDir, { recursive: true, force: true });
}

const commands = loaded
	? [...new Set(loaded.extensions.flatMap((extension) => [...extension.commands].map(([name]) => name)))].sort()
	: [];
const permissionGate = loaded
	? loaded.extensions.some((extension) => extension.path.includes("permission-modes") && (extension.handlers.get("tool_call")?.length ?? 0) > 0)
	: false;

const payload = {
	ok: false,
	piVersion: pi.version,
	piDir: pi.dir,
	packages,
	extensions,
	extensionCount: loaded?.extensions.length ?? 0,
	errors: loaded?.errors ?? [],
	commands,
	permissionGate,
	loadError,
	skipped,
};

if (options.mode === "verify") {
	const problems = [];
	const expected = readJson(options.expectFrom);
	if (!expected) {
		problems.push(`cannot read the recorded pre-install state from ${options.expectFrom}`);
	} else {
		if (expected.skipped || expected.ok === false) {
			// The pre-run environment could not be inspected (for example a stub
			// `pi` in the test suite). A rollback can then only prove that what is
			// there now loads; it cannot compare command lists.
			payload.previousStateUnavailable = true;
		} else {
			if (expected.piVersion && expected.piVersion !== pi.version) {
				problems.push(`Pi is ${pi.version} after rollback, expected ${expected.piVersion}`);
			}
			for (const name of expected.commands ?? []) {
				if (!commands.includes(name)) problems.push(`command ${name} is not registered after rollback`);
			}
			for (const pkg of expected.packages ?? []) {
				const now = packages.find((info) => info.id === pkg.id);
				if (!now) {
					problems.push(`${pkg.id} was installed before the run and is not configured now`);
					continue;
				}
				if (now.version !== pkg.version) {
					problems.push(`${pkg.id} is ${now.version ?? "missing"} after rollback, expected ${pkg.version}`);
				}
			}
		}
	}
	if (loadError && !skipped) problems.push(`loader error: ${loadError}`);
	for (const error of loaded?.errors ?? []) problems.push(`${error.path}: ${error.error}`);
	for (const info of packages) if (info.error) problems.push(`${info.id}: ${info.error}`);
	if ((expected?.permissionGate ?? false) && !permissionGate) problems.push("permission-modes tool_call gate is not registered");
	payload.problems = problems;
	payload.ok = problems.length === 0;
} else {
	const problems = [];
	if (!loaded) problems.push(loadError ?? "extensions could not be loaded");
	for (const error of payload.errors) problems.push(`${error.path}: ${error.error}`);
	for (const info of packages) if (info.error) problems.push(`${info.id}: ${info.error}`);
	for (const name of options.requireCommands) {
		if (!commands.includes(name)) problems.push(`command ${name} is not registered`);
	}
	payload.requiredCommands = options.requireCommands;
	payload.problems = problems;
	payload.ok = problems.length === 0;
}

if (options.jsonOut) fs.writeFileSync(options.jsonOut, `${JSON.stringify(payload, null, 2)}\n`);

if (skipped) {
	// A stub `pi` (the installer's own test suite) or a Pi build without a
	// loader: nothing can be proven either way, so say so instead of guessing.
	console.log(`SKIP stack verification: ${loadError}`);
	process.exit(3);
}

const summary = `Pi ${pi.version}; ${payload.extensionCount} extension(s); ${commands.length} command(s)${
	packages.length ? `; packages ${packages.map((info) => `${info.id}@${info.version ?? "?"}`).join(", ")}` : ""
}`;
if (payload.ok) {
	console.log(`stack verification OK: ${summary}`);
	process.exit(0);
}
console.error(`stack verification FAILED: ${summary}`);
for (const problem of payload.problems ?? []) console.error(`  - ${problem}`);
for (const error of payload.errors ?? []) console.error(`  - ${error.path}: ${error.error}`);
if (loadError) console.error(`  - ${loadError}`);
for (const info of packages) if (info.error) console.error(`  - ${info.id}: ${info.error}`);
process.exit(1);
VERIFY_STACK_JS_BODY
}

# Run the real Pi launcher against the managed stack. Never loads unrelated
# user packages. Returns non-zero when the stack does not load.
verify_stack() {
	local mode="$1"
	shift
	node "$VERIFY_STACK_JS" --mode "$mode" --pi-bin "$PI_BIN" --agent-dir "$AGENT_DIR" "$@"
}

verify_installed_stack() {
	local status=0
	verify_stack capture --json-out "$STATE_DIR/stack.json" \
		--require-command mode --require-command permissions \
		--require-command classifier-model \
		--require-command btw --require-command advisor --require-command advisor-models || status=$?
	case "$status" in
		0) : ;;
		3)
			# Nothing could be proven: the resolved pi package has no extension
			# loader (only possible with a stub or a non-standard Pi build). A real
			# install must not pretend that is verified; the test suite opts in
			# explicitly, and its own acceptance test covers this branch.
			if [[ "${PI_BOOTSTRAP_ALLOW_UNVERIFIED:-0}" == "1" ]]; then
				warn "the installed stack could not be verified on this Pi build (PI_BOOTSTRAP_ALLOW_UNVERIFIED=1)"
			else
				fail "could not verify the installed stack: the pi package at ${GLOBAL_PI_PACKAGE:-unknown} has no extension loader"
			fi
			;;
		*) fail "the installed stack does not load on the installed Pi (see the errors above)" ;;
	esac
}

locate_current_pi() {
	PI_BIN="$(command -v pi 2>/dev/null || true)"
	if [[ -z "$PI_BIN" ]] && [[ -n "${GLOBAL_PI_BIN:-}" ]] && [[ -x "$GLOBAL_PI_BIN" ]]; then
		PI_BIN="$GLOBAL_PI_BIN"
	fi
}

# ---------------------------------------------------------------------------
# Backups / rollback
# ---------------------------------------------------------------------------
backup_record_file() {
	local target="$1" entry stored
	[[ -d "$BACKUP_DIR/files" ]] || mkdir -p "$BACKUP_DIR/files" || fail "could not create $BACKUP_DIR/files"
	[[ -f "$BACKUP_DIR/files.tsv" ]] || : >"$BACKUP_DIR/files.tsv" || fail "could not create $BACKUP_DIR/files.tsv"
	entry="$(wc -l <"$BACKUP_DIR/files.tsv" | tr -d ' ')"
	stored="$(printf '%03d-%s' "$((entry + 1))" "$(basename "$target")")"
	cp -p "$target" "$BACKUP_DIR/files/$stored" || fail "could not back up $target"
	printf '%s\t%s\n' "$target" "$stored" >>"$BACKUP_DIR/files.tsv" || fail "could not record the backup of $target"
}

# Remember the previous contents of a file so a failure can restore it, or so a
# newly created file can be removed. Recorded on disk immediately, which is what
# makes recovery work after SIGKILL as well as after a trap.
track_install_target() {
	local target="$1"
	if [[ ! -d "$BACKUP_DIR" ]]; then
		mkdir -p "$BACKUP_DIR" || fail "could not create $BACKUP_DIR"
	fi
	if [[ -f "$target" ]]; then
		backup_record_file "$target"
	else
		printf '%s\n' "$target" >>"$BACKUP_DIR/created.list" || fail "could not record $target as created"
	fi
}

snapshot_settings() {
	if [[ -f "$SETTINGS_FILE" ]]; then
		cp -p "$SETTINGS_FILE" "$BACKUP_DIR/settings.json" || fail "could not back up $SETTINGS_FILE"
		: >"$BACKUP_DIR/settings.existed"
	else
		: >"$BACKUP_DIR/settings.absent"
	fi
}

# Move each managed package tree aside and work on a copy. The moved tree is the
# authoritative backup, so restoring it cannot be corrupted by the run itself
# (including a run that `pi remove` partially destroyed).
snapshot_plugin_trees() {
	local tree src
	for tree in npm git; do
		src="$AGENT_DIR/$tree"
		if [[ -e "$src" ]]; then
			mkdir -p "$BACKUP_DIR/trees" || fail "could not create $BACKUP_DIR/trees"
			move_path "$src" "$BACKUP_DIR/trees/$tree" ||
				fail "could not move $src aside for rollback"
			cp -a "$BACKUP_DIR/trees/$tree" "$src" || fail "could not working-copy $src back into place"
		else
			printf '%s\n' "$src" >>"$BACKUP_DIR/created.list" || fail "could not record $src as created"
		fi
	done
}

# Capture what the current environment registers, so a rollback can prove the
# old commands are back rather than merely that files match bytes.
capture_pre_state() {
	local pre_state="$BACKUP_DIR/pre-state.json"
	if [[ -z "${PI_BIN:-}" ]]; then
		printf '{"skipped": true, "reason": "no Pi launcher was available before the upgrade"}\n' >"$pre_state"
		return 0
	fi
	verify_stack capture --json-out "$pre_state" >/dev/null 2>&1 || true
	[[ -f "$pre_state" ]] || printf '{"skipped": true, "reason": "pre-install stack capture failed"}\n' >"$pre_state"
}

begin_transaction() {
	if [[ -e "$BACKUP_DIR" ]]; then
		fail "a previous rollback is still pending at $BACKUP_DIR; resolve it before running the installer again (see the messages from the failed run)"
	fi
	mkdir -p "$BACKUP_DIR" || fail "could not create $BACKUP_DIR"
	# The journal is the only crash record, so a run that cannot write it must
	# not start: nothing has been mutated yet, so undo the empty backup dir.
	if ! journal_write active backup; then
		rmdir "$BACKUP_DIR" 2>/dev/null || true
		fail "could not record the transaction journal $JOURNAL; nothing was changed"
	fi
	MUTATION_STARTED=1
	capture_pre_state
	snapshot_settings
	snapshot_plugin_trees
	test_hook after-backup
	test_hook after-backup-slow
}

# Resolve where the global Pi package and bin entry are, preferring the values
# in the journal (see journal_write) and falling back to the npm global prefix
# for a journal that has none. A recovery run must never call npm for this.
global_cli_paths() {
	local root="${GLOBAL_NPM_ROOT:-}"
	if [[ -z "$root" && -n "${GLOBAL_NPM_PREFIX:-}" ]]; then
		root="$GLOBAL_NPM_PREFIX/lib/node_modules"
	fi
	GLOBAL_PI_PACKAGE="${GLOBAL_PI_PACKAGE:-${root:+$root/@earendil-works/pi-coding-agent}}"
	GLOBAL_PI_BIN="${GLOBAL_PI_BIN:-${GLOBAL_NPM_PREFIX:+$GLOBAL_NPM_PREFIX/bin/pi}}"
}

# Verify the environment that was just restored, through the npm global
# launcher that was restored (not whatever `pi` happens to be first on PATH).
# This is a local Node load of files already on disk. Returns 0 verified,
# 3 unprovable (stub Pi, no Node, no recorded pre-state), else a failure.
verify_restored_environment() {
	if [[ -n "${GLOBAL_PI_BIN:-}" && -x "$GLOBAL_PI_BIN" ]]; then
		PI_BIN="$GLOBAL_PI_BIN"
	fi
	[[ -n "$VERIFY_STACK_JS" && -f "$BACKUP_DIR/pre-state.json" && -n "${PI_BIN:-}" ]] || return 3
	command -v node >/dev/null 2>&1 || return 3
	verify_stack verify --expect "$BACKUP_DIR/pre-state.json" >&2
}

# Restore everything the journal and backup directory describe. Idempotent:
# every step checks what is actually present, so it is safe after a partial
# crash as well as after a trap.
restore_from_backup() {
	local original stored created old_target

	global_cli_paths

	# Files the run replaced, then files the run created.
	if [[ -f "$BACKUP_DIR/files.tsv" ]]; then
		while IFS=$'\t' read -r original stored; do
			[[ -n "$original" && -n "$stored" ]] || continue
			if [[ -f "$BACKUP_DIR/files/$stored" ]]; then
				mkdir -p "$(dirname "$original")" || true
				cp -p "$BACKUP_DIR/files/$stored" "$original" ||
					echo "pi-bootstrap: could not restore ${original} from ${BACKUP_DIR}/files/${stored}" >&2
			fi
		done <"$BACKUP_DIR/files.tsv"
	fi
	if [[ -f "$BACKUP_DIR/created.list" ]]; then
		while IFS= read -r created; do
			[[ -n "$created" ]] || continue
			case "$created" in
				"$AGENT_DIR/npm" | "$AGENT_DIR/git") continue ;; # handled as trees below
			esac
			rm -f "$created" || echo "pi-bootstrap: could not remove ${created}; it did not exist before this run" >&2
		done <"$BACKUP_DIR/created.list"
	fi

	# settings.json is what Pi loads; restoring it deactivates a partial matrix.
	if [[ -f "$BACKUP_DIR/settings.json" ]]; then
		cp -p "$BACKUP_DIR/settings.json" "$SETTINGS_FILE" &&
			echo "pi-bootstrap: restored $SETTINGS_FILE" >&2 ||
			echo "pi-bootstrap: could not restore $SETTINGS_FILE; copy it back from $BACKUP_DIR/settings.json" >&2
	elif [[ -f "$BACKUP_DIR/settings.absent" ]]; then
		rm -f "$SETTINGS_FILE"
	fi

	# Package trees: drop the working copy, move the untouched original back. A
	# tree the run created did not exist before and is removed entirely.
	for tree in npm git; do
		if [[ -d "$BACKUP_DIR/trees/$tree" ]]; then
			rm -rf "${AGENT_DIR:?}/$tree" || echo "pi-bootstrap: could not clear $AGENT_DIR/$tree" >&2
			move_path "$BACKUP_DIR/trees/$tree" "$AGENT_DIR/$tree" ||
				echo "pi-bootstrap: could not restore $AGENT_DIR/$tree from $BACKUP_DIR/trees/$tree" >&2
		elif [[ -f "$BACKUP_DIR/created.list" ]] && grep -Fxq "$AGENT_DIR/$tree" "$BACKUP_DIR/created.list"; then
			rm -rf "${AGENT_DIR:?}/$tree" || echo "pi-bootstrap: could not remove $AGENT_DIR/$tree; it did not exist before this run" >&2
		fi
	done

	# Global Pi CLI: put the previous package back, or remove one this run created.
	if [[ -f "$BACKUP_DIR/cli/package.created" ]]; then
		if [[ -n "${GLOBAL_PI_PACKAGE:-}" ]]; then
			rm -rf "$GLOBAL_PI_PACKAGE" ||
				echo "pi-bootstrap: could not remove $GLOBAL_PI_PACKAGE; it did not exist before this run" >&2
		else
			echo "pi-bootstrap: cannot tell where the Pi package this run created was installed" >&2
		fi
	fi
	if [[ -f "$BACKUP_DIR/cli/package.existed" ]] && [[ -d "$BACKUP_DIR/cli/package" ]]; then
		if [[ -n "${GLOBAL_PI_PACKAGE:-}" ]]; then
			rm -rf "$GLOBAL_PI_PACKAGE" || true
			mkdir -p "$(dirname "$GLOBAL_PI_PACKAGE")" || true
			move_path "$BACKUP_DIR/cli/package" "$GLOBAL_PI_PACKAGE" ||
				echo "pi-bootstrap: could not restore the previous Pi package to $GLOBAL_PI_PACKAGE" >&2
		else
			echo "pi-bootstrap: cannot tell where the previous Pi package belongs; it is kept at $BACKUP_DIR/cli/package" >&2
		fi
	fi
	# The bin entry: remove it when the run created it, otherwise put back the
	# exact link target or the exact plain file.
	if [[ -f "$BACKUP_DIR/cli/bin.created" ]] || [[ -f "$BACKUP_DIR/cli/bin.existed" ]]; then
		local bin_path="${GLOBAL_PI_BIN:-}"
		if [[ -n "$bin_path" ]]; then
			if [[ -f "$BACKUP_DIR/cli/bin.created" ]]; then
				rm -f "$bin_path" ||
					echo "pi-bootstrap: could not remove $bin_path; it did not exist before this run" >&2
			else
				mkdir -p "$(dirname "$bin_path")" || true
				if [[ -f "$BACKUP_DIR/cli/bin-file" ]]; then
					# Remove first: the failed run may have replaced the file with
					# a symlink, and `cp` would write through a dangling link.
					rm -f "$bin_path" || true
					cp -p "$BACKUP_DIR/cli/bin-file" "$bin_path" ||
						echo "pi-bootstrap: could not restore $bin_path" >&2
				else
					old_target="$(cat "$BACKUP_DIR/cli/bin-target" 2>/dev/null || true)"
					[[ -z "$old_target" ]] || ln -sfn "$old_target" "$bin_path" ||
						echo "pi-bootstrap: could not restore the pi bin link" >&2
				fi
			fi
		fi
	fi
}

discard_backup() {
	rm -rf "$BACKUP_DIR" || true
	rm -f "$JOURNAL" || true
}

# Rollback for the in-process failure path. Never exits, so the original status
# is preserved. Verifies the restored environment with the real Pi loader and
# says so explicitly when it cannot.
recover() {
	((MUTATION_STARTED)) || return 0
	((RECOVERY_ACTIVE)) && return 0
	RECOVERY_ACTIVE=1
	MUTATION_STARTED=0
	set +e
	echo "pi-bootstrap: rolling back to the previous state..." >&2
	restore_from_backup

	# 0 = restored and proven to load, 3 = restored but unprovable (no real
	# loader / stub pi), anything else = restored but verification failed.
	local verify_status=0
	verify_restored_environment || verify_status=$?
	case "$verify_status" in
		0)
			echo "pi-bootstrap: previous environment restored and verified: Pi and the managed extensions load, and the commands the previous installation registered are back." >&2
			discard_backup
			;;
		3)
			echo "pi-bootstrap: files restored, but this environment cannot be verified automatically (no real Pi launcher/loader was available). Backups were removed because the previous files are back in place." >&2
			discard_backup
			;;
		*)
			echo "pi-bootstrap: rollback restored the files, but the previous environment FAILED verification. Do not start Pi until this is resolved." >&2
			echo "pi-bootstrap: backups are kept at $BACKUP_DIR; the next installer run will refuse to start until they are resolved." >&2
			;;
	esac
	echo "pi-bootstrap: fix the reported problem and re-run install.sh." >&2
	return 0
}

# Recover from a run that was killed without running any trap (SIGKILL, power
# loss). Runs before anything in a new install touches the filesystem.
recover_interrupted_run() {
	local status=""
	[[ -f "$JOURNAL" ]] || return 0
	status="$(sed -n 's/^status=//p' "$JOURNAL" | head -n 1)"
	# shellcheck disable=SC1090
	. "$JOURNAL" 2>/dev/null || true
	# Journals written before R4 stored the global paths under lowercase names.
	GLOBAL_PI_PACKAGE="${GLOBAL_PI_PACKAGE:-${global_package:-}}"
	GLOBAL_PI_BIN="${GLOBAL_PI_BIN:-${global_bin:-}}"
	if [[ "$status" == "committed" ]]; then
		echo "pi-bootstrap: cleaning up a previous run that committed but did not finish"
		discard_backup
		return 0
	fi
	echo "pi-bootstrap: a previous run was interrupted during '${phase:-unknown}' and left backups in $BACKUP_DIR" >&2
	echo "pi-bootstrap: rolling back to the previous state before continuing..." >&2
	restore_from_backup
	# Verify through the npm global launcher that was just restored, not through
	# whatever `pi` happens to be first on PATH. Verification is a local Node
	# load of the restored files; it is not a prerequisite for restoring them,
	# so without Node or a recorded pre-state the restore is reported unproven.
	local verify_status=3
	verify_restored_environment || verify_status=$?
	case "$verify_status" in
		0)
			discard_backup
			echo "pi-bootstrap: previous environment restored and verified" >&2
			;;
		3)
			discard_backup
			echo "pi-bootstrap: previous files restored; automatic verification was not possible here" >&2
			;;
		*)
			fail "could not verify the environment restored after the interrupted run; backups are kept at $BACKUP_DIR"
			;;
	esac
}

commit_transaction() {
	# The "committed" journal record must be durable before the backups are
	# removed. If it cannot be written, the run is not committed: fail() leaves
	# MUTATION_STARTED set, so the EXIT trap rolls the new environment back
	# instead of leaving backups that the next run would roll back anyway.
	journal_write committed complete ||
		fail "could not record the commit in $JOURNAL; rolling back instead of leaving a pending transaction"
	RUN_COMMITTED=1
	discard_backup
	MUTATION_STARTED=0
}

install_classifier_extension() {
	local local_source="${PI_BOOTSTRAP_SOURCE_DIR:-}"
	if [[ -z "$local_source" && -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
		local_source="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	fi

	track_install_target "$EXTENSIONS_DIR/classifier-model.ts"
	if [[ -n "$local_source" && -f "$local_source/extensions/classifier-model.ts" ]]; then
		install -m 0644 "$local_source/extensions/classifier-model.ts" "$EXTENSIONS_DIR/classifier-model.ts" ||
			fail "could not install classifier-model.ts"
		return
	fi

	# Keep curl | bash self-contained. Local checkouts use the repository source file.
	cat >"$EXTENSIONS_DIR/classifier-model.ts" <<'CLASSIFIER_MODEL_EXTENSION'
import { mkdirSync, readFileSync, realpathSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type JsonObject = Record<string, unknown>;

const DEFAULT_TIMEOUT_MS = 60_000;
const DISABLE_LABEL = "Disable classifier";

// Pi resolves its agent directory from PI_CODING_AGENT_DIR (see
// getAgentDir() in @earendil-works/pi-coding-agent). The classifier selection
// must be written to the same directory Pi and its packages use, otherwise
// `/classifier-model` appears to work while permission-modes keeps reading a
// different file. PI_AGENT_DIR is this repository's installer-only override
// and is deliberately not consulted here: Pi itself ignores it, so honoring
// it would reintroduce the mismatch. The installer translates PI_AGENT_DIR to
// PI_CODING_AGENT_DIR for the `pi` process it drives.
export function resolveAgentDir(): string {
	const configured = process.env.PI_CODING_AGENT_DIR?.trim();
	if (!configured) return join(homedir(), ".pi", "agent");
	if (configured === "~") return homedir();
	if (configured.startsWith("~/")) return join(homedir(), configured.slice(2));
	return resolve(configured);
}

export function resolveConfigPath(): string {
	return join(requireSupportedAgentDir(), "permission-modes.json");
}

// permission-modes 2.8.0 reads `join(homedir(), ".pi", "agent",
// "permission-modes.json")` and exposes no way to redirect it: the pinned
// source (config.ts) sets the path at module load and only its test helper
// `setGlobalConfigPathForTests` can change it. So with a custom
// PI_CODING_AGENT_DIR the gate and Pi would use two different files.
//
// The selection is deliberately NOT mirrored to the upstream path: a test or a
// throwaway Pi instance with PI_CODING_AGENT_DIR set would then rewrite the
// real user's `~/.pi/agent/permission-modes.json`, which is exactly the
// cross-directory write this command must never perform. Instead the command
// fails closed and says why, so nobody believes a selection was saved while
// the gate keeps reading another file.
function requireSupportedAgentDir(): string {
	const agentDir = physicalPath(resolve(resolveAgentDir()));
	const upstreamDir = physicalPath(resolve(join(homedir(), ".pi", "agent")));
	if (agentDir === upstreamDir) return agentDir;
	const upstreamConfig = join(upstreamDir, "permission-modes.json");
	throw new Error(
		`/classifier-model cannot save a selection here: Pi is using ${agentDir}, but permission-modes 2.8.0 always reads ${upstreamConfig} and cannot be redirected. ` +
			`Writing that file anyway would change a directory this Pi does not own, so nothing was written. ` +
			`Run Pi with the default agent directory (unset PI_CODING_AGENT_DIR), or set the classifier block in ${upstreamConfig} yourself.`,
	);
}

// Resolve symlinks for the part of the path that exists and keep the rest
// lexical, so `~/x`, `x/`, a relative spelling and a symlink to the default
// directory all compare equal - the same rule install.sh applies, so the
// installer and this command never disagree about which directories are
// supported.
function physicalPath(target: string): string {
	let base = target;
	const rest: string[] = [];
	for (;;) {
		try {
			return join(realpathSync(base), ...rest);
		} catch {
			const parent = dirname(base);
			if (parent === base) return target;
			rest.unshift(basename(base));
			base = parent;
		}
	}
}

function readConfig(configPath: string): JsonObject {
	let text: string;
	try {
		text = readFileSync(configPath, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
		throw new Error(`Could not read ${configPath}: ${String(error)}`);
	}

	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch (error) {
		throw new Error(`Could not parse ${configPath}: ${error instanceof Error ? error.message : String(error)}`);
	}

	if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
		throw new Error(`Could not parse ${configPath}: the JSON root must be an object`);
	}
	return parsed as JsonObject;
}

function writeConfig(configPath: string, config: JsonObject): void {
	const directory = dirname(configPath);
	mkdirSync(directory, { recursive: true });

	let mode: number | undefined;
	try {
		mode = statSync(configPath).mode;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}

	const temporaryPath = `${configPath}.tmp-${process.pid}-${Date.now()}`;
	try {
		writeFileSync(temporaryPath, `${JSON.stringify(config, null, 2)}\n`, {
			encoding: "utf8",
			mode: mode ?? 0o600,
		});
		renameSync(temporaryPath, configPath);
	} catch (error) {
		try {
			// Best effort cleanup. The original file is left untouched on failure.
			unlinkSync(temporaryPath);
		} catch {
			// Ignore cleanup errors and report the original write failure.
		}
		throw new Error(`Could not write ${configPath}: ${String(error)}`);
	}
}

function classifierConfig(config: JsonObject): JsonObject {
	const value = config.classifier;
	return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as JsonObject) : {};
}

function modelName(model: { provider: string; id: string }): string {
	return `${model.provider}/${model.id}`;
}

export default function classifierModelExtension(pi: ExtensionAPI) {
	pi.registerCommand("classifier-model", {
		description: "Choose the permission-modes classifier model",
		handler: async (_args, ctx) => {
			if (!ctx.hasUI) {
				ctx.ui.notify("Classifier model selection requires interactive UI.", "error");
				return;
			}

			// Resolved per invocation so a changed PI_CODING_AGENT_DIR (or a
			// reload in a new environment) always targets Pi's current directory.
			// An unsupported directory is refused before the picker is shown:
			// the user must not spend a selection on a write that cannot reach
			// the file permission-modes reads.
			let configPath: string;
			try {
				configPath = resolveConfigPath();
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			let config: JsonObject;
			try {
				config = readConfig(configPath);
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			try {
				await ctx.modelRegistry.refresh();
			} catch (error) {
				ctx.ui.notify(
					`Could not refresh model registry; showing cached models. ${error instanceof Error ? error.message : String(error)}`,
					"warning",
				);
			}

			const models = ctx.modelRegistry
				.getAvailable()
				.filter((model) => model.provider && model.id)
				.sort((a, b) => modelName(a).localeCompare(modelName(b)));
			if (models.length === 0) {
				ctx.ui.notify("No available models. Configure a provider/model in Pi first.", "error");
				return;
			}

			const current = classifierConfig(config);
			const currentModel = typeof current.model === "string" ? current.model : undefined;
			const labels = models.map((model) => {
				const id = modelName(model);
				return id === currentModel ? `✓ ${id}` : id;
			});
			const title = currentModel ? `Choose classifier model\nCurrent: ${currentModel}` : "Choose classifier model";
			const selected = await ctx.ui.select(title, [...labels, DISABLE_LABEL]);
			if (!selected) return;

			const selectedIndex = labels.indexOf(selected);
			const nextClassifier: JsonObject = { ...current };
			if (!("timeoutMs" in nextClassifier)) nextClassifier.timeoutMs = DEFAULT_TIMEOUT_MS;

			if (selected === DISABLE_LABEL) {
				nextClassifier.enabled = false;
			} else if (selectedIndex >= 0) {
				nextClassifier.enabled = true;
				nextClassifier.model = modelName(models[selectedIndex]);
			} else {
				ctx.ui.notify("Unknown classifier selection.", "error");
				return;
			}

			try {
				writeConfig(configPath, { ...config, classifier: nextClassifier });
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			try {
				ctx.ui.notify(`Classifier ${nextClassifier.enabled === false ? "disabled" : "updated"}.`, "info");
				await ctx.reload();
				return;
			} catch (error) {
				ctx.ui.notify(
					`Classifier configuration saved, but Pi could not reload it. Run /reload. ${error instanceof Error ? error.message : String(error)}`,
					"warning",
				);
			}
		},
	});
}
CLASSIFIER_MODEL_EXTENSION
}

install_minimal_mode() {
	local minimal_tmp minimal_hash
	echo "Installing minimal-mode.ts from Pi v${PI_VERSION}..."
	minimal_tmp="$(mktemp)"
	tmp_files+=("$minimal_tmp")
	curl -fsSL "$MINIMAL_MODE_URL" -o "$minimal_tmp" || fail "could not download $MINIMAL_MODE_URL"
	minimal_hash="$(hash_file "$minimal_tmp")"
	if [[ "$minimal_hash" != "$MINIMAL_MODE_SHA256" ]]; then
		fail "minimal-mode.ts from tag v${PI_VERSION} does not match pinned checksum ${MINIMAL_MODE_SHA256}"
	fi
	track_install_target "$EXTENSIONS_DIR/minimal-mode.ts"
	install -m 0644 "$minimal_tmp" "$EXTENSIONS_DIR/minimal-mode.ts" || fail "could not install minimal-mode.ts"
}

merge_keybindings() {
	node - "$KEYBINDINGS_FILE" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const file = process.argv[2];
const directory = path.dirname(file);
fs.mkdirSync(directory, { recursive: true });

let config = {};
let mode;
try {
  mode = fs.statSync(file).mode;
  config = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (error) {
  if (error && error.code !== "ENOENT") {
    console.error(`Could not parse ${file}: ${error.message}`);
    process.exit(1);
  }
}
if (config === null || typeof config !== "object" || Array.isArray(config)) {
  console.error(`Could not parse ${file}: the JSON root must be an object`);
  process.exit(1);
}

config["app.thinking.cycle"] = "ctrl+shift+tab";
const temporary = `${file}.tmp-${process.pid}-${Date.now()}`;
try {
  fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`, { encoding: "utf8", mode: mode ?? 0o600 });
  fs.renameSync(temporary, file);
} catch (error) {
  try { fs.unlinkSync(temporary); } catch {}
  console.error(`Could not write ${file}: ${error.message}`);
  process.exit(1);
}
NODE
}

remove_bootstrap_tmux_settings() {
	local file="$1"
	local cleaned
	cleaned="$(mktemp "${file}.tmp.XXXXXX")"
	tmp_files+=("$cleaned")
	awk '
		$0 == "# >>> pi-bootstrap >>>" { skip = 1; next }
		$0 == "# <<< pi-bootstrap <<<" { skip = 0; next }
		$0 == "set -g extended-keys on" { next } # Exact line added by the v1 installer.
		!skip { print }
	' "$file" >"$cleaned"
	chmod --reference="$file" "$cleaned" 2>/dev/null || true
	mv "$cleaned" "$file"
}

configure_tmux() {
	local version strategy
	version="$(tmux -V 2>/dev/null || true)"
	strategy="$(tmux_strategy_for_version "$version")"

	case "$strategy" in
		unknown)
			warn "could not parse tmux version (${version:-unknown}); no tmux settings were changed."
			return 0
			;;
	esac

	# Every remaining branch may rewrite the file; remember it first so a later
	# failure (including a failure in this function) restores the user's config.
	track_install_target "$TMUX_CONFIG"

	case "$strategy" in
		unsupported)
			if [[ -f "$TMUX_CONFIG" ]]; then
				remove_bootstrap_tmux_settings "$TMUX_CONFIG"
			fi
			warn "Pi modified-key support requires tmux >= 3.2. Upgrade tmux or run Pi outside tmux for modified Enter shortcuts."
			return 0
			;;
	esac

	mkdir -p "$(dirname "$TMUX_CONFIG")"
	touch "$TMUX_CONFIG"
	remove_bootstrap_tmux_settings "$TMUX_CONFIG"
	if [[ -s "$TMUX_CONFIG" && -n "$(tail -n 1 "$TMUX_CONFIG")" ]]; then
		printf '\n' >>"$TMUX_CONFIG"
	fi
	{
		printf '# >>> pi-bootstrap >>>\n'
		printf 'set -g extended-keys on\n'
		if [[ "$strategy" == "csi-u" ]]; then
			printf 'set -g extended-keys-format csi-u\n'
		fi
		printf '# <<< pi-bootstrap <<<\n'
	} >>"$TMUX_CONFIG"

	case "$strategy" in
		csi-u)
			echo "tmux ${version#tmux } detected: extended-keys = on; extended-keys-format = csi-u"
			;;
		extended)
			echo "tmux ${version#tmux } detected: extended-keys = on"
			;;
	esac

	if [[ -n "${TMUX:-}" ]]; then
		if ! tmux source-file "$TMUX_CONFIG"; then
			warn "could not reload tmux configuration; run tmux source-file $TMUX_CONFIG or restart the tmux server."
		fi
	fi
	echo "tmux configuration updated."
	echo "For modified-key changes to be guaranteed active, restart the tmux server after saving your sessions."
}

# Compare two paths the way the kernel would, resolving symlinks in the part
# that exists and keeping the rest lexical, so `~/x`, `x/`, a relative path and
# a symlink to the same directory all compare equal (and a symlink pointing
# somewhere else does not).
same_directory() {
	node -e '
		const path = require("node:path");
		const fs = require("node:fs");
		const real = (p) => {
			let base = path.resolve(p);
			const rest = [];
			while (!fs.existsSync(base)) {
				const parent = path.dirname(base);
				if (parent === base) break;
				rest.unshift(path.basename(base));
				base = parent;
			}
			try { base = fs.realpathSync(base); } catch {}
			return path.join(base, ...rest);
		};
		process.exit(real(process.argv[1]) === real(process.argv[2]) ? 0 : 1);
	' "$1" "$2"
}

# permission-modes 2.8.0 resolves *every* user file from homedir() -
# permission-modes.json (config.ts), model-profiles.json and settings.json
# (profiles.ts), the subagent forwarding root (permission-forwarding.ts) - and
# never reads PI_CODING_AGENT_DIR. Its only setter, setConfigPath(), is not
# exported from index.ts, and Pi loads each extension with `moduleCache: false`
# (loader.js), so another extension's import of config.ts is a *separate*
# module instance: setting the path there does not change what the gate reads.
# There is therefore no way to make the gate follow Pi's agent directory
# without patching the pinned upstream source.
#
# The installer refuses to build a configuration where Pi uses directory A while
# the gate reads directory B. Failing closed before any mutation is the only
# honest option: the alternative is an install that looks protected and is not.
require_supported_agent_dir() {
	same_directory "$AGENT_DIR" "$HOME/.pi/agent" && return 0
	fail "$AGENT_DIR is UNSUPPORTED: Pi would run with this agent directory, but permission-modes ${PERMISSION_MODES_VERSION} always reads $HOME/.pi/agent (permission-modes.json, model-profiles.json, settings.json) and cannot be redirected. Installing here would leave the permission gate reading a different configuration than Pi, so nothing was changed. Run the installer with the default agent directory (unset PI_AGENT_DIR and PI_CODING_AGENT_DIR)."
}

preflight() {
	require_command node
	require_command npm
	require_command git
	require_node_version
	[[ -n "${HOME:-}" ]] || fail "HOME is not set"
	require_supported_agent_dir
	mkdir -p "$AGENT_DIR" "$EXTENSIONS_DIR" "$STATE_DIR" || fail "could not create $AGENT_DIR"
	[[ -w "$STATE_DIR" ]] || fail "$STATE_DIR is not writable"
	check_settings plan >/dev/null
	resolve_global_paths
	require_writable_global_prefix
}

main() {
	# Installed here rather than at file scope so that a test which sources this
	# file keeps its own EXIT trap, and a subshell running main() cleans up its
	# own temporary directories. One EXIT trap owns rollback: it fires for
	# explicit failures, errexit exits from nested functions, and signals.
	RUN_PID="$BASHPID"
	MUTATION_STARTED=0
	RUN_COMMITTED=0
	RECOVERY_ACTIVE=0
	FAIL_REPORTED=0

	PI_BIN="${PI_BIN:-}"
	trap on_exit EXIT
	trap 'on_signal INT 2' INT
	trap 'on_signal TERM 15' TERM
	trap 'on_signal HUP 1' HUP

	# Interrupted-run recovery is local-first (H2): the journal and the moved
	# backups on this machine are the only inputs. It therefore runs before
	# preflight, before the settings check (a previous run may have left
	# settings.json half-written), before the Git fetch, and before any npm
	# work, so an unreachable network or a corrupt settings file cannot keep a
	# crashed upgrade from being rolled back. The verifier is embedded in this
	# script, so materialising it needs no network either.
	materialize_verify_stack
	recover_interrupted_run
	if [[ "${PI_BOOTSTRAP_RECOVER_ONLY:-0}" == 1 ]]; then
		echo "pi-bootstrap: recovery-only run complete" >&2
		exit 0
	fi

	preflight

	# Verify the pinned source before anything from it can execute.
	prepare_permission_modes_snapshot

	locate_current_pi
	if [[ -n "$PI_BIN" ]]; then
		export PI_CODING_AGENT_DIR="$AGENT_DIR"
	fi

	begin_transaction

	install_pi_cli_staged
	export PI_CODING_AGENT_DIR="$AGENT_DIR"

	migrate_managed_packages
	install_managed_packages
	# Exercise rollback from a failure that a non-errtrace ERR trap would miss.
	test_hook nested
	test_hook pipeline
	test_hook subshell
	check_settings verify >/dev/null
	verify_permission_modes "$PERMISSION_MODES_DIR"
	test_hook after-verify

	install_classifier_extension
	install_minimal_mode
	# Exact versions only after everything is in place; a missing or unexpected
	# version is a failed install, not a warning.
	verify_installed_versions
	test_hook after-extensions

	echo "Merging Pi keybindings..."
	track_install_target "$KEYBINDINGS_FILE"
	merge_keybindings || fail "could not merge $KEYBINDINGS_FILE"
	test_hook after-keybindings

	if command -v tmux >/dev/null 2>&1; then
		configure_tmux
	fi
	test_hook after-tmux

	# Final proof on the real loader: Pi launches, every managed package loads,
	# and the commands the stack promises are registered.
	verify_installed_stack
	test_hook after-config

	commit_transaction
	test_hook after-commit

	cat <<EOF

Pi bootstrap installed and verified.

Pinned stack:
  Pi:                ${PI_VERSION} (npm)
  permission-modes:  ${PERMISSION_MODES_VERSION} (source snapshot ${PERMISSION_MODES_COMMIT:0:12}, SHA256-verified; not an npm release)
  pi-btw:            ${PI_BTW_VERSION} (npm)
  pi-advisor-flow:   ${PI_ADVISOR_FLOW_VERSION} (npm)
  minimal-mode.ts:   Pi v${PI_VERSION} tag (SHA256-verified)

Next steps:

1. Configure your providers/models in Pi.
2. Start Pi:
     pi
3. Select the permission classifier:
     /classifier-model
4. Configure Advisor:
     /advisor-models
5. Select a permission mode:
     /mode
EOF
}

if [[ "${PI_BOOTSTRAP_TEST_ONLY:-0}" != 1 ]]; then
	main "$@"
fi
