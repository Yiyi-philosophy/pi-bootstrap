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

SETTINGS_SNAPSHOT=""
SETTINGS_EXISTED=0
MUTATION_STARTED=0
RECOVERY_ACTIVE=0
BACKED_UP_FILES=()
CREATED_FILES=()

# Restore the pre-run activation state. settings.json is what Pi loads, so
# restoring it deactivates any partially installed version matrix.
recover() {
	((MUTATION_STARTED)) || return 0
	((RECOVERY_ACTIVE)) && return 0
	RECOVERY_ACTIVE=1
	set +e
	echo "pi-bootstrap: rolling back to the previous state..." >&2
	if ((SETTINGS_EXISTED)); then
		if cp -p "$SETTINGS_SNAPSHOT" "$SETTINGS_FILE"; then
			echo "pi-bootstrap: restored $SETTINGS_FILE from $SETTINGS_SNAPSHOT" >&2
		else
			echo "pi-bootstrap: could not restore $SETTINGS_FILE; copy it back manually from $SETTINGS_SNAPSHOT" >&2
		fi
	else
		rm -f "$SETTINGS_FILE"
		echo "pi-bootstrap: removed $SETTINGS_FILE (it did not exist before this run)" >&2
	fi
	# Guarded expansions keep `set -u` happy on bash < 4.4, where an empty
	# array under "${a[@]}" is an unbound-variable error.
	for entry in ${BACKED_UP_FILES[@]+"${BACKED_UP_FILES[@]}"}; do
		cp -p "${entry#*|}" "${entry%%|*}" ||
			echo "pi-bootstrap: could not restore ${entry%%|*} from ${entry#*|}" >&2
	done
	for entry in ${CREATED_FILES[@]+"${CREATED_FILES[@]}"}; do
		rm -f "$entry"
	done
	echo "pi-bootstrap: package files may remain under $AGENT_DIR; Pi only loads packages listed in settings.json, so nothing partial is active." >&2
	echo "pi-bootstrap: fix the reported problem and re-run install.sh." >&2
}

fail() {
	echo "pi-bootstrap: error: $*" >&2
	recover
	exit 1
}

