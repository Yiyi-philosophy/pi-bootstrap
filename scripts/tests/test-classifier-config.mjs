#!/usr/bin/env node
// classifier-model.ts configuration safety, exercised through the real
// extension module (Node's built-in TypeScript type stripping; no build step).
//
// The extension resolves its config path from homedir(), so this test must run
// with HOME pointing at a scratch directory (scripts/tests/run-all.sh does).
// Nothing here touches a model provider: the registry and UI are stubs.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const extensionPath = path.join(repo, "extensions/classifier-model.ts");

const home = process.env.HOME;
assert(home && !home.startsWith("/root"), "HOME must be an isolated scratch directory");
const agentDir = path.join(home, ".pi", "agent");
const configPath = path.join(agentDir, "permission-modes.json");
fs.mkdirSync(agentDir, { recursive: true });

const { default: install } = await import(pathToFileURL(extensionPath).href);
const commands = new Map();
install({ registerCommand: (name, options) => commands.set(name, options) });
assert(commands.has("classifier-model"), "registers the /classifier-model command");
const handler = commands.get("classifier-model").handler;

const notices = [];
const state = {
	selection: "audit/model",
	refreshFails: false,
	reloadFails: false,
	reloads: 0,
	available: [
		{ provider: "audit", id: "model" },
		{ provider: "audit", id: "model2" },
	],
	hasUI: true,
};
const ui = new Proxy(
	{
		notify: (...args) => notices.push(args),
		select: async (_title, options) => {
			if (state.selection === undefined) return undefined;
			if (state.selection === "DISABLE") return options[options.length - 1];
			return options.find((option) => option.endsWith(`/${state.selection.split("/")[1]}`)) ?? options[0];
		},
	},
	{ get: (target, property) => (property in target ? target[property] : () => undefined) },
);
const ctx = {
	mode: "tui",
	cwd: os.tmpdir(),
	ui,
	modelRegistry: {
		refresh: async () => {
			if (state.refreshFails) throw new Error("offline");
		},
		getAvailable: () => state.available,
	},
	reload: async () => {
		state.reloads += 1;
		if (state.reloadFails) throw new Error("reload failed");
	},
};
Object.defineProperty(ctx, "hasUI", { get: () => state.hasUI });

const run = () => handler("", ctx);
const readConfig = () => JSON.parse(fs.readFileSync(configPath, "utf8"));
const reset = () => {
	fs.rmSync(configPath, { force: true });
	state.selection = "audit/model";
	state.refreshFails = false;
	state.reloadFails = false;
	state.reloads = 0;
	state.hasUI = true;
	notices.length = 0;
};

// 1. New file: defaults, mode bits, reload.
reset();
await run();
assert.deepEqual(readConfig().classifier, { enabled: true, model: "audit/model", timeoutMs: 60000 });
assert.equal(fs.statSync(configPath).mode & 0o777, 0o600, "new config file is 0600");
assert.equal(state.reloads, 1, "ctx.reload invoked once");
console.log("PASS new config: defaults, 0600 mode, reload");

// 2. Existing file: unrelated fields, permission rules, timeout, mode preserved.
reset();
const original = {
	custom: { nested: ["keep"] },
	permissions: { allow: ["Read(*)"], deny: ["Bash(rm *)"], ask: ["Write(*)"] },
	classifier: { model: "old/model", timeoutMs: 12345, failClosed: true, stage: "tool", custom: "keep" },
};
fs.writeFileSync(configPath, JSON.stringify(original));
fs.chmodSync(configPath, 0o640);
await run();
const merged = readConfig();
assert.deepEqual(merged.permissions, original.permissions, "permission rules untouched");
assert.deepEqual(merged.custom, original.custom, "unrelated sections untouched");
assert.equal(merged.classifier.timeoutMs, 12345, "existing timeout preserved");
assert.equal(merged.classifier.failClosed, true, "failClosed preserved");
assert.equal(merged.classifier.custom, "keep", "unknown classifier fields preserved");
assert.equal(merged.classifier.model, "audit/model", "model updated");
assert.equal(fs.statSync(configPath).mode & 0o777, 0o640, "mode bits preserved");
console.log("PASS existing config: unrelated data, timeout, failClosed, and mode bits preserved");

// 3. Disable keeps the previous model and timeout.
reset();
fs.writeFileSync(configPath, JSON.stringify(original));
state.selection = "DISABLE";
await run();
const disabled = readConfig();
assert.equal(disabled.classifier.enabled, false, "disabled");
assert.equal(disabled.classifier.model, "old/model", "previous model retained");
assert.equal(disabled.classifier.timeoutMs, 12345, "timeout retained");
console.log("PASS disable: enabled=false while model and timeout are retained");

