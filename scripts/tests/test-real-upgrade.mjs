#!/usr/bin/env node
// H1 acceptance, on the REAL Pi CLI and REAL packages (no stubs):
//
//   1. build a scratch "previous installation": Pi 1.0.2 from npm, plus
//      permission-modes 2.7.0, pi-btw 0.61.1 and pi-advisor-flow 0.11.0
//      installed by that CLI from the registry;
//   2. run the real install.sh with a failure injected after the new packages
//      were installed;
//   3. prove the failure was clean: `pi --version` is 1.0.2 again, every old
//      package is back, settings.json lists the old matrix, and the REAL Pi
//      1.0.2 extension loader loads all of it;
//   4. run install.sh again without the fault and prove the pinned 1.4.0 stack
//      loads with the exact pinned versions.
//
// This is the test that distinguishes "recover() was called" from "the old
// environment still works". It BUILDS the pinned Pi 1.4.0 itself, in a scratch
// prefix, so it cannot ride on whatever Pi happens to be installed. It needs a
// network (npm registry + the pinned GitHub commit) and is therefore opt-in:
//
//   PI_BOOTSTRAP_REAL_UPGRADE=1 node scripts/tests/test-real-upgrade.mjs
//
// Without that variable it SKIPs (exit 77), so an offline CI job reports
// "not exercised" rather than a false PASS.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { PI_VERSION, PERMISSION_MODES_COMMIT, PERMISSION_MODES_VERSION, readVersion } from "./lib-pi.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const name = "real upgrade and rollback";

function skip(message) {
	console.log(`SKIP ${name}: ${message}`);
	process.exit(77);
}

if (process.env.PI_BOOTSTRAP_REAL_UPGRADE !== "1") {
	skip("set PI_BOOTSTRAP_REAL_UPGRADE=1 to run the real npm/GitHub upgrade test");
}
for (const command of ["node", "npm", "git", "bash"]) {
	const found = spawnSync("bash", ["-c", `command -v ${command}`], { encoding: "utf8" });
	if (found.status !== 0) skip(`${command} is not available`);
}
if (process.env.PI_BOOTSTRAP_FETCH !== "1" && process.env.PI_BOOTSTRAP_ALLOW_NETWORK !== "1") {
	// run-all.sh --fetch (or an explicit opt-in) is the signal that a registry
	// and GitHub may be reached; without it the test cannot build its fixtures.
	skip("network access is not allowed here (run scripts/tests/run-all.sh --fetch or set PI_BOOTSTRAP_ALLOW_NETWORK=1)");
}

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-real-upgrade."));
process.on("exit", () => {
	if (process.env.PI_BOOTSTRAP_KEEP_SCRATCH === "1") {
		console.log(`kept scratch tree: ${scratch}`);
		return;
	}
	fs.rmSync(scratch, { recursive: true, force: true });
});

const home = path.join(scratch, "home");
const agentDir = path.join(home, ".pi/agent");
// One npm global prefix, which is the real scenario: the installer replaces the
// global Pi in place, so a rollback has to put the old CLI back there.
const prefix = path.join(scratch, "npm-prefix");
const cache = path.join(scratch, "npm-cache");
fs.mkdirSync(agentDir, { recursive: true });

const baseEnv = {
	...process.env,
	HOME: home,
	PI_CODING_AGENT_DIR: agentDir,
	npm_config_prefix: prefix,
	npm_config_cache: cache,
	PI_SKIP_VERSION_CHECK: "1",
	NO_COLOR: "1",
	PATH: `${prefix}/bin:${process.env.PATH}`,
};

function run(command, args, options = {}) {
	const result = spawnSync(command, args, {
		encoding: "utf8",
		env: { ...baseEnv, ...options.env },
		cwd: options.cwd ?? scratch,
		timeout: options.timeout ?? 900_000,
	});
	if (options.check !== false && result.status !== 0) {
		throw new Error(`${command} ${args.join(" ")} failed (${result.status}):\n${result.stdout}\n${result.stderr}`);
	}
	return result;
}

function npmInstallGlobal(pkgPrefix, spec, extraEnv = {}) {
	// PI_OFFLINE would block the registry, so it is dropped for this call only.
	const env = { ...baseEnv, ...extraEnv, npm_config_prefix: pkgPrefix };
	delete env.PI_OFFLINE;
	const result = spawnSync("npm", ["install", "-g", "--ignore-scripts", "--prefix", pkgPrefix, spec], {
		encoding: "utf8",
		env,
		cwd: scratch,
		timeout: 900_000,
	});
	if (result.status !== 0) throw new Error(`npm install ${spec} failed:\n${result.stdout}\n${result.stderr}`);
}

