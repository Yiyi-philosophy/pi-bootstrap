#!/usr/bin/env node
// M2/M3: the suite must not be able to write a production Pi directory, and a
// component that is not at the pinned version must SKIP, never PASS.
//
// Checked here without needing a real Pi:
//   * scripts/tests/lib.sh refuses a HOME outside TMPDIR (require_scratch_home);
//   * test-classifier-config.mjs refuses a PI_CODING_AGENT_DIR outside its
//     scratch HOME instead of writing the user's permission-modes.json;
//   * test-default-stack.mjs never writes the directory it is pointed at, and
//     reports SKIP (exit 77) for a stack whose versions do not match.
//
// The version gate itself is exercised on a real environment by run-all.sh
// (each real-runtime test now calls skipUnlessPi/skipUnlessPackage, which
// compare exactly).
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "pi-bootstrap-isolation."));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));

function run(command, args, env) {
	return spawnSync(command, args, { encoding: "utf8", env: { ...process.env, ...env } });
}

// --- 1. lib.sh refuses a non-scratch HOME ---------------------------------
{
	const tmpRoot = path.join(scratch, "tmp");
	const home = path.join(scratch, "home");
	fs.mkdirSync(tmpRoot, { recursive: true });
	fs.mkdirSync(home, { recursive: true });
	const probe = path.join(scratch, "guard-probe.sh");
	fs.writeFileSync(
		probe,
		[
			"#!/usr/bin/env bash",
			`source ${JSON.stringify(path.join(here, "lib.sh"))}`,
			"require_scratch_home",
			"echo REACHED",
			"",
		].join("\n"),
	);
	fs.chmodSync(probe, 0o755);

	// The developer's real home is what the guard must reject: handing the suite
	// the real HOME is exactly the M2 accident.
	const realHome = os.userInfo().homedir;
	const refused = run("bash", [probe], { HOME: realHome, TMPDIR: tmpRoot });
	assert.notEqual(refused.status, 0, "the real HOME must be refused");
	assert.match(refused.stderr, /refusing to run with HOME/, `refusal is explicit: ${refused.stderr}`);
	assert.doesNotMatch(refused.stdout, /REACHED/, "the run stopped at the guard");

	const allowed = run("bash", [probe], { HOME: home, TMPDIR: tmpRoot });
	assert.equal(allowed.status, 0, `a scratch HOME is allowed: ${allowed.stderr}`);
	assert.match(allowed.stdout, /REACHED/, "the run continued under a scratch HOME");

	// An agent directory outside the scratch HOME is refused too, which is the
	// exact mistake M2 describes (PI_BOOTSTRAP_AGENT_DIR pointing at ~/.pi).
	const outside = run("bash", [probe], {
		HOME: home,
		TMPDIR: tmpRoot,
		PI_CODING_AGENT_DIR: path.join(realHome, ".pi/agent"),
	});
	assert.notEqual(outside.status, 0, "an agent dir outside HOME must be refused");
	assert.match(outside.stderr, /is outside HOME/, `refusal is explicit: ${outside.stderr}`);

	// A symlink escape is refused as well: HOME or the agent directory can look
	// like a scratch path textually while resolving to the real home. Both
	// cases below would pass a plain string-prefix check.
	const linkedHome = path.join(scratch, "linked-home");
	fs.symlinkSync(realHome, linkedHome);
	const symlinkedHome = run("bash", [probe], { HOME: linkedHome, TMPDIR: tmpRoot });
	assert.notEqual(symlinkedHome.status, 0, "a HOME that is a symlink to the real home must be refused");
	assert.match(symlinkedHome.stderr, /resolves to/, `symlink refusal is explicit: ${symlinkedHome.stderr}`);

	const linkedAgent = path.join(home, "agent-link");
	fs.symlinkSync(path.join(realHome, ".pi/agent"), linkedAgent);
	const escapingAgent = run("bash", [probe], { HOME: home, TMPDIR: tmpRoot, PI_CODING_AGENT_DIR: linkedAgent });
	assert.notEqual(escapingAgent.status, 0, "an agent dir that symlinks outside HOME must be refused");
	assert.match(escapingAgent.stderr, /is outside HOME/, `symlink refusal is explicit: ${escapingAgent.stderr}`);
	console.log("PASS isolation: lib.sh refuses a non-scratch HOME and an agent dir outside it");
	console.log("PASS isolation: lib.sh refuses symlink escapes for HOME and for the agent directory");
}

// --- 2. the classifier battery refuses a production agent directory --------
{
	const result = run(
		process.execPath,
		[path.join(here, "test-classifier-config.mjs")],
		{
			HOME: scratch,
			TMPDIR: scratch,
			PI_CODING_AGENT_DIR: path.join(repo, ".pi/agent"),
		},
	);
	assert.notEqual(result.status, 0, "the battery must refuse an agent dir outside its scratch HOME");
	assert.match(result.stderr, /refusing to run: agent dir .* is outside/, `refusal is explicit: ${result.stderr}`);
	console.log("PASS isolation: classifier config battery refuses PI_CODING_AGENT_DIR outside its scratch HOME");
}

// --- 3. default-stack never writes the directory it is given --------------
{
	const agent = path.join(scratch, "mismatched-agent");
	const btw = path.join(agent, "npm/node_modules/@narumitw/pi-btw");
	fs.mkdirSync(path.join(btw, "dist"), { recursive: true });
	fs.writeFileSync(path.join(btw, "package.json"), JSON.stringify({ name: "@narumitw/pi-btw", version: "0.9.9" }));
	fs.writeFileSync(path.join(btw, "dist/index.ts"), "export default function () {}\n");
	fs.writeFileSync(path.join(agent, "settings.json"), '{"packages":[]}\n');
	const before = fs.readFileSync(path.join(btw, "package.json"), "utf8");
	const result = run(process.execPath, [path.join(here, "test-default-stack.mjs")], {
		HOME: scratch,
		TMPDIR: scratch,
		PI_BOOTSTRAP_AGENT_DIR: agent,
		PI_BOOTSTRAP_PI_PACKAGE: path.join(scratch, "no-such-pi"),
	});
	const output = `${result.stdout}${result.stderr}`;
	assert.equal(result.status, 77, `expected SKIP (77), got ${result.status}: ${output}`);
	assert.match(output, /^SKIP default stack load:/m, `SKIP is reported: ${output}`);
	assert.equal(fs.readFileSync(path.join(btw, "package.json"), "utf8"), before, "the caller's agent dir was not modified");
	assert.deepEqual(fs.readdirSync(agent).sort(), ["npm", "settings.json"], "nothing was added to the caller's agent dir");
	console.log("PASS isolation: default stack SKIPs a mismatched stack and never writes the given directory");
}

console.log("isolation and version-matrix guards: ALL PASS");
