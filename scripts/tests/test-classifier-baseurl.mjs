#!/usr/bin/env node
// Regression for the October 2026 permission-modes classifier baseUrl bug.
//
// Both versions are driven through the SAME real Pi ModelRegistry and the same
// loopback mock server. The mock treats any path other than the auth-resolved
// one as a tripwire, so a version that ignores the per-credential baseUrl is
// caught unambiguously.
//
//   2.7.0 (published npm) must FAIL the resolved-auth case  -> regression proof
//   2.8.0 (pinned source)  must PASS it                     -> fix proof
//
// Fixtures come from the environment, never from this repository's history:
//   PI_BOOTSTRAP_PM_270  path to an installed permission-modes 2.7.0
//   PI_BOOTSTRAP_PM_280  path to the pinned 2.8.0 source checkout
// Each may also be fetched fresh with `--fetch` (npm for 2.7.0, git for 2.8.0)
// into a temporary directory, which keeps the test free of checked-in trees.
import assert from "node:assert/strict";
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import {
	findPi,
	findPackageDir,
	skipUnlessPi,
	skipUnlessPackage,
	skipUnlessPinnedPermissionModes,
} from "./lib-pi.mjs";

const PM_COMMIT = "cf77816f28e102409dddbf8e537e4cf57aa092f0";
const PM_REPO = "https://github.com/GeorgeDong32/pi-permission-modes";
const PM_270_VERSION = "2.7.0";

const pi = skipUnlessPi("classifier baseUrl regression");
const work = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-baseurl."));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));

const fetchMissing = process.env.PI_BOOTSTRAP_FETCH === "1";

function ensurePm270() {
	if (process.env.PI_BOOTSTRAP_PM_270) return process.env.PI_BOOTSTRAP_PM_270;
	const target = path.join(work, "pm270");
	fs.mkdirSync(target, { recursive: true });
	fs.writeFileSync(path.join(target, "package.json"), JSON.stringify({ name: "pm270-fixture", private: true }));
	execFileSync("npm", ["install", "--no-save", "--ignore-scripts", `@georgedong32/permission-modes@${PM_270_VERSION}`], {
		cwd: target,
		stdio: "pipe",
	});
	return path.join(target, "node_modules/@georgedong32/permission-modes");
}

function ensurePm280() {
	if (process.env.PI_BOOTSTRAP_PM_280) return process.env.PI_BOOTSTRAP_PM_280;
	const target = path.join(work, "pm280");
	fs.mkdirSync(target, { recursive: true });
	execFileSync("git", ["clone", "--quiet", PM_REPO, target], { stdio: "pipe" });
	execFileSync("git", ["checkout", "--quiet", PM_COMMIT], { cwd: target, stdio: "pipe" });
	return target;
}

function resolveFixtures() {
	const missing = [];
	if (!process.env.PI_BOOTSTRAP_PM_270) missing.push("permission-modes 2.7.0 (PI_BOOTSTRAP_PM_270)");
	if (!process.env.PI_BOOTSTRAP_PM_280) missing.push("permission-modes 2.8.0 (PI_BOOTSTRAP_PM_280)");
	if (missing.length === 0) return { pm270: process.env.PI_BOOTSTRAP_PM_270, pm280: process.env.PI_BOOTSTRAP_PM_280 };
	if (!fetchMissing) {
		console.log(`SKIP classifier baseUrl regression: missing ${missing.join(", ")}; re-run with --fetch to download them`);
		process.exit(77);
	}
	return { pm270: ensurePm270(), pm280: ensurePm280() };
}

const fixtures = resolveFixtures();
for (const [label, dir] of Object.entries(fixtures)) {
	assert(fs.existsSync(path.join(dir, "classifier-client.ts")), `${label} fixture has classifier-client.ts: ${dir}`);
}
// Exact fixture versions (M3). 2.7.0 is the fixed published control; 2.8.0 has
// no npm release, so it must be the pinned commit.
skipUnlessPackage("classifier baseUrl regression", "permission-modes 2.7.0 control", fixtures.pm270, PM_270_VERSION);
skipUnlessPinnedPermissionModes("classifier baseUrl regression", fixtures.pm280);

// --- fixtures --------------------------------------------------------------
const agentDir = path.join(work, "home/.pi/agent");
fs.mkdirSync(agentDir, { recursive: true });
fs.writeFileSync(path.join(agentDir, "auth.json"), "{}");
fs.writeFileSync(path.join(agentDir, "models.json"), JSON.stringify({ providers: {} }, null, 2));

