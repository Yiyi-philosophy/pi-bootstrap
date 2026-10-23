#!/usr/bin/env bash
# M1/R4-H1: where /classifier-model writes, and where it refuses to write.
#
# permission-modes 2.8.0 reads `$HOME/.pi/agent/permission-modes.json` and
# cannot be redirected (config.ts in the pinned source sets the path at module
# load; the only setter is a test helper). The command therefore:
#
#   * writes Pi's own config when Pi's agent directory IS that directory
#     (default HOME, a trailing slash, a relative path that resolves there);
#   * fails closed - writing nothing anywhere - when Pi's directory is anything
#     else, instead of mirroring the selection into the real HOME.
#
# The last case is the H1 finding: a test or throwaway Pi instance with
# PI_CODING_AGENT_DIR set must never rewrite the user's real config.
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
# one under test and print a JSON summary: notices, whether the picker ran.
# PICKER_CWD (optional) is the child's working directory, which is what a
# relative PI_CODING_AGENT_DIR resolves against.
run_picker() {
	(
		cd "${PICKER_CWD:-$root}" || exit 1
		env "$@" SCRATCH="$root" node --input-type=module -e '
		import { pathToFileURL } from "node:url";

		const { default: install } = await import(pathToFileURL(process.env.EXTENSION).href);
		const commands = new Map();
		install({ registerCommand: (name, options) => commands.set(name, options) });
		const notices = [];
		let pickerShown = false;
		await commands.get("classifier-model").handler("", {
			mode: "tui",
			hasUI: true,
			cwd: process.cwd(),
			ui: new Proxy({
				notify: (...args) => notices.push([String(args[0]), String(args[1] ?? "")]),
				select: async (_title, options) => {
					pickerShown = true;
					return options[0];
				},
			}, { get: (target, property) => (property in target ? target[property] : () => undefined) }),
			modelRegistry: {
				refresh: async () => ({}),
				getAvailable: () => [{ provider: "audit", id: "model" }],
			},
			reload: async () => {},
		});
		console.log(JSON.stringify({ notices, pickerShown }));
	'
	)
}

config_of() {
	node -e 'const fs=require("fs");const p=process.argv[1];try{process.stdout.write(JSON.parse(fs.readFileSync(p,"utf8")).classifier.model||"")}catch{}' "$1"
}

# Assert a picker run was refused for an unsupported directory and wrote
# nothing there. The caller separately proves the real HOME file is untouched.
assert_refused() {
	local label="$1" log="$2" agent="$3" summary notices
	summary="$(cat "$log")"
	notices="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.notices.map(n=>n[0]).join("\n"))' "$summary")"
	assert_contains "$notices" "cannot save a selection here" "$label: refusal is explained"
	assert_contains "$notices" "permission-modes 2.8.0 always reads" "$label: refusal names the file the gate reads"
	node -e 'const s=JSON.parse(process.argv[1]);process.exit(s.pickerShown?1:0)' "$summary" ||
		fail_test "$label: the picker was shown for a directory that cannot be written"
	[[ -z "$(ls -A "$agent" 2>/dev/null)" ]] ||
		fail_test "$label: the unsupported agent dir was written: $(ls -A "$agent")"
	pass "$label: refused, no picker, nothing written in the configured directory"
}

home="$root/home"
mkdir -p "$home/.pi/agent"

# --- 1. default HOME -------------------------------------------------------
run_picker HOME="$home" >"$root/default.log" 2>&1 ||
	fail_test "default layout failed: $(cat "$root/default.log")"
assert_eq "audit/model" "$(config_of "$home/.pi/agent/permission-modes.json")" "default HOME writes \$HOME/.pi/agent"
pass "default HOME: selection written to \$HOME/.pi/agent/permission-modes.json"

# --- 2. the default path spelled with a trailing slash --------------------
rm -f "$home/.pi/agent/permission-modes.json"
run_picker HOME="$home" PI_CODING_AGENT_DIR="$home/.pi/agent/" >"$root/trailing.log" 2>&1 ||
	fail_test "trailing slash failed: $(cat "$root/trailing.log")"
assert_eq "audit/model" "$(config_of "$home/.pi/agent/permission-modes.json")" "a trailing slash resolves to the same file"
pass "same directory spelled with a trailing slash: accepted, one file"

# --- 3. the default path spelled relatively, from inside it --------------
rm -f "$home/.pi/agent/permission-modes.json"
PICKER_CWD="$home/.pi/agent" run_picker HOME="$home" PI_CODING_AGENT_DIR="." >"$root/relative.log" 2>&1 ||
	fail_test "relative default path failed: $(cat "$root/relative.log")"
