#!/usr/bin/env node
// RPC smoke test: the REAL Pi CLI starts headless with the pinned
// permission-modes source and this repository's classifier-model extension,
// and reports both commands through `get_commands` with no load errors.
//
// Uses Pi's documented `--mode rpc` protocol; no provider request is made (the
// fake provider only backs Pi's model selection) and no credential is read.
// Skips (exit 77) when Pi 1.4.0 or the permission-modes source is unavailable.
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { skipUnlessPi, skipUnlessPinnedPermissionModes } from "./lib-pi.mjs";

const pi = skipUnlessPi("RPC smoke");
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const home = process.env.HOME;
assert(home && !home.startsWith("/root"), "HOME must be an isolated scratch directory");
const agentDir = path.join(home, ".pi", "agent");
fs.mkdirSync(agentDir, { recursive: true });
fs.writeFileSync(path.join(agentDir, "auth.json"), "{}");
fs.writeFileSync(path.join(agentDir, "models.json"), JSON.stringify({ providers: {} }, null, 2));

function findPermissionModes() {
	if (process.env.PI_BOOTSTRAP_PM_280) return process.env.PI_BOOTSTRAP_PM_280;
	for (const candidate of [
		path.join(agentDir, "git/github.com/GeorgeDong32/pi-permission-modes"),
		path.join(home, "pi-permission-modes"),
	]) {
		if (fs.existsSync(path.join(candidate, "index.ts"))) return candidate;
	}
	return undefined;
}

const pmSource = findPermissionModes();
if (!pmSource) {
	console.log("SKIP RPC smoke: permission-modes 2.8.0 source not found (set PI_BOOTSTRAP_PM_280)");
	process.exit(77);
}
// Exact provenance (M3).
skipUnlessPinnedPermissionModes("RPC smoke", pmSource);

// Loopback provider so Pi can select a model without any network access.
const server = http.createServer((request, response) => {
	let body = "";
	request.on("data", (chunk) => (body += chunk));
	request.on("end", () => {
		response.writeHead(200, { "Content-Type": "text/event-stream" });
		response.write(
			"data: " + JSON.stringify({ id: "x", object: "chat.completion.chunk", created: 1, model: "smoke", choices: [{ index: 0, delta: { role: "assistant", content: "ok" }, finish_reason: null }] }) + "\n\n",
		);
		response.write("data: " + JSON.stringify({ id: "x", object: "chat.completion.chunk", created: 1, model: "smoke", choices: [{ index: 0, delta: {}, finish_reason: "stop" }] }) + "\n\n");
		response.end("data: [DONE]\n\n");
	});
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

const providerFile = path.join(home, "provider.ts");
fs.writeFileSync(
	providerFile,
	`export default function (pi) {
	pi.registerProvider("smoke", {
		baseUrl: "http://127.0.0.1:${port}/v1",
		apiKey: "smoke-placeholder",
		api: "openai-completions",
		models: [{ id: "smoke", name: "Smoke", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 32768, maxTokens: 1024 }],
	});
}
`,
);

const manifest = JSON.parse(fs.readFileSync(path.join(pi.dir, "package.json"), "utf8"));
const cli = path.join(pi.dir, typeof manifest.bin === "string" ? manifest.bin : manifest.bin.pi);
const child = spawn(
	process.execPath,
	[
		cli,
		"--mode",
		"rpc",
		"--no-session",
		"-e",
		providerFile,
		"-e",
		path.join(pmSource, "index.ts"),
		"-e",
		path.join(repo, "extensions/classifier-model.ts"),
		"--provider",
		"smoke",
		"--model",
		"smoke",
	],
	{
		cwd: home,
		env: { ...process.env, HOME: home, PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: "1", PI_SKIP_VERSION_CHECK: "1", NO_COLOR: "1" },
		stdio: ["pipe", "pipe", "pipe"],
	},
);

const records = [];
let stderr = "";
let buffer = "";
child.stderr.on("data", (chunk) => (stderr += chunk));
child.stdout.on("data", (chunk) => {
	buffer += chunk;
	let index;
	while ((index = buffer.indexOf("\n")) >= 0) {
		const line = buffer.slice(0, index);
		buffer = buffer.slice(index + 1);
		try {
			const record = JSON.parse(line);
			records.push(record);
			// Release any dialog so the process cannot block.
			if (record.type === "extension_ui_request") {
				child.stdin.write(JSON.stringify({ type: "extension_ui_response", id: record.id, cancelled: true }) + "\n");
			}
		} catch {
			// non-JSON diagnostic line
		}
	}
});

function waitFor(predicate, label) {
	return new Promise((resolve, reject) => {
		const deadline = Date.now() + 30000;
		const timer = setInterval(() => {
			if (predicate()) {
				clearInterval(timer);
				resolve();
				return;
			}
			if (child.exitCode !== null || Date.now() > deadline) {
				clearInterval(timer);
				reject(new Error(`timed out waiting for ${label}; exit=${child.exitCode}; stderr=${stderr.slice(0, 400)}; stdout=${buffer.slice(0, 400)}`));
			}
		}, 50);
	});
}

try {
	child.stdin.write(JSON.stringify({ id: "commands", type: "get_commands" }) + "\n");
	await waitFor(() => records.some((record) => record.id === "commands"), "get_commands reply");
	const reply = records.find((record) => record.id === "commands");
	assert(reply.success, `get_commands succeeded: ${JSON.stringify(reply)}`);
	const names = reply.data.commands.map((command) => command.name);
	for (const name of ["classifier-model", "mode", "permissions"]) {
		assert(names.includes(name), `command registered over RPC: ${name} (got ${names.join(", ")})`);
	}
	assert(!/Failed to load extension|error loading/i.test(stderr), `no extension load errors: ${stderr}`);
	console.log(`PASS RPC: Pi ${pi.version} started headless; registered ${names.filter((n) => ["classifier-model", "mode", "permissions"].includes(n)).join(", ")}`);

	for (const [id, message] of [["cm", "/classifier-model"], ["mode", "/mode"]]) {
		child.stdin.write(JSON.stringify({ id, type: "prompt", message }) + "\n");
		await waitFor(() => records.some((record) => record.id === id), `${message} reply`);
		assert(records.find((record) => record.id === id).success, `${message} invocation succeeded`);
	}
	console.log("PASS RPC: /classifier-model and /mode invoke successfully (dialogs cancelled)");
	assert(!/Failed to load extension/i.test(stderr), "still no load errors after command invocations");
} finally {
	child.stdin.end();
	await new Promise((resolve) => {
		if (child.exitCode !== null) {
			resolve();
			return;
		}
		const timer = setTimeout(() => child.kill("SIGTERM"), 5000);
		child.once("exit", () => {
			clearTimeout(timer);
			resolve();
		});
	});
	server.close();
}

console.log("RPC smoke: ALL PASS");
