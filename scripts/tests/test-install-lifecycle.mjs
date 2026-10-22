#!/usr/bin/env node
// F2 evidence: Pi's git package install runs `npm install` inside the checkout
// with lifecycle scripts enabled, and Pi offers no flag to disable them. The
// installer therefore exports npm_config_ignore_scripts=1 for managed installs.
//
// This test proves both halves against the REAL Pi CLI, using a throwaway
// repository served over localhost (no network, no registry, no credentials):
//   1. control run without the variable -> preinstall/postinstall/prepare run;
//   2. installer run with the variable  -> no lifecycle script runs at all.
//
// Skips (exit 77) when Pi 1.4.0 is unavailable.
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { findPi, skipUnlessPi } from "./lib-pi.mjs";

const pi = skipUnlessPi("git install lifecycle isolation");
// Pi's package.json "bin" points at the bundled CLI.
const piManifest = JSON.parse(fs.readFileSync(path.join(pi.dir, "package.json"), "utf8"));
const piBinEntry = typeof piManifest.bin === "string" ? piManifest.bin : piManifest.bin?.pi;
assert(piBinEntry, "Pi package.json declares a bin entry");
const piCli = path.join(pi.dir, piBinEntry);
assert(fs.existsSync(piCli), `Pi CLI entry point found at ${piCli}`);

const work = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-lifecycle."));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));

// --- a package whose lifecycle scripts leave a marker ----------------------
const pkgDir = path.join(work, "pkg");
fs.mkdirSync(pkgDir);
fs.writeFileSync(
	path.join(pkgDir, "package.json"),
	JSON.stringify(
		{
			name: "lifecycle-probe",
			version: "1.0.0",
			scripts: {
				preinstall: "node -e \"require('fs').appendFileSync('lifecycle-marker.txt','preinstall\\n')\"",
				postinstall: "node -e \"require('fs').appendFileSync('lifecycle-marker.txt','postinstall\\n')\"",
				prepare: "node -e \"require('fs').appendFileSync('lifecycle-marker.txt','prepare\\n')\"",
			},
		},
		null,
		2,
	),
);
fs.writeFileSync(path.join(pkgDir, "index.ts"), "export default function () {}\n");

const git = (args, cwd) => execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8" });
git(["init", "--quiet"], pkgDir);
git(["-c", "user.email=test@example.invalid", "-c", "user.name=test", "add", "-A"], pkgDir);
git(["-c", "user.email=test@example.invalid", "-c", "user.name=test", "commit", "--quiet", "-m", "probe"], pkgDir);
git(["tag", "v1"], pkgDir);

// --- dumb-HTTP git server for the bare repository -------------------------
const bareRoot = path.join(work, "srv");
fs.mkdirSync(path.join(bareRoot, "owner"), { recursive: true });
const bareRepo = path.join(bareRoot, "owner", "lifecycle-probe.git");
execFileSync("git", ["init", "--quiet", "--bare", bareRepo]);
git(["remote", "add", "origin", bareRepo], pkgDir);
git(["push", "--quiet", "origin", "HEAD:refs/heads/main", "--tags"], pkgDir);
git(["update-server-info"], bareRepo);

const server = http.createServer((request, response) => {
	const filePath = path.join(bareRoot, decodeURIComponent(request.url.split("?")[0]));
	if (!path.resolve(filePath).startsWith(path.resolve(bareRoot)) || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
		response.writeHead(404);
		response.end("not found");
		return;
	}
	response.writeHead(200);
	response.end(fs.readFileSync(filePath));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const source = `git:http://127.0.0.1:${port}/owner/lifecycle-probe.git@v1`;

// The git server shares this event loop, so the install must run asynchronously
// (a synchronous spawn would deadlock the loopback fetch).
async function installFresh(agentDir, extraEnv) {
	fs.rmSync(agentDir, { recursive: true, force: true });
	fs.mkdirSync(agentDir, { recursive: true });
	const env = { ...process.env, HOME: path.dirname(path.dirname(agentDir)), PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: "1", ...extraEnv };
	delete env.npm_config_ignore_scripts;
	if (extraEnv.npm_config_ignore_scripts) env.npm_config_ignore_scripts = extraEnv.npm_config_ignore_scripts;
	return await new Promise((resolve, reject) => {
		const child = spawn(process.execPath, [piCli, "install", source], { env, cwd: work, stdio: ["ignore", "pipe", "pipe"] });
		let output = "";
		child.stdout.on("data", (chunk) => (output += chunk));
		child.stderr.on("data", (chunk) => (output += chunk));
		child.on("error", reject);
		child.on("exit", (code) => {
			if (code !== 0) {
				reject(new Error(`pi install failed (${code}): ${output}`));
				return;
			}
			resolve(path.join(agentDir, "git", "127.0.0.1", "owner", "lifecycle-probe"));
		});
	});
}

// 1. Control: without the variable, Pi runs the package's lifecycle scripts.
const controlDir = await installFresh(path.join(work, "control/.pi/agent"), {});
const controlMarker = path.join(controlDir, "lifecycle-marker.txt");
assert(fs.existsSync(controlMarker), "control run executed lifecycle scripts (expected: Pi runs them)");
const controlScripts = fs.readFileSync(controlMarker, "utf8").trim().split("\n");
assert.deepEqual(controlScripts.sort(), ["postinstall", "preinstall", "prepare"], "all lifecycle scripts ran");
console.log(`PASS control: Pi's git install ran ${controlScripts.join(", ")} inside the checkout`);

// 2. With npm_config_ignore_scripts=1 (what the installer exports), none run.
const isolatedDir = await installFresh(path.join(work, "isolated/.pi/agent"), { npm_config_ignore_scripts: "1" });
assert(!fs.existsSync(path.join(isolatedDir, "lifecycle-marker.txt")), "no lifecycle script ran with npm_config_ignore_scripts=1");
assert(fs.existsSync(path.join(isolatedDir, "index.ts")), "the package content itself was installed");
console.log("PASS isolated: npm_config_ignore_scripts=1 suppresses every lifecycle script");

server.close();
console.log("git install lifecycle isolation: ALL PASS");
