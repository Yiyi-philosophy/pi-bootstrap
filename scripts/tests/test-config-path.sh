#!/usr/bin/env bash
# M1: the classifier selection must land in Pi's actual agent directory.
#
# Covers: the default HOME layout, a custom PI_CODING_AGENT_DIR (relative, with
# a trailing slash, and with a leading ~), the historical PI_AGENT_DIR being
# ignored exactly as Pi ignores it, the upstream mirror that permission-modes
# 2.8.0 reads, and persistence across a reload.
#
# Runs in an isolated HOME with no Pi and no network: the extension is loaded
# directly (Node's type stripping) and driven with a stub UI/registry.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

root="$(new_root)"
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"

extension="$repo_dir/extensions/classifier-model.ts"
# The child processes below import the extension through this variable, so it
# must be exported once rather than passed per call.
export EXTENSION="$extension"

# Drive /classifier-model in a child process whose environment is exactly the
# one under test, then print the path the extension wrote and the files on disk.
run_picker() {
	env "$@" SCRATCH="$root" node --input-type=module -e '
		import fs from "node:fs";
		import path from "node:path";
		import { pathToFileURL } from "node:url";

		const { default: install } = await import(pathToFileURL(process.env.EXTENSION).href);
		const commands = new Map();
		install({ registerCommand: (name, options) => commands.set(name, options) });
		const notices = [];
		await commands.get("classifier-model").handler("", {
			mode: "tui",
			hasUI: true,
			cwd: process.env.SCRATCH,
			ui: new Proxy({ notify: (...args) => notices.push(args), select: async (_title, options) => options[0] }, {
				get: (target, property) => (property in target ? target[property] : () => undefined),
			}),
			modelRegistry: {
				refresh: async () => ({}),
				getAvailable: () => [{ provider: "audit", id: "model" }],
			},
			reload: async () => {},
		});
		console.log(JSON.stringify({ notices: notices.map((args) => String(args[0])) }));
	'
}

config_of() {
	node -e 'const fs=require("fs");const p=process.argv[1];try{process.stdout.write(JSON.parse(fs.readFileSync(p,"utf8")).classifier.model||"")}catch{}' "$1"
}

# --- 1. default HOME -------------------------------------------------------
home="$root/home"
mkdir -p "$home/.pi/agent"
run_picker HOME="$home" >"$root/default.log" 2>&1 ||
	fail_test "default layout failed: $(cat "$root/default.log")"
assert_eq "audit/model" "$(config_of "$home/.pi/agent/permission-modes.json")" "default HOME writes \$HOME/.pi/agent"
pass "default HOME: selection written to \$HOME/.pi/agent/permission-modes.json"

# --- 2. custom PI_CODING_AGENT_DIR ----------------------------------------
custom="$root/custom-agent"
mkdir -p "$custom"
run_picker HOME="$home" PI_CODING_AGENT_DIR="$custom" >"$root/custom.log" 2>&1 ||
	fail_test "custom PI_CODING_AGENT_DIR failed: $(cat "$root/custom.log")"
assert_eq "audit/model" "$(config_of "$custom/permission-modes.json")" "custom agent dir receives the selection"
[[ ! -f "$home/.pi/agent/permission-modes.json" ]] ||
	[[ "$(config_of "$home/.pi/agent/permission-modes.json")" == "audit/model" ]] ||
	fail_test "custom agent dir: the default path was written with unrelated content"
pass "custom PI_CODING_AGENT_DIR: selection written to the configured directory"

# --- 3. trailing slash and relative path ----------------------------------
trailing="$root/trailing-agent"
mkdir -p "$trailing"
run_picker HOME="$home" PI_CODING_AGENT_DIR="$trailing/" >"$root/trailing.log" 2>&1 ||
	fail_test "trailing slash failed: $(cat "$root/trailing.log")"
assert_eq "audit/model" "$(config_of "$trailing/permission-modes.json")" "a trailing slash is tolerated"

