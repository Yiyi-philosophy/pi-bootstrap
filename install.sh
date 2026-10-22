#!/usr/bin/env bash
set -euo pipefail

# Tested version matrix. Keep this file self-contained for curl | bash installs.
# permission-modes is installed from an immutable upstream commit because the
# 2.8.0 source snapshot is not published on npm. It is a source-built pin, not
# an official npm release, and is verified against the manifest below.
PI_VERSION="1.4.0"
PI_BTW_VERSION="0.62.0"
PI_ADVISOR_FLOW_VERSION="0.14.2"
PERMISSION_MODES_COMMIT="cf77816f28e102409dddbf8e537e4cf57aa092f0"
PERMISSION_MODES_VERSION="2.8.0"
PERMISSION_MODES_SOURCE="git:github.com/GeorgeDong32/pi-permission-modes@${PERMISSION_MODES_COMMIT}"
MINIMAL_MODE_URL="https://raw.githubusercontent.com/earendil-works/pi/v${PI_VERSION}/packages/coding-agent/examples/extensions/minimal-mode.ts"
MINIMAL_MODE_SHA256="040cbc7619b2e903888c8626e2fa55ca5e3f820535dfd1aadcb2060e156a8770"

AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
EXTENSIONS_DIR="$AGENT_DIR/extensions"
KEYBINDINGS_FILE="$AGENT_DIR/keybindings.json"
SETTINGS_FILE="$AGENT_DIR/settings.json"
TMUX_CONFIG="${TMUX_CONFIG_FILE:-$HOME/.tmux.conf}"