assert_eq "audit/model" "$(config_of "$home/.pi/agent/permission-modes.json")" "a relative path resolves against the cwd"
pass "same directory spelled relatively: accepted, one file"

# --- 4. PI_AGENT_DIR is ignored, exactly as Pi ignores it -----------------
legacy="$root/legacy-agent"
mkdir -p "$legacy"
rm -f "$home/.pi/agent/permission-modes.json"
run_picker HOME="$home" PI_AGENT_DIR="$legacy" >"$root/legacy.log" 2>&1 ||
	fail_test "PI_AGENT_DIR run failed: $(cat "$root/legacy.log")"
assert_eq "audit/model" "$(config_of "$home/.pi/agent/permission-modes.json")" "PI_AGENT_DIR does not redirect the selection"
[[ ! -e "$legacy/permission-modes.json" ]] ||
	fail_test "PI_AGENT_DIR: a file was written to a directory Pi never reads"
pass "PI_AGENT_DIR: ignored (Pi ignores it too); the default Pi directory is used"

# --- 5. a custom PI_CODING_AGENT_DIR must be refused (H1) -----------------
# The user's real config already exists and holds their classifier model: the
# run must not touch a single byte of it.
printf '{"classifier":{"model":"user/real-model","timeoutMs":15000},"permissions":{"deny":["Bash(rm *)"]}}\n' \
	>"$home/.pi/agent/permission-modes.json"
cp "$home/.pi/agent/permission-modes.json" "$root/upstream-before.json"
for custom in "$root/custom-agent" "$root/trailing-agent/" "~" "relative-agent"; do
	label="custom PI_CODING_AGENT_DIR [$custom]"
	if [[ "$custom" == "relative-agent" ]]; then
		mkdir -p "$root/relative-agent"
		PICKER_CWD="$root" run_picker HOME="$home" PI_CODING_AGENT_DIR="$custom" >"$root/custom.log" 2>&1 ||
			fail_test "$label: the run crashed: $(cat "$root/custom.log")"
		assert_refused "$label" "$root/custom.log" "$root/relative-agent"
		rm -rf "$root/relative-agent"
	elif [[ "$custom" == "~" ]]; then
		# "~" expands to HOME, which is not Pi's agent directory.
		run_picker HOME="$home" PI_CODING_AGENT_DIR="$custom" >"$root/custom.log" 2>&1 ||
			fail_test "$label: the run crashed: $(cat "$root/custom.log")"
		summary="$(cat "$root/custom.log")"
		assert_contains "$summary" "cannot save a selection here" "$label: refusal is explained"
		node -e 'const s=JSON.parse(process.argv[1]);process.exit(s.pickerShown?1:0)' "$summary" ||
			fail_test "$label: the picker was shown for a directory that cannot be written"
		[[ ! -e "$home/permission-modes.json" ]] || fail_test "$label: HOME itself was written"
		pass "$label: refused, no picker, HOME itself was not written"
	else
		mkdir -p "$root/trailing-agent" "$root/custom-agent"
		run_picker HOME="$home" PI_CODING_AGENT_DIR="$custom" >"$root/custom.log" 2>&1 ||
			fail_test "$label: the run crashed: $(cat "$root/custom.log")"
		assert_refused "$label" "$root/custom.log" "${custom%/}"
	fi
	cmp -s "$root/upstream-before.json" "$home/.pi/agent/permission-modes.json" ||
		fail_test "$label: the user's real \$HOME config was modified"
done
pass "H1: every unsupported agent directory fails closed; the real HOME config is byte-identical"

# --- 6. persistence across a reload --------------------------------------
mkdir -p "$home/.pi/agent"
printf '{"classifier":{"model":"audit/model"}}\n' >"$home/.pi/agent/permission-modes.json"
run_picker HOME="$home" >/dev/null 2>&1 || fail_test "reload: first selection failed"
cp "$home/.pi/agent/permission-modes.json" "$root/before-reload.json"
run_picker HOME="$home" >/dev/null 2>&1 || fail_test "reload: second selection failed"
node - "$root/before-reload.json" "$home/.pi/agent/permission-modes.json" <<'NODE' ||
const fs = require("node:fs");
const before = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const after = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
if (JSON.stringify(before) !== JSON.stringify(after)) {
	console.error(`reload changed the file: ${JSON.stringify(before)} != ${JSON.stringify(after)}`);
	process.exit(1);
}
NODE
	fail_test "reload: the persisted selection changed across a reload"
pass "persistence: the selection is stable across a reload"

echo "classifier config path tests passed"