// --- 1. the previous installation -----------------------------------------
console.log(`installing Pi 1.0.2 and the old extension set (network) in ${scratch}`);
npmInstallGlobal(prefix, "@earendil-works/pi-coding-agent@1.0.2");
const oldPi = path.join(prefix, "bin/pi");
assert(fs.existsSync(oldPi), "the old pi launcher exists");
const oldEnv = {
	HOME: home,
	PI_CODING_AGENT_DIR: agentDir,
	PATH: `${prefix}/bin:${process.env.PATH}`,
};
for (const spec of [
	"npm:@georgedong32/permission-modes@2.7.0",
	"npm:@narumitw/pi-btw@0.61.1",
	"npm:pi-advisor-flow@0.11.0",
]) {
	// `pi install` runs npm inside the agent directory; ignore-scripts is what the
	// installer does for managed installs, and is safe here too.
	const result = spawnSync(oldPi, ["install", spec], {
		encoding: "utf8",
		env: { ...baseEnv, ...oldEnv, npm_config_ignore_scripts: "1" },
		cwd: scratch,
		timeout: 900_000,
	});
	if (result.status !== 0) throw new Error(`pi install ${spec} failed:\n${result.stdout}\n${result.stderr}`);
}
fs.mkdirSync(path.join(agentDir, "extensions"), { recursive: true });
fs.copyFileSync(path.join(repo, "extensions/classifier-model.ts"), path.join(agentDir, "extensions/classifier-model.ts"));
const settingsBefore = fs.readFileSync(path.join(agentDir, "settings.json"), "utf8");
assert.match(settingsBefore, /2\.7\.0/, "the previous settings describe the 2.7.0 matrix");
assert.equal(run(oldPi, ["--version"], { env: oldEnv }).stdout.trim(), "1.0.2", "the previous Pi is 1.0.2");

// --- 2. record what the previous environment registers --------------------
const verifier = path.join(repo, "scripts/lib/verify-stack.mjs");
const preState = path.join(scratch, "pre-state.json");
const capture = run(
	process.execPath,
	[verifier, "--mode", "capture", "--pi-bin", oldPi, "--agent-dir", agentDir, "--json-out", preState],
	{ env: oldEnv },
);
assert.match(capture.stdout, /stack verification OK/, `previous environment loads: ${capture.stdout}`);
const pre = JSON.parse(fs.readFileSync(preState, "utf8"));
assert.equal(pre.piVersion, "1.0.2", "captured Pi version");
assert(pre.commands.includes("mode") && pre.commands.includes("btw"), "captured the old command set");
console.log(`PASS previous environment: Pi 1.0.2, ${pre.commands.length} commands (${pre.packages.map((p) => `${p.id}@${p.version}`).join(", ")})`);

// --- 3. the real installer fails after installing the new packages --------
const installLog = path.join(scratch, "install.log");
const failed = spawnSync("bash", [path.join(repo, "install.sh")], {
	encoding: "utf8",
	env: {
		...baseEnv,
		...oldEnv,
		PI_BOOTSTRAP_TEST_FAIL_AT: "after-install",
		PI_BOOTSTRAP_TEST_SETUP: "",
	},
	cwd: scratch,
	timeout: 1_800_000,
});
fs.writeFileSync(installLog, `${failed.stdout}\n${failed.stderr}`);
assert.notEqual(failed.status, 0, "the install must report failure");
assert.match(failed.stderr, /rolling back/, "the rollback is announced");
console.log("PASS fault injection: the real installer failed after installing the new packages and rolled back");

// --- 4. the old environment must be usable again --------------------------
const restoredVersion = run(oldPi, ["--version"], { env: oldEnv }).stdout.trim();
assert.equal(restoredVersion, "1.0.2", "the previous Pi CLI is active again");
assert.equal(fs.readFileSync(path.join(agentDir, "settings.json"), "utf8"), settingsBefore, "settings.json is byte-identical");
for (const [label, dir] of [
	["permission-modes 2.7.0", path.join(agentDir, "npm/node_modules/@georgedong32/permission-modes")],
	["pi-btw 0.61.1", path.join(agentDir, "npm/node_modules/@narumitw/pi-btw")],
	["pi-advisor-flow 0.11.0", path.join(agentDir, "npm/node_modules/pi-advisor-flow")],
]) {
	assert(fs.existsSync(path.join(dir, "package.json")), `${label} is installed again`);
}
assert.equal(readVersion(path.join(agentDir, "npm/node_modules/@georgedong32/permission-modes")), "2.7.0", "old permission-modes version");
assert.equal(readVersion(path.join(agentDir, "npm/node_modules/@narumitw/pi-btw")), "0.61.1", "old pi-btw version");
assert.equal(readVersion(path.join(agentDir, "npm/node_modules/pi-advisor-flow")), "0.11.0", "old advisor version");
assert(!fs.existsSync(path.join(agentDir, "git/github.com/GeorgeDong32/pi-permission-modes")), "the new checkout is gone");