# SHA256 of every tracked file in the permission-modes source snapshot.
# Generated from a verified checkout of ${PERMISSION_MODES_COMMIT}.
PERMISSION_MODES_MANIFEST_COUNT=69
PERMISSION_MODES_MANIFEST="$(cat <<'PM_MANIFEST'
8f6c12d90033922d595c78fc90bd1701a90cd9ecef39cee659b3f55d7ee59087  AGENTS.md
3561df3bed68d3c4babc0f5a3b31453f6af72f2c6bb204f04a980b3f024d8ba1  bash-permission-match.test.ts
f1371507650db63ae732be3e3794c92680fe11d296c16784f2dd6483ec1008e7  bash-permission-match.ts
83e1fcc9a63b9cd2d806b10b206946e7c69362df51a2c33c068c38bb8e46deec  branch-stats.test.ts
05b392a5f9bdadda000f0f508cd98ffb64ce97d2057d2c3abbb64e65ea58f926  branch-stats.ts
298f7b7f6611de4d40ced84ccce50a0a827a3b56fe35abb50ad35329c6dc96e5  cc-alignment.test.ts
f38d00ff9378e09c50a0b453baf42751bafe5b71d09e6195325b05f4eea04b4c  CHANGELOG.md
d4b144d0ca5ecdd26a25ddde3de1293ecb198fcc46cdd87ae73090fd6f31c1af  classifier-client.test.ts
aea667388d565a9a6da6b629db079669c30859accc0a2a096b44ba68f529ae53  classifier-client.ts
48ca6742009dc62e518d6dbcf02327b861e726c1a2931e52172033ac73a53ae4  classifier-messages.ts
eb04b2d2d3e2e276ac04fe31211ae1021db19c3e8139dd92613a02671147a51f  classifier-prompts/auto_mode_system_prompt.txt
3936ba0465c634d46bf0a6f899ecee1a4362fa718085db66137509dec7466e24  classifier-prompts/permissions_external.txt
b17174bbc9f4e26d1cc45192f64a4cb5c66737e34526eac2c03a21dcc54ebb95  classifier-prompt.test.ts
6d49d8683f01806701f8528e28e968e946b55a3646bf440662ae9121d64b99c9  classifier-prompt.ts
be73ef8106c30b67d4007e924270f6ac62a021206681b01ce2736d88996679b6  classifier-redact.ts
13a53d959a77ad18af2b10dc5f1e4268df1504173f9869491584abe8d2946623  classifier-tool-projection.test.ts
b8f1cf2f92e652fe053be2b9a6a6d68ed94822dff2e579f4a8a3049e923dc13d  classifier-tool-projection.ts
23a358bc9a0e0267dd38fef1916829bd6c7a5da0b72cd41568546e3e5a3350eb  classifier-tool.ts
5454a1662158c0cb9c6c77cf46e975b4ce10ab27b2563e8e5e40b6c531d66aba  classifier-transcript.test.ts
2854f726cb922ca3ffe40fd102750e863f5ea06a42de07cbd8581e882b3ac49c  classifier-transcript.ts
413ba30bd9d467f06ad6f9dd48b00c20b2a0f1c09c7f3580b3443db066df0d3b  CLAUDE.md
5db5add1eba1cc5d009d98283746006af9ac359e64c2bb9c14cdde07ea780527  config-cache.test.ts
cfea6ae407c44bf138d0a681fb1a365408847c83acbbf005da556745d36eb485  config.ts
7745d4c2abba79cb0274bc7fd7aa332147ff1fd0a541094474c332a552f66134  dangerous-permissions.test.ts
b774ca4b7ade4f7fb302b89b2efb8488f546c9991e661a0baea934c72fa73f92  dangerous-permissions.ts
2a196771b00d18896f82ed53f8c4a0997675f13f28812af436ae085a50650cd7  denial-tracking.ts
e6ace746004f5a89347bd2ca5382988dca0f9ea213ae1e8af50b35523560e741  docs/bash-risk-adjudication-2026-09-12.md
b4578e974e65339c161fa6ae3e377e56e05ae0854faa3caa72bcb49c74fbd2ff  docs/PRD.md
79a94acf32ad802978ed348cf1364840538b3fe186610505f3d68b9edbc1e3b3  docs/project-intelligence.md
ea0492adb8f5b5c4b78379485cb23dbb5c80f56e5923765d6aa637f4d1a0e296  docs/prompts/ask-mode-prompts.md
f36e80036a091ccfe72c80caa7007ea994b686b50c9d97b1aa3b3702ad0f0a99  docs/prompts/auto-mode-prompts.md
4e3b0477b19f0fcd153786231f6a70633cd56d5b3ec5a8f6cf4e6c9afe812767  docs/prompts/plan-mode-prompts.md
90f62ef14d62cd215bb2e24bd6608cd73ba780ffd45bf293115b9bc8ad6e42ce  docs/suggestions.md
299fe37daf8c6933b8ccb4c86f2233a7b48111126304ebdd543a7657aa649a62  fusion-tools.test.ts
0ffb4f32762218a61f0d1f2759e91ac0117a24ae6c958db8c5612368f6eac561  fusion-tools.ts
7387ce1305cf3b40c59ca3a121ccd82266b78f460d9c717694bb39429f3d5ca5  .github/workflows/release.yml
4d7f80ba3222d8510981d5302def0f5e934ecc98a110c5e54fc5c3cac05a2943  .github/workflows/test.yml
b8ef2be276125fde8eeb8e9aa64047e2eeecdefca46c4ec26be31f90ec074109  .gitignore
55ff435b0c9f24667b9e090a58c3c575b4a66042af967caef49313576f13ba03  index.test.ts
3e86b5f7d4df1698e919582304951f01b8538cc0e990f72fd56f03c2fcfdc666  index.ts
2b191b13e28f59cde118d7b39049a7b597d3026f29e37f042bc54653101dd0ee  injection-probe.ts
5f3e97c3e8cef9edb584f7d7785cc623966eb4fb8eefd1c5421e8a2797055206  LICENSE
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
8a789bc8d82783a9441fca0de3952e3d22dd3e611b2463d51c5bdcf1940a25a7  README.md
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

