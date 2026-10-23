#!/usr/bin/env node
// P0: which file does the permission gate actually read?
//
// permission-modes 2.8.0 resolves every user file from homedir() and never
// reads PI_CODING_AGENT_DIR. This test proves that with the REAL Pi 1.4.0
// loader and the REAL pinned source, by giving two isolated directories
// contradictory rules and observing the gate's decision - not by inspecting
// any path.
//
//   B = $HOME/.pi/agent               (the file the gate uses)
//   A = PI_CODING_AGENT_DIR           (the directory Pi itself uses)
//
// Case 1: B denies, A allows -> the tool must be DENIED by a rule from B.
// Case 2: B allows, A denies -> the tool must NOT be denied: A was not read.
// Case 3: the two directories are the same -> the rule is honoured (sanity).
//
// That is the evidence behind install.sh require_supported_agent_dir(): with a
// custom agent directory the gate reads a different configuration than Pi, so
// the installer refuses instead of building that state.
//
// Runs only against the exact pinned matrix; a scratch HOME is required.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { skipUnlessPi, skipUnlessPinnedPermissionModes } from "./lib-pi.mjs";

const pi = skipUnlessPi("config source");
const home = process.env.HOME;
assert(home && !home.startsWith("/root"), "HOME must be an isolated scratch directory");
assert(
	path.resolve(home).startsWith(path.resolve(os.tmpdir())),
	`refusing to run: HOME ${home} is not a scratch directory under ${os.tmpdir()}`,
);

function findPermissionModes() {
	if (process.env.PI_BOOTSTRAP_PM_280) return process.env.PI_BOOTSTRAP_PM_280;
	for (const candidate of [
		path.join(home, ".pi/agent/git/github.com/GeorgeDong32/pi-permission-modes"),
		path.join(home, "pi-permission-modes"),
	]) {
		if (fs.existsSync(path.join(candidate, "index.ts"))) return candidate;
	}
	return undefined;
}

const sourceDir = findPermissionModes();
if (!sourceDir) {
	console.log("SKIP config source: permission-modes 2.8.0 source not found (set PI_BOOTSTRAP_PM_280)");
	process.exit(77);
}
skipUnlessPinnedPermissionModes("config source", sourceDir);

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-config-source."));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));

// A rule/command pair that the pinned matcher resolves deterministically.
const RULE = "Bash(denytest:*)";
const COMMAND = "denytest run";

const { loadExtensions, createExtensionRuntime } = await import(
	pathToFileURL(path.join(pi.dir, "dist/core/extensions/loader.js")).href
);

function writeConfig(file, permissions) {
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(
		file,
		JSON.stringify({ permissions, classifier: { enabled: false, model: "audit/audit", timeoutMs: 1000 } }, null, 2),
	);
}