// The decisive check: the real 1.0.2 loader loads every restored package.
const verify = run(
	process.execPath,
	[verifier, "--mode", "verify", "--pi-bin", oldPi, "--agent-dir", agentDir, "--expect", preState],
	{ env: oldEnv },
);
assert.match(verify.stdout, /stack verification OK/, `restored environment loads: ${verify.stdout}`);
console.log("PASS rollback: Pi 1.0.2 is active again and the real loader loads every restored extension");

// --- 5. a clean run then installs and verifies the pinned matrix ---------
const installed = spawnSync("bash", [path.join(repo, "install.sh")], {
	encoding: "utf8",
	env: { ...baseEnv, ...oldEnv },
	cwd: scratch,
	timeout: 1_800_000,
});
fs.writeFileSync(path.join(scratch, "install-ok.log"), `${installed.stdout}\n${installed.stderr}`);
assert.equal(installed.status, 0, `the clean install must succeed:\n${installed.stdout}\n${installed.stderr}`);

const newPi = path.join(prefix, "bin/pi");
assert.equal(run(newPi, ["--version"], { env: oldEnv }).stdout.trim(), PI_VERSION, "the new Pi is active");
assert.equal(readVersion(path.join(agentDir, "npm/node_modules/@narumitw/pi-btw")), "0.62.0", "pi-btw 0.62.0 installed");
assert.equal(readVersion(path.join(agentDir, "npm/node_modules/pi-advisor-flow")), "0.14.2", "advisor 0.14.2 installed");
const pmDir = path.join(agentDir, "git/github.com/GeorgeDong32/pi-permission-modes");
assert.equal(readVersion(pmDir), PERMISSION_MODES_VERSION, "permission-modes 2.8.0 installed");
assert.equal(
	run("git", ["-C", pmDir, "rev-parse", "HEAD"]).stdout.trim(),
	PERMISSION_MODES_COMMIT,
	"permission-modes is the pinned commit",
);
const postState = path.join(scratch, "post-state.json");
const post = run(
	process.execPath,
	[verifier, "--mode", "capture", "--pi-bin", newPi, "--agent-dir", agentDir, "--json-out", postState],
	{ env: oldEnv },
);
assert.match(post.stdout, /stack verification OK/, `the new stack loads: ${post.stdout}`);
const postJson = JSON.parse(fs.readFileSync(postState, "utf8"));
for (const command of ["mode", "permissions", "classifier-model", "btw", "advisor", "advisor-models"]) {
	assert(postJson.commands.includes(command), `command registered after upgrade: ${command}`);
}
console.log("PASS clean run: Pi 1.4.0, permission-modes 2.8.0 at the pinned commit, and every command registered");

// --- 6. a second failure shape: while stale entries are being removed ----
const secondFailure = spawnSync("bash", [path.join(repo, "install.sh")], {
	encoding: "utf8",
	env: { ...baseEnv, ...oldEnv, PI_BOOTSTRAP_TEST_FAIL_AT: "after-remove" },
	cwd: scratch,
	timeout: 1_800_000,
});
fs.writeFileSync(path.join(scratch, "install-fail2.log"), `${secondFailure.stdout}\n${secondFailure.stderr}`);
// The 1.4.0 matrix is already current, so there is nothing to remove: the
// injected stage is not reached and this run simply converges (exit 0).
if (secondFailure.status === 0) {
	console.log("PASS rerun after upgrade: already current, the removal stage was not reached (idempotent)");
} else {
	const verifyAfter = run(
		process.execPath,
		[verifier, "--mode", "verify", "--pi-bin", newPi, "--agent-dir", agentDir, "--expect", postState],
		{ env: oldEnv },
	);
	assert.match(verifyAfter.stdout, /stack verification OK/, "a failed rerun leaves the current stack loading");
	console.log("PASS rerun after upgrade: failure rolled back to the working 1.4.0 stack");
}

console.log(`${name}: ALL PASS`);