tmp_files=()
cleanup() {
	if ((${#tmp_files[@]})); then
		rm -f "${tmp_files[@]}"
	fi
}
trap cleanup EXIT

die() {
	echo "pi-bootstrap: $*" >&2
	exit 1
}

warn() {
	echo "pi-bootstrap: warning: $*" >&2
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		die "checksum verification requires sha256sum or shasum"
	fi
}

require_node_version() {
	local version major minor patch
	version="$(node -p 'process.versions.node')"
	if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
		die "could not parse Node.js version: ${version}"
	fi
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	patch="${BASH_REMATCH[3]}"
	if ((major < 22 || (major == 22 && minor < 19))); then
		die "Pi ${PI_VERSION} requires Node.js >=22.19.0; found ${major}.${minor}.${patch}"
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

# Remove settings.json package entries whose source contains $1 but is not $2.
# Uses `pi remove` so Pi's own bookkeeping stays consistent; never edits
# settings.json directly. Missing or malformed settings are ignored.
remove_stale_package_entries() {
	local filter="$1" keep="$2" entry
	[[ -f "$SETTINGS_FILE" ]] || return 0
	while IFS= read -r entry; do
		[[ -n "$entry" ]] || continue
		echo "Removing stale package entry: ${entry}"
		"$PI_BIN" remove "$entry" >/dev/null 2>&1 || true
	done < <(node - "$SETTINGS_FILE" "$filter" "$keep" <<'NODE'
const fs = require("node:fs");
const [file, filter, keep] = process.argv.slice(2);
try {
	const config = JSON.parse(fs.readFileSync(file, "utf8"));
	if (Array.isArray(config.packages)) {
		for (const entry of config.packages) {
			if (typeof entry === "string" && entry.includes(filter) && entry !== keep) {
				console.log(entry);
			}
		}
	}
} catch {}
NODE
)
}

install_classifier_extension() {
	local local_source="${PI_BOOTSTRAP_SOURCE_DIR:-}"
	if [[ -z "$local_source" && -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
		local_source="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	fi

	if [[ -n "$local_source" && -f "$local_source/extensions/classifier-model.ts" ]]; then
		install -m 0644 "$local_source/extensions/classifier-model.ts" "$EXTENSIONS_DIR/classifier-model.ts"
		return
	fi

	# Keep curl | bash self-contained. Local checkouts use the repository source file.
	cat > "$EXTENSIONS_DIR/classifier-model.ts" <<'CLASSIFIER_MODEL_EXTENSION'
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

# Verify the installed permission-modes source snapshot: exact commit, clean
# tree, and every tracked file matching the pinned SHA256 manifest.
verify_permission_modes() {
	local pkg_dir="$1" head status count=0 failures=0 expected rel actual

	head="$(git -C "$pkg_dir" rev-parse HEAD 2>/dev/null || true)"
	if [[ "$head" != "$PERMISSION_MODES_COMMIT" ]]; then
		die "permission-modes is at ${head:-unknown}, expected ${PERMISSION_MODES_COMMIT}"
	fi

	status="$(git -C "$pkg_dir" status --porcelain 2>/dev/null || true)"
	if [[ -n "$status" ]]; then
		die "permission-modes working tree has local modifications"
	fi

	while read -r expected rel; do
		[[ -n "$expected" && -n "$rel" ]] || continue
		if [[ ! -f "$pkg_dir/$rel" ]]; then
			echo "pi-bootstrap: manifest file missing: $rel" >&2
			failures=$((failures + 1))
			continue
		fi
		actual="$(hash_file "$pkg_dir/$rel")"
		if [[ "$actual" != "$expected" ]]; then
			echo "pi-bootstrap: checksum mismatch: $rel" >&2
			failures=$((failures + 1))
		fi
		count=$((count + 1))
	done < <(printf '%s\n' "$PERMISSION_MODES_MANIFEST")

	if ((count != PERMISSION_MODES_MANIFEST_COUNT)); then
		die "permission-modes manifest verified ${count}/${PERMISSION_MODES_MANIFEST_COUNT} files"
	fi
	if ((failures > 0)); then
		die "permission-modes source verification failed (${failures} problem(s))"
	fi
	echo "permission-modes ${PERMISSION_MODES_VERSION} source verified: commit ${PERMISSION_MODES_COMMIT:0:12}, ${count} files match SHA256 manifest."
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
	' "$file" > "$cleaned"
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
		printf '\n' >> "$TMUX_CONFIG"
	fi
	{
		printf '# >>> pi-bootstrap >>>\n'
		printf 'set -g extended-keys on\n'
		if [[ "$strategy" == "csi-u" ]]; then
			printf 'set -g extended-keys-format csi-u\n'
		fi
		printf '# <<< pi-bootstrap <<<\n'
	} >> "$TMUX_CONFIG"

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

main() {
	require_command node
	require_command npm
	require_command curl
	require_command git
	require_node_version

	mkdir -p "$EXTENSIONS_DIR"

	echo "Installing Pi Coding Agent ${PI_VERSION}..."
	npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

	# npm's global bin directory may not have been on PATH when this script started.
	PI_BIN="$(command -v pi || true)"
	if [[ -z "$PI_BIN" ]]; then
		NPM_GLOBAL_BIN="$(npm prefix -g)/bin"
		if [[ -x "$NPM_GLOBAL_BIN/pi" ]]; then
			PI_BIN="$NPM_GLOBAL_BIN/pi"
		else
			die "Pi was installed but the pi command could not be found"
		fi
	fi

	echo "Installing default Pi extensions..."
	remove_stale_package_entries "pi-btw" "npm:@narumitw/pi-btw@${PI_BTW_VERSION}"
	"$PI_BIN" install "npm:@narumitw/pi-btw@${PI_BTW_VERSION}"
	remove_stale_package_entries "pi-advisor-flow" "npm:pi-advisor-flow@${PI_ADVISOR_FLOW_VERSION}"
	"$PI_BIN" install "npm:pi-advisor-flow@${PI_ADVISOR_FLOW_VERSION}"

	echo "Installing permission-modes ${PERMISSION_MODES_VERSION} from pinned upstream commit ${PERMISSION_MODES_COMMIT:0:12}..."
	echo "(2.8.0 is a source-built snapshot, not an official npm release; it is verified against a SHA256 manifest.)"
	remove_stale_package_entries "permission-modes" "$PERMISSION_MODES_SOURCE"
	"$PI_BIN" install "$PERMISSION_MODES_SOURCE"

	PM_DIR="$(find "$AGENT_DIR/git" -maxdepth 4 -type d -name "pi-permission-modes" 2>/dev/null | head -n 1)"
	[[ -n "$PM_DIR" ]] || die "permission-modes source directory not found under $AGENT_DIR/git"
	verify_permission_modes "$PM_DIR"

	install_classifier_extension

	echo "Installing minimal-mode.ts from Pi v${PI_VERSION}..."
	minimal_tmp="$(mktemp)"
	tmp_files+=("$minimal_tmp")
	curl -fsSL "$MINIMAL_MODE_URL" -o "$minimal_tmp"
	minimal_hash="$(hash_file "$minimal_tmp")"
	if [[ "$minimal_hash" != "$MINIMAL_MODE_SHA256" ]]; then
		die "minimal-mode.ts from tag v${PI_VERSION} does not match pinned checksum ${MINIMAL_MODE_SHA256}"
	fi
	install -m 0644 "$minimal_tmp" "$EXTENSIONS_DIR/minimal-mode.ts"

	echo "Merging Pi keybindings..."
	merge_keybindings

	if command -v tmux >/dev/null 2>&1; then
		configure_tmux
	fi

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
