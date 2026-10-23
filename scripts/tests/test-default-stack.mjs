#!/usr/bin/env node
// The full default stack on the real Pi 1.4.0 loader: permission-modes 2.8.0 +
// pi-btw + pi-advisor-flow + classifier-model + minimal-mode, all at once.
//
// Needs an agent directory that already has the pinned packages installed
// (the installer produces one):
//   PI_BOOTSTRAP_AGENT_DIR=/path/to/copy-of-agent-dir
// The directory is COPIED into a scratch tree first and the copy is what gets
// loaded and written to, so this test can never modify the caller's real Pi
// configuration (M2). The original is only read.
//
// Every component's version is checked against the pinned matrix (M3) before
// anything is loaded; a mismatch is a SKIP naming the version, never a PASS.
// Without a configured directory this test SKIPS, so a machine without the
// stack reports "not exercised" rather than a false PASS.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
	PI_ADVISOR_FLOW_VERSION,
	PI_BTW_VERSION,
	readVersion,
	skipUnlessPi,
	skipUnlessPinnedPermissionModes,
} from "./lib-pi.mjs";

const pi = skipUnlessPi("default stack load");
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function skip(message) {
	console.log(`SKIP default stack load: ${message}`);
	process.exit(77);
}

const configured = process.env.PI_BOOTSTRAP_AGENT_DIR;
if (!configured) {
	skip("set PI_BOOTSTRAP_AGENT_DIR to a copy of an agent directory with the pinned stack");
}
const sourceAgentDir = path.resolve(configured);
if (!fs.existsSync(sourceAgentDir)) skip(`PI_BOOTSTRAP_AGENT_DIR does not exist: ${sourceAgentDir}`);

// Copy the CI-relevant parts of the agent directory into a scratch tree. The
// original is never written to: this test adds/changes permission-modes.json
// and must not touch the caller's configuration.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-stack."));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));
const agentDir = path.join(scratch, "agent");
for (const entry of ["npm", "git", "extensions", "settings.json"]) {
	const from = path.join(sourceAgentDir, entry);
	if (fs.existsSync(from)) fs.cpSync(from, path.join(agentDir, entry), { recursive: true, dereference: true });
}
fs.mkdirSync(agentDir, { recursive: true });
const expectedCommands = [
	"classifier-model",
	"mode",
	"permissions",
	"btw",
	"advisor",
	"advisor-models",
	"advisor-settings",
	"advisor-stats",
];

function locate() {
	const permissionModes = [
		process.env.PI_BOOTSTRAP_PM_280,
		path.join(sourceAgentDir, "git/github.com/GeorgeDong32/pi-permission-modes"),
	].find((candidate) => candidate && fs.existsSync(path.join(candidate, "index.ts")));
	const btw = path.join(agentDir, "npm/node_modules/@narumitw/pi-btw/dist/index.ts");
	const advisor = path.join(agentDir, "npm/node_modules/pi-advisor-flow/dist/index.js");
	const classifier = path.join(repo, "extensions/classifier-model.ts");
	const minimal = path.join(agentDir, "extensions/minimal-mode.ts");
	return { permissionModes, btw, advisor, classifier, minimal };
}

const files = locate();
const missing = Object.entries(files)
	.filter(([, file]) => !file || !fs.existsSync(file))
	.map(([key]) => key);
if (missing.length > 0) {
	skip(`not installed (${missing.join(", ")}); set PI_BOOTSTRAP_AGENT_DIR to an agent directory with the pinned stack`);
}

// Exact versions and provenance, before loading anything (M3).
const expectedVersions = {
	"pi-btw": [PI_BTW_VERSION, path.join(agentDir, "npm/node_modules/@narumitw/pi-btw")],
	"pi-advisor-flow": [PI_ADVISOR_FLOW_VERSION, path.join(agentDir, "npm/node_modules/pi-advisor-flow")],
};
for (const [label, [expected, dir]] of Object.entries(expectedVersions)) {
	const actual = readVersion(dir);
	if (actual !== expected) skip(`${label} at ${dir} is ${actual ?? "unknown"}, the pinned matrix requires ${expected}`);
}
// 2.8.0 was never published to npm: its provenance is the pinned commit.
skipUnlessPinnedPermissionModes("default stack load", files.permissionModes);

fs.mkdirSync(agentDir, { recursive: true });
// A classifier selection must exist for permission-modes to construct its gate.
const configPath = path.join(agentDir, "permission-modes.json");
const previousConfig = fs.existsSync(configPath) ? fs.readFileSync(configPath, "utf8") : undefined;
fs.writeFileSync(
	configPath,
	JSON.stringify({ classifier: { enabled: true, model: "stack/model", timeoutMs: 2000 } }, null, 2),
);

const { loadExtensions, createExtensionRuntime } = await import(
	pathToFileURL(path.join(pi.dir, "dist/core/extensions/loader.js")).href
);
const runtime = createExtensionRuntime();
for (const method of ["sendMessage", "sendUserMessage", "appendEntry", "setSessionName", "setLabel", "setActiveTools"]) {
	if (typeof runtime[method] === "function") runtime[method] = () => undefined;
}
runtime.getSessionName = () => "stack-test";
runtime.getSettings = () => ({});
runtime.getActiveTools = runtime.getAllTools = () => [];

const cwd = path.join(scratch, "stack-work");
fs.mkdirSync(cwd, { recursive: true });

let result;
try {
	result = await loadExtensions(
		[files.permissionModes, files.btw, files.advisor, files.classifier, files.minimal],
		cwd,
		undefined,
		runtime,
	);
} finally {
	if (previousConfig === undefined) fs.rmSync(configPath, { force: true });
	else fs.writeFileSync(configPath, previousConfig);
}

assert.deepEqual(result.errors, [], `no extension load errors: ${JSON.stringify(result.errors)}`);
assert.equal(result.extensions.length, 5, `five extensions loaded, got ${result.extensions.length}`);

const commands = new Map(result.extensions.flatMap((extension) => [...extension.commands]));
const registered = expectedCommands.filter((name) => commands.has(name));
const absent = expectedCommands.filter((name) => !commands.has(name));
assert.deepEqual(absent, [], `all expected commands registered (missing: ${absent.join(", ")})`);
console.log(`PASS default stack: 5 extensions loaded on Pi ${pi.version}, ${registered.length} commands registered`);

// permission-modes must install a tool_call gate; without it, nothing else matters.
// Identify permission-modes by the commands it registers, not by its path: a
// PI_BOOTSTRAP_PM_280 checkout may live in any directory.
const permissionModes = result.extensions.find(
	(extension) => extension.commands.has("mode") && extension.commands.has("permissions"),
);
assert(permissionModes, "permission-modes extension present");
const gate = permissionModes.handlers.get("tool_call");
assert(Array.isArray(gate) && gate.length >= 1, "permission-modes registered a tool_call gate");
console.log("PASS default stack: permission-modes registered its tool_call gate");

// Loading advisor-flow and btw must not mutate unrelated user configuration.
for (const file of ["auth.json", "models.json"]) {
	const full = path.join(agentDir, file);
	if (fs.existsSync(full)) {
		const text = fs.readFileSync(full, "utf8");
		assert(text === "" || text.trim().startsWith("{"), `${file} not corrupted by extension load`);
	}
}
console.log("PASS default stack: no credentials or model files were modified");

console.log("default stack load: ALL PASS");