(cd "$root" && mkdir -p relative-agent &&
	env HOME="$home" PI_CODING_AGENT_DIR="relative-agent" node --input-type=module -e '
		import { pathToFileURL } from "node:url";
		const { default: install } = await import(pathToFileURL(process.env.EXTENSION).href);
		const commands = new Map();
		install({ registerCommand: (name, options) => commands.set(name, options) });
		await commands.get("classifier-model").handler("", {
			mode: "tui", hasUI: true, cwd: process.cwd(),
			ui: new Proxy({ notify: () => {}, select: async (_t, options) => options[0] }, {
				get: (target, property) => (property in target ? target[property] : () => undefined),
			}),
			modelRegistry: { refresh: async () => ({}), getAvailable: () => [{ provider: "audit", id: "model" }] },
			reload: async () => {},
		});
	' >"$root/relative.log" 2>&1) ||
	fail_test "relative agent dir failed: $(cat "$root/relative.log")"
assert_eq "audit/model" "$(config_of "$root/relative-agent/permission-modes.json")" "a relative path resolves against the cwd"
pass "custom agent dir: trailing slash and relative paths both resolve to the configured directory"

# --- 4. PI_AGENT_DIR is ignored, exactly as Pi ignores it -----------------
legacy="$root/legacy-agent"
mkdir -p "$legacy"
run_picker HOME="$home" PI_AGENT_DIR="$legacy" >"$root/legacy.log" 2>&1 ||
	fail_test "PI_AGENT_DIR run failed: $(cat "$root/legacy.log")"
assert_eq "audit/model" "$(config_of "$home/.pi/agent/permission-modes.json")" "PI_AGENT_DIR does not redirect the selection"
[[ ! -f "$legacy/permission-modes.json" ]] ||
	fail_test "PI_AGENT_DIR: a file was written to a directory Pi never reads"
pass "PI_AGENT_DIR: ignored (Pi ignores it too); the default Pi directory is used"

# --- 4b. a leading ~ is expanded, as Pi expands it -----------------------
tilde_agent="$root/tilde-agent"
mkdir -p "$tilde_agent"
run_picker HOME="$root/tilde-home" PI_CODING_AGENT_DIR="~" >"$root/tilde.log" 2>&1 ||
	fail_test "tilde agent dir failed: $(cat "$root/tilde.log")"
assert_eq "audit/model" "$(config_of "$root/tilde-home/permission-modes.json")" "~ expands to HOME"
pass "custom agent dir: a leading ~ expands to HOME, matching Pi"

# --- 5. the upstream mirror permission-modes 2.8.0 actually reads ---------
# permission-modes resolves its config from homedir(); when Pi runs with a
# custom directory the extension mirrors the classifier block there, so the gate
# reads the user's choice instead of a stale or absent file.
mirrored_home="$root/mirror-home"
mkdir -p "$mirrored_home/.pi/agent"
printf '{"permissions":{"allow":["Read(*)"]},"classifier":{"timeoutMs":9000}}\n' \
	>"$mirrored_home/.pi/agent/permission-modes.json"
mirror_agent="$root/mirror-agent"
mkdir -p "$mirror_agent"
run_picker HOME="$mirrored_home" PI_CODING_AGENT_DIR="$mirror_agent" >"$root/mirror.log" 2>&1 ||
	fail_test "mirror run failed: $(cat "$root/mirror.log")"
assert_eq "audit/model" "$(config_of "$mirror_agent/permission-modes.json")" "the configured directory gets the selection"
assert_eq "audit/model" "$(config_of "$mirrored_home/.pi/agent/permission-modes.json")" "the upstream path is mirrored"
assert_eq "9000" "$(node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(c.classifier.timeoutMs))' "$mirrored_home/.pi/agent/permission-modes.json")" "the mirror keeps the existing timeout"
assert_eq "Read(*)" "$(node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(c.permissions.allow[0])' "$mirrored_home/.pi/agent/permission-modes.json")" "the mirror keeps existing permission rules"
assert_contains "$(cat "$root/mirror.log")" "mirrored" "the mirror is reported to the user"
pass "upstream compatibility: the classifier block is mirrored to the path permission-modes 2.8.0 reads"

# --- 6. persistence across a reload --------------------------------------
reload_agent="$root/reload-agent"
mkdir -p "$reload_agent"
run_picker HOME="$home" PI_CODING_AGENT_DIR="$reload_agent" >/dev/null 2>&1 ||
	fail_test "reload: first selection failed"
cp "$reload_agent/permission-modes.json" "$root/before-reload.json"
run_picker HOME="$home" PI_CODING_AGENT_DIR="$reload_agent" >/dev/null 2>&1 ||
	fail_test "reload: second selection failed"
python3 - "$root/before-reload.json" "$reload_agent/permission-modes.json" <<'PY' ||
import json, sys
before = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
assert before == after, f"reload changed the file: {before} != {after}"
PY
	fail_test "reload: the persisted selection changed across a reload"
pass "persistence: the selection is stable across a reload"

echo "classifier config path tests passed"