function sseToolCall(shouldBlock) {
	const chunk = {
		id: "chatcmpl-audit",
		object: "chat.completion.chunk",
		created: 1,
		model: "audit",
		choices: [
			{
				index: 0,
				delta: {
					role: "assistant",
					tool_calls: [
						{
							index: 0,
							id: "audit-call",
							type: "function",
							function: {
								name: "classify_result",
								arguments: JSON.stringify({
									thinking: "audit response",
									shouldBlock,
									reason: shouldBlock ? "audit deny" : "audit allow",
								}),
							},
						},
					],
				},
				finish_reason: null,
			},
		],
	};
	return (
		"data: " + JSON.stringify(chunk) + "\n\n" +
		"data: " + JSON.stringify({ ...chunk, choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }] }) + "\n\n" +
		"data: [DONE]\n\n"
	);
}

const serverState = { shouldBlock: false, mode: "normal" };
const requests = [];
const server = http.createServer(async (request, response) => {
	let body = "";
	for await (const chunk of request) body += chunk;
	let parsed = {};
	try {
		parsed = JSON.parse(body);
	} catch {
		// keep {} so a malformed body is still recorded
	}
	requests.push({
		path: request.url,
		host: request.headers.host,
		authorized: Boolean(request.headers.authorization),
		body: parsed,
	});
	if (serverState.mode === "hang") {
		response.writeHead(200, { "Content-Type": "text/event-stream" });
		return; // never respond: exercises the timeout path
	}
	if (serverState.mode === "garbage") {
		response.writeHead(200, { "Content-Type": "text/event-stream" });
		response.end("data: not-json\n\ndata: [DONE]\n\n");
		return;
	}
	if (serverState.mode === "empty") {
		response.writeHead(200, { "Content-Type": "text/event-stream" });
		response.end("data: [DONE]\n\n");
		return;
	}
	if (request.url !== "/effective/v1/chat/completions") {
		response.writeHead(400, { "Content-Type": "application/json" });
		response.end(JSON.stringify({ error: { message: "Classifier ignored the resolved auth.baseUrl" } }));
		return;
	}
	response.writeHead(200, { "Content-Type": "text/event-stream" });
	response.end(sseToolCall(serverState.shouldBlock));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const baseEffective = `http://127.0.0.1:${port}/effective/v1`; // auth-resolved baseUrl
const baseCatalog = `http://127.0.0.1:${port}/v1`; // provider catalog baseUrl

// --- real ModelRegistry ----------------------------------------------------
process.env.PI_OFFLINE = "1";
const { ModelRegistry } = await import(pathToFileURL(path.join(pi.dir, "dist/core/model-registry.js")).href);
const { ModelRuntime } = await import(pathToFileURL(path.join(pi.dir, "dist/core/model-runtime.js")).href);
const piAiDir = findPackageDir(pi.dir, "@earendil-works/pi-ai");
assert(piAiDir, "pi-ai is installed next to Pi");
const openaiCompletions = await import(pathToFileURL(path.join(piAiDir, "dist/api/openai-completions.js")).href);

const runtime = await ModelRuntime.create({
	authPath: path.join(agentDir, "auth.json"),
	modelsPath: path.join(agentDir, "models.json"),
	refreshOnCreate: false,
});
const registry = new ModelRegistry(runtime);
// A native provider whose ApiKeyAuth.resolve() returns a per-credential
// baseUrl (the documented GitHub-Copilot-style case) while the catalog model
// carries a different baseUrl. PuBlic pi-ai interfaces only.
registry.registerProvider({
	id: "audit",
	name: "Audit",
	baseUrl: baseCatalog,
	api: "openai-completions",
	auth: {
		apiKey: {
			name: "Audit API key",
			resolve: async () => ({
				auth: { apiKey: "audit-placeholder", baseUrl: baseEffective },
				source: "per-credential endpoint",
			}),
		},
	},
	stream: (model, context, options) => openaiCompletions.stream(model, context, options),
	streamSimple: (model, context, options) => openaiCompletions.streamSimple(model, context, options),
	getModels: () => [
		{
			provider: "audit",
			id: "audit",
			api: "openai-completions",
			baseUrl: baseCatalog,
			name: "Audit Model",
			reasoning: false,
			input: ["text"],
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			contextWindow: 32768,
			maxTokens: 2048,
		},
	],
});
const model = registry.find("audit", "audit");
assert(model, "the fixture model is registered");
const auth = await registry.getApiKeyAndHeaders(model);
assert.equal(auth.ok, true, "registry resolved credentials");
assert.equal(auth.baseUrl, baseEffective, "resolved auth carries the per-credential baseUrl");
assert.notEqual(model.baseUrl, baseEffective, "regression requires model.baseUrl to differ from auth.baseUrl");
console.log(`SANITY model.baseUrl=${model.baseUrl} auth.baseUrl=${auth.baseUrl} (divergent, as required)`);

// permission-modes imports bare Pi packages; jiti aliases resolve them to Pi.
const jitiFactory = createRequire(path.join(pi.dir, "package.json"))("jiti");
const aliases = {
	"@earendil-works/pi-ai/compat": path.join(piAiDir, "dist/compat.js"),
	"@earendil-works/pi-ai": path.join(piAiDir, "dist/index.js"),
	"@earendil-works/pi-coding-agent": path.join(pi.dir, "dist/index.js"),
};
function loadClassifierClient(dir) {
	const jiti = jitiFactory.createJiti(pathToFileURL(import.meta.url).href, { moduleCache: false, alias: aliases });
	return jiti.import(path.join(dir, "classifier-client.ts"));
}

const session = { cwd: work, mode: "auto", branch: [] };
const pending = (command) => ({ name: "bash", input: { command } });

// --- 2.7.0 must reproduce the October failure -----------------------------
{
	const { classifyToolCall } = await loadClassifierClient(fixtures.pm270);
	const before = requests.length;
	let verdict;
	let thrown;
	try {
		verdict = await classifyToolCall({
			modelRef: "audit/audit",
			session,
			timeoutMs: 4000,
			registry,
			pendingTool: pending("regression-probe-v270"),
		});
	} catch (error) {
		thrown = error.message;
	}
	const seen = requests.slice(before);
	const misrouted = seen.filter((request) => request.path !== "/effective/v1/chat/completions");
	assert.ok(misrouted.length > 0, "2.7.0 must request the catalog baseUrl, ignoring the resolved one");
	if (verdict) assert.notEqual(verdict.allow, true, "2.7.0 must not allow through the misrouted request");
	requests.length = 0;
	console.log(
		`PASS 2.7.0 reproduces the bug: misrouted to ${misrouted[0].path}` +
			(thrown ? ` -> classify threw: ${thrown.slice(0, 70)}` : ` -> verdict.allow=${verdict.allow}`),
	);
}

// --- 2.8.0 must honor the resolved baseUrl, allow, and deny ---------------
const client280 = await loadClassifierClient(fixtures.pm280);
{
	const { classifyToolCall } = client280;
	const before = requests.length;
	for (const shouldBlock of [false, true]) {
		serverState.shouldBlock = shouldBlock;
		const verdict = await classifyToolCall({
			modelRef: "audit/audit",
			session,
			timeoutMs: 4000,
			registry,
			pendingTool: pending(shouldBlock ? "regression-deny-v280" : "regression-allow-v280"),
		});
		assert.equal(verdict.allow, !shouldBlock, `2.8.0 verdict mirrors shouldBlock=${shouldBlock}`);
		assert.equal(verdict.reason, shouldBlock ? "audit deny" : "audit allow", "reason is passed through");
	}
	const seen = requests.slice(before);
	assert.equal(seen.length, 2, "exactly one classifier request per call");
	for (const request of seen) {
		assert.equal(request.path, "/effective/v1/chat/completions", "2.8.0 posts to the resolved auth baseUrl");
		assert.equal(request.authorized, true, "the credential header goes to the resolved host");
		assert.equal(request.host, `127.0.0.1:${port}`, "no other host received the request");
		assert.equal(request.body.tool_choice?.function?.name, "classify_result", "tool choice is forced");
		assert.deepEqual(
			Object.keys(request.body.tools[0].function.parameters.properties).sort(),
			["reason", "shouldBlock", "thinking"],
			"the classify_result schema is intact",
		);
	}
	requests.length = 0;
	console.log("PASS 2.8.0 via ModelRegistry: resolved baseUrl honored, allow+deny, schema, forced tool choice, credential");
}

// --- transport faults must never become a silent allow -------------------
{
	const { classifyToolCall } = client280;
	for (const [mode, label] of [["garbage", "malformed JSON"], ["empty", "empty stream"], ["hang", "timeout"]]) {
		serverState.mode = mode;
		const before = requests.length;
		let verdict;
		let thrown;
		try {
			verdict = await classifyToolCall({
				modelRef: "audit/audit",
				session,
				timeoutMs: 1500,
				registry,
				pendingTool: pending(`fault-${mode}`),
			});
		} catch (error) {
			thrown = error.message;
		}
		const attempts = requests.length - before;
		assert.ok(thrown || verdict?.allow === false, `${label} must not silently allow`);
		assert.equal(attempts, 1, `${label}: one HTTP attempt per call (the SDK layer runs with maxRetries 0)`);
		serverState.mode = "normal";
		requests.length = 0;
		console.log(`PASS 2.8.0 ${label}: no silent allow (${thrown ? "threw" : "fail-closed verdict"}), attempts=1`);
	}
}

server.closeAllConnections();
await new Promise((resolve) => server.close(resolve));
console.log("classifier baseUrl regression: ALL PASS (2.7.0 broken, 2.8.0 fixed)");
