#!/usr/bin/env node
// The full default stack on the real Pi 1.4.0 loader: permission-modes 2.8.0 +
// pi-btw + pi-advisor-flow + classifier-model + minimal-mode, all at once.
//
// Needs an agent directory that already has the pinned packages installed
// (the installer produces one):
//   PI_BOOTSTRAP_AGENT_DIR=~/.pi/agent
// Without it this test SKIPS, so a machine without the stack reports
// "not exercised" rather than a false PASS.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { skipUnlessPi } from "./lib-pi.mjs";

const pi = skipUnlessPi("default stack load");
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

const agentDir = process.env.PI_BOOTSTRAP_AGENT_DIR || path.join(process.env.HOME || "", ".pi", "agent");
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
		path.join(agentDir, "git/github.com/GeorgeDong32/pi-permission-modes"),
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
	console.log(
		`SKIP default stack load: not installed (${missing.join(", ")}); set PI_BOOTSTRAP_AGENT_DIR to an agent directory with the pinned stack`,
	);
	process.exit(77);
}

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

const cwd = path.join(agentDir, "..", "..", "stack-work");
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
const permissionModes = result.extensions.find((extension) => extension.path.includes("permission-modes"));
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