// Load a fresh copy of the extension for one environment. A loader instance is
// created per case because the module reads homedir()-based paths at import.
async function decide({ label, agentDir, homeDir }) {
	const previousHome = process.env.HOME;
	const previousAgent = process.env.PI_CODING_AGENT_DIR;
	process.env.HOME = homeDir;
	if (agentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
	else process.env.PI_CODING_AGENT_DIR = agentDir;

	try {
		const runtime = createExtensionRuntime();
		for (const method of ["sendMessage", "sendUserMessage", "appendEntry", "setSessionName", "setLabel", "setActiveTools"]) {
			if (typeof runtime[method] === "function") runtime[method] = () => undefined;
		}
		runtime.getSessionName = () => `config-source-${label}`;
		runtime.getSettings = () => ({});
		runtime.getActiveTools = runtime.getAllTools = () => [];

		const work = path.join(scratch, `work-${label}`);
		fs.mkdirSync(work, { recursive: true });
		const loaded = await loadExtensions([path.join(sourceDir, "index.ts")], work, undefined, runtime);
		assert.deepEqual(loaded.errors, [], `${label}: no load errors: ${JSON.stringify(loaded.errors)}`);
		const extension = loaded.extensions.find((candidate) => candidate.commands.has("mode"));
		assert(extension, `${label}: permission-modes loaded`);

		const ui = new Proxy(
			{ notify: () => {}, select: async () => undefined, setWorkingMessage: () => {}, setStatus: () => {} },
			{ get: (target, property) => (property in target ? target[property] : () => undefined) },
		);
		const ctx = {
			mode: "tui",
			hasUI: false,
			cwd: work,
			ui,
			modelRegistry: { find: () => undefined, getApiKeyAndHeaders: async () => ({ ok: false }) },
			appendEntry: () => undefined,
			sendMessage: () => undefined,
			reload: async () => undefined,
		};

		// The gate refreshes its merged rules from the config on this event; a
		// real session always starts with it, so the decision must be observed
		// after it rather than on a bare handler call.
		for (const handler of extension.handlers.get("before_agent_start") ?? []) {
			await handler({ systemPrompt: "base" }, { ...ctx, getSystemPrompt: () => "base", sessionManager: {} });
		}
		// ask mode consults the rule table directly; auto mode would ask a model.
		await extension.commands.get("mode").handler("ask", ctx);
		const gate = extension.handlers.get("tool_call")[0];
		const result = await gate({ toolName: "bash", input: { command: COMMAND } }, ctx);
		return { result, reason: String(result?.reason ?? "") };
	} finally {
		process.env.HOME = previousHome;
		if (previousAgent === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = previousAgent;
	}
}

// --- case 1: the gate must follow $HOME, not PI_CODING_AGENT_DIR ----------
{
	const homeDir = path.join(scratch, "case1/home");
	const agentDir = path.join(scratch, "case1/agent");
	writeConfig(path.join(homeDir, ".pi/agent/permission-modes.json"), { deny: [RULE] });
	writeConfig(path.join(agentDir, "permission-modes.json"), { allow: [RULE] });
	const { result, reason } = await decide({ label: "case1", agentDir, homeDir });
	assert.equal(result?.block, true, `case1: the denying rule from $HOME blocks: ${JSON.stringify(result)}`);
	assert.match(reason, /Denied by permission rule \[global\]: Bash\(denytest:\*\)/, `case1: the decision cites $HOME's rule: ${reason}`);
	console.log("PASS gate source: a deny rule in $HOME/.pi/agent decides, although PI_CODING_AGENT_DIR allows it");
}

// --- case 2: an allow in $HOME wins over a deny in the custom directory ---
{
	const homeDir = path.join(scratch, "case2/home");
	const agentDir = path.join(scratch, "case2/agent");
	writeConfig(path.join(homeDir, ".pi/agent/permission-modes.json"), { allow: [RULE] });
	writeConfig(path.join(agentDir, "permission-modes.json"), { deny: [RULE] });
	const { result, reason } = await decide({ label: "case2", agentDir, homeDir });
	assert.doesNotMatch(reason, /Denied by permission rule/, `case2: the custom directory's deny rule is not read: ${reason}`);
	assert.notEqual(result?.block, true, `case2: an allowed command is not blocked: ${JSON.stringify(result)}`);
	console.log("PASS gate source: a deny rule in PI_CODING_AGENT_DIR is NOT read (the gate ignores it)");
}

// --- case 3: control - the default directory's rules do apply ------------
{
	const homeDir = path.join(scratch, "case3/home");
	writeConfig(path.join(homeDir, ".pi/agent/permission-modes.json"), { deny: [RULE] });
	const { result, reason } = await decide({ label: "case3", agentDir: undefined, homeDir });
	assert.equal(result?.block, true, `case3: the rule still applies in the default layout: ${JSON.stringify(result)}`);
	assert.match(reason, /Denied by permission rule/, `case3: control decision cites the rule: ${reason}`);
	console.log("PASS gate source: control - the default layout honours the rule");
}

console.log("permission config source: ALL PASS (the gate reads $HOME/.pi/agent, never PI_CODING_AGENT_DIR)");