// 4. Malformed JSON is refused without touching the file.
reset();
for (const invalid of ["{broken", "[]", "null", '"string"', ""]) {
	fs.writeFileSync(configPath, invalid === "" ? "   " : invalid);
	const before = fs.readFileSync(configPath, "utf8");
	await run();
	assert.equal(fs.readFileSync(configPath, "utf8"), before, `invalid config left intact: ${JSON.stringify(invalid)}`);
}
assert(notices.some((args) => String(args[0]).includes("Could not parse")), "parse error surfaced to the user");
console.log("PASS malformed or non-object config: refused, file untouched, user notified");

// 5. Cancel changes nothing.
reset();
fs.writeFileSync(configPath, JSON.stringify(original));
const beforeCancel = fs.readFileSync(configPath, "utf8");
state.selection = undefined;
await run();
assert.equal(fs.readFileSync(configPath, "utf8"), beforeCancel, "cancel leaves the file alone");
assert.equal(state.reloads, 0, "cancel does not reload");
console.log("PASS cancelled selection: no write, no reload");

// 6. Registry refresh failure falls back to the cached model list.
reset();
state.refreshFails = true;
await run();
assert(notices.some((args) => String(args[0]).includes("cached models")), "refresh failure reported as a warning");
assert.equal(readConfig().classifier.model, "audit/model", "selection still saved");
console.log("PASS refresh failure: cached models used, selection still saved");

// 7. No UI: refuse and change nothing.
reset();
fs.writeFileSync(configPath, JSON.stringify(original));
state.hasUI = false;
const beforeNoUi = fs.readFileSync(configPath, "utf8");
await run();
assert.equal(fs.readFileSync(configPath, "utf8"), beforeNoUi, "no-UI run does not write");
assert(notices.some((args) => String(args[0]).includes("requires interactive UI")), "no-UI guard reported");
state.hasUI = true;
console.log("PASS no UI: refuses without touching the config");

// 8. Reload failure keeps the saved file and asks the user to run /reload.
reset();
fs.writeFileSync(configPath, JSON.stringify(original));
state.reloadFails = true;
await run();
assert(notices.some((args) => String(args[0]).includes("/reload")), "reload failure instructs the user to run /reload");
assert.equal(readConfig().classifier.model, "audit/model", "selection still persisted");
console.log("PASS reload failure: config saved, /reload fallback message shown");

// 9. No temporary residue, even when the write cannot complete.
assert(!fs.readdirSync(agentDir).some((name) => name.includes(".tmp-")), "no temporary files left behind");
fs.renameSync(configPath, `${configPath}.saved`);
fs.mkdirSync(configPath);
const listing = fs.readdirSync(agentDir).sort();
await run();
assert(fs.statSync(configPath).isDirectory(), "the obstructing directory is left alone");
assert.deepEqual(fs.readdirSync(agentDir).sort(), listing, "nothing was created or removed");
fs.rmSync(configPath, { recursive: true });
fs.renameSync(`${configPath}.saved`, configPath);
console.log("PASS failed atomic write: original untouched, no residue");

// 10. A write that cannot succeed is reported to the user, never thrown.
// The config path is derived from homedir() at import time, so this case runs
// in a child process whose HOME is a read-only agent directory.
{
	const readOnlyHome = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-ro-home."));
	const readOnlyAgent = path.join(readOnlyHome, ".pi", "agent");
	fs.mkdirSync(readOnlyAgent, { recursive: true });
	fs.chmodSync(readOnlyAgent, 0o500);
	const childScript = `
		import { pathToFileURL } from "node:url";
		const { default: install } = await import(pathToFileURL(process.argv[1]).href);
		const commands = new Map();
		install({ registerCommand: (name, options) => commands.set(name, options) });
		const notices = [];
		const ui = new Proxy({
			notify: (...args) => notices.push(args),
			select: async () => "audit/model",
		}, { get: (t, p) => (p in t ? t[p] : () => undefined) });
		await commands.get("classifier-model").handler("", {
			mode: "tui", hasUI: true, cwd: process.cwd(), ui,
			modelRegistry: { refresh: async () => ({}), getAvailable: () => [{ provider: "audit", id: "model" }] },
			reload: async () => {},
		});
		const message = notices.map((args) => String(args[0])).find((text) => text.includes("Could not write"));
		if (!message) {
			console.error("no write-failure notice; notices were " + JSON.stringify(notices));
			process.exit(1);
		}
	`;
	const result = spawnSync(process.execPath, ["--input-type=module", "-e", childScript, extensionPath], {
		env: { ...process.env, HOME: readOnlyHome },
		encoding: "utf8",
	});
	fs.chmodSync(readOnlyAgent, 0o700);
	fs.rmSync(readOnlyHome, { recursive: true, force: true });
	assert.equal(result.status, 0, `unwritable agent dir handled without throwing: ${result.stderr}`);
	console.log("PASS unwritable directory: reported through the UI, not thrown");
}

console.log("classifier-model config battery: ALL PASS");