warn() {
	echo "pi-bootstrap: warning: $*" >&2
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
migrate_managed_packages() {
	local value
	read_settings_plan plan || fail "could not inspect $SETTINGS_FILE"
	report_conflicts

	for value in ${PLAN_FINDINGS[@]+"${PLAN_FINDINGS[@]}"}; do
		echo "Removing stale package entry: ${value}"
		if ! "$PI_BIN" remove "$value"; then
			fail "pi remove failed for ${value}; $SETTINGS_FILE may be unchanged, but Pi may already have deleted the package files"
		fi
	done

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

	echo "Installing default Pi extensions..."
	"$PI_BIN" install "$PI_BTW_SOURCE" || fail "could not install $PI_BTW_SOURCE"
	"$PI_BIN" install "$PI_ADVISOR_FLOW_SOURCE" || fail "could not install $PI_ADVISOR_FLOW_SOURCE"

	echo "Installing permission-modes ${PERMISSION_MODES_VERSION} from pinned upstream commit ${PERMISSION_MODES_COMMIT:0:12}..."
	echo "(source built from the pinned commit, not an official npm release; SHA256-verified)"
	"$PI_BIN" install "$PERMISSION_MODES_SOURCE" || fail "could not install $PERMISSION_MODES_SOURCE"
}

locate_pi_bin() {
	if [[ -n "${PI_BIN:-}" && -x "${PI_BIN:-}" ]]; then
		export PI_CODING_AGENT_DIR="$AGENT_DIR"
		return 0
	fi
	PI_BIN="$(command -v pi || true)"
	if [[ -z "$PI_BIN" ]]; then
		local global_bin
		global_bin="$(npm prefix -g)/bin"
		if [[ -x "$global_bin/pi" ]]; then
			PI_BIN="$global_bin/pi"
		else
			fail "Pi was installed but the pi command could not be found"
		fi
	fi
	# Keep `pi install` writing to the same agent directory the checks read.
	export PI_CODING_AGENT_DIR="$AGENT_DIR"
}

snapshot_settings() {
	mkdir -p "$STATE_DIR" || fail "could not create $STATE_DIR"
	SETTINGS_SNAPSHOT="$STATE_DIR/settings.json.snapshot"
	if [[ -f "$SETTINGS_FILE" ]]; then
		cp -p "$SETTINGS_FILE" "$SETTINGS_SNAPSHOT" || fail "could not back up $SETTINGS_FILE"
		SETTINGS_EXISTED=1
	else
		rm -f "$SETTINGS_SNAPSHOT"
		SETTINGS_EXISTED=0
	fi
}

# Remember the previous contents of an installed file so a failure can restore
# it, or so a newly created file can be removed.
track_install_target() {
	local target="$1" backup
	if [[ -f "$target" ]]; then
		backup="$STATE_DIR/backup/$(basename "$target")"
		mkdir -p "$STATE_DIR/backup" || fail "could not create $STATE_DIR/backup"
		cp -p "$target" "$backup" || fail "could not back up $target"
		BACKED_UP_FILES+=("$target|$backup")
	else
		CREATED_FILES+=("$target")
	fi
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
import { mkdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type JsonObject = Record<string, unknown>;

const CONFIG_PATH = join(homedir(), ".pi", "agent", "permission-modes.json");
const DEFAULT_TIMEOUT_MS = 60_000;
const DISABLE_LABEL = "Disable classifier";

function readConfig(): JsonObject {
	let text: string;
	try {
		text = readFileSync(CONFIG_PATH, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
		throw new Error(`Could not read ${CONFIG_PATH}: ${String(error)}`);
	}

	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch (error) {
		throw new Error(`Could not parse ${CONFIG_PATH}: ${error instanceof Error ? error.message : String(error)}`);
	}

	if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
		throw new Error(`Could not parse ${CONFIG_PATH}: the JSON root must be an object`);
	}
	return parsed as JsonObject;
}

function writeConfig(config: JsonObject): void {
	const directory = dirname(CONFIG_PATH);
	mkdirSync(directory, { recursive: true });

	let mode: number | undefined;
	try {
		mode = statSync(CONFIG_PATH).mode;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}

	const temporaryPath = `${CONFIG_PATH}.tmp-${process.pid}-${Date.now()}`;
	try {
		writeFileSync(temporaryPath, `${JSON.stringify(config, null, 2)}\n`, {
			encoding: "utf8",
			mode: mode ?? 0o600,
		});
		renameSync(temporaryPath, CONFIG_PATH);
	} catch (error) {
		try {
			// Best effort cleanup. The original file is left untouched on failure.
			unlinkSync(temporaryPath);
		} catch {
			// Ignore cleanup errors and report the original write failure.
		}
		throw new Error(`Could not write ${CONFIG_PATH}: ${String(error)}`);
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

			let config: JsonObject;
			try {
				config = readConfig();
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
				writeConfig({ ...config, classifier: nextClassifier });
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
		unsupported)
			if [[ -f "$TMUX_CONFIG" ]]; then
				remove_bootstrap_tmux_settings "$TMUX_CONFIG"
			fi
			warn "Pi modified-key support requires tmux >= 3.2. Upgrade tmux or run Pi outside tmux for modified Enter shortcuts."
			return 0
			;;
		unknown)
			warn "could not parse tmux version (${version:-unknown}); no tmux settings were changed."
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

preflight() {
	require_command node
	require_command npm
	require_command curl
	require_command git
	require_node_version
	[[ -n "${HOME:-}" ]] || fail "HOME is not set"
	mkdir -p "$EXTENSIONS_DIR" || fail "could not create $EXTENSIONS_DIR"
	check_settings plan >/dev/null
}

main() {
	# Installed here rather than at file scope so that a test which sources this
	# file keeps its own EXIT trap, and a subshell running main() cleans up its
	# own temporary directories.
	trap cleanup EXIT
	trap 'fail "unexpected failure (exit $?)"' ERR
	preflight

	# Verify the pinned source before anything from it can execute.
	prepare_permission_modes_snapshot

	snapshot_settings
	MUTATION_STARTED=1

	echo "Installing Pi Coding Agent ${PI_VERSION}..."
	npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" ||
		fail "npm could not install Pi ${PI_VERSION}"
	locate_pi_bin

	migrate_managed_packages
	install_managed_packages
	check_settings verify >/dev/null
	verify_permission_modes "$PERMISSION_MODES_DIR"

	install_classifier_extension
	install_minimal_mode

	echo "Merging Pi keybindings..."
	merge_keybindings || fail "could not merge $KEYBINDINGS_FILE"

	if command -v tmux >/dev/null 2>&1; then
		configure_tmux
	fi

	MUTATION_STARTED=0
	cat <<EOF

Pi bootstrap installed.

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
