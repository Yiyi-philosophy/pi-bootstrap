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
	// Two refusals are correct here: "outside HOME" when the link target exists
	// and resolves outside the scratch tree, and "does not resolve" when it does
	// not exist (the CI runner has no ~/.pi/agent). Either way the run stopped.
	assert.match(
		escapingAgent.stderr,
		/is outside HOME|symlink that does not resolve/,
		`symlink refusal is explicit: ${escapingAgent.stderr}`,
	);
	assert.doesNotMatch(escapingAgent.stdout, /REACHED/, "the run stopped at the guard");

	// A symlink that does not resolve is not a missing path: it cannot be proven
	// to stay inside the scratch tree, so the guard must fail closed instead of
	// appending it lexically (a dangling link was accepted before this fix).
	const danglingOutside = path.join(scratch, "not-created-yet");
	const danglingHome = path.join(scratch, "dangling-home");
	fs.symlinkSync(danglingOutside, danglingHome);
	const danglingHomeRun = run("bash", [probe], { HOME: danglingHome, TMPDIR: tmpRoot });
	assert.notEqual(danglingHomeRun.status, 0, "a HOME that is a dangling symlink must be refused");
	assert.match(danglingHomeRun.stderr, /does not resolve/, `dangling refusal is explicit: ${danglingHomeRun.stderr}`);
	assert.doesNotMatch(danglingHomeRun.stdout, /REACHED/, "the run stopped at the guard");

	const danglingAgent = path.join(home, "dangling-agent");
	fs.symlinkSync(danglingOutside, danglingAgent);
	const danglingAgentRun = run("bash", [probe], { HOME: home, TMPDIR: tmpRoot, PI_CODING_AGENT_DIR: danglingAgent });
	assert.notEqual(danglingAgentRun.status, 0, "an agent dir that is a dangling symlink must be refused");
	assert.match(danglingAgentRun.stderr, /does not resolve/, `dangling agent refusal is explicit: ${danglingAgentRun.stderr}`);

	const danglingBelowLink = run("bash", [probe], {
		HOME: home,
		TMPDIR: tmpRoot,
		PI_CODING_AGENT_DIR: path.join(danglingAgent, "agent"),
	});
	assert.notEqual(danglingBelowLink.status, 0, "a path below a dangling symlink must be refused");

	const cyclicHome = path.join(scratch, "cyclic-home");
	fs.symlinkSync(cyclicHome, cyclicHome);
	const cyclicRun = run("bash", [probe], { HOME: cyclicHome, TMPDIR: tmpRoot });
	assert.notEqual(cyclicRun.status, 0, "a HOME that is a symlink loop must be refused");
	assert.match(cyclicRun.stderr, /does not resolve/, `cyclic refusal is explicit: ${cyclicRun.stderr}`);
	assert.doesNotMatch(cyclicRun.stdout, /REACHED/, "the run stopped at the guard");

	// A missing path segment used to be appended to the resolved prefix without
	// collapsing "..", so "home/new/../../outside" kept the "home/" prefix and
	// passed the textual check while meaning a directory outside HOME. Built as a
	// string on purpose: path.join() would collapse the ".." and hide the bug.
	const dotDotEscape = run("bash", [probe], {
		HOME: home,
		TMPDIR: tmpRoot,
		PI_CODING_AGENT_DIR: `${home}/new/../../outside`,
	});
	assert.notEqual(dotDotEscape.status, 0, "a missing segment followed by .. must not escape HOME");
	assert.doesNotMatch(dotDotEscape.stdout, /REACHED/, "the run stopped at the guard");
	assert.equal(fs.existsSync(path.join(scratch, "outside")), false, "the guard created nothing outside HOME");

	// H1: the write-through the lexical collapse could not see. The kernel walks
	// a path component by component: it creates the missing "new", applies "..",
	// and only then follows "agent-link" - so the write lands in `outside`, while
	// every lexical interpretation of the path names $HOME/agent-link, which is
	// inside HOME. A prefix check therefore cannot be trusted for any path that
	// contains "..", so such paths are refused outright (fail closed).
	const h1 = path.join(scratch, "h1");
	const h1Home = path.join(h1, "home");
	const h1Outside = path.join(h1, "outside");
	fs.mkdirSync(h1Home, { recursive: true });
	fs.mkdirSync(h1Outside, { recursive: true });
	fs.symlinkSync(h1Outside, path.join(h1Home, "agent-link"));

	// The probe writes only after the guard has accepted, so its filesystem
	// state proves whether the guard's decision matched where a write would go.
	const writeProbe = path.join(scratch, "write-probe.sh");
	fs.writeFileSync(
		writeProbe,
		[
			"#!/usr/bin/env bash",
			`source ${JSON.stringify(path.join(here, "lib.sh"))}`,
			"require_scratch_home",
			'mkdir -p "$PI_CODING_AGENT_DIR"',
			': >"$PI_CODING_AGENT_DIR/written-by-test"',
			"echo REACHED",
			"",
		].join("\n"),
	);
	fs.chmodSync(writeProbe, 0o755);

	const writeThrough = run("bash", [writeProbe], {
		HOME: h1Home,
		TMPDIR: tmpRoot,
		PI_CODING_AGENT_DIR: `${h1Home}/new/../agent-link`,
	});
	assert.notEqual(writeThrough.status, 0, "a missing segment followed by .. and a symlink must be refused");
	assert.match(writeThrough.stderr, /\.\.|does not resolve/, `refusal is explicit: ${writeThrough.stderr}`);
	assert.doesNotMatch(writeThrough.stdout, /REACHED/, "the run stopped before writing");
	assert.deepEqual(fs.readdirSync(h1Outside), [], "nothing was written outside HOME through the symlink");
	assert.equal(fs.existsSync(path.join(h1Home, "new")), false, "the refused run created no intermediate directory");
	assert.equal(fs.existsSync(path.join(h1Home, "written-by-test")), false, "nothing was written inside HOME either");

	// Control: the same link reached without ".." is a plain missing path inside
	// HOME and is still allowed - the refusal is about "..", not about symlinks.
	const control = run("bash", [writeProbe], {
		HOME: h1Home,
		TMPDIR: tmpRoot,
		PI_CODING_AGENT_DIR: path.join(h1Home, "new-agent"),
	});
	assert.equal(control.status, 0, `a plain missing directory inside HOME is still allowed: ${control.stderr}`);
	assert.match(control.stdout, /REACHED/, "the run continued for a plain missing directory");
	assert.equal(fs.existsSync(path.join(h1Home, "new-agent/written-by-test")), true, "the allowed path was written where the guard said it would be");

	// Even a ".." that happens to stay inside HOME is refused: the guard does not
	// try to decide which combinations of ".." and symlinks are safe.
	const dotDotInside = run("bash", [probe], {
		HOME: home,
		TMPDIR: tmpRoot,
		PI_CODING_AGENT_DIR: `${home}/new/../.pi/agent`,
	});
	assert.notEqual(dotDotInside.status, 0, "a path with .. is refused even when it would stay inside HOME");
	assert.doesNotMatch(dotDotInside.stdout, /REACHED/, "the run stopped at the guard");

	assert.equal(fs.existsSync(danglingOutside), false, "the guard created no link target");
	console.log("PASS isolation: lib.sh refuses a non-scratch HOME and an agent dir outside it");
	console.log("PASS isolation: lib.sh refuses symlink escapes for HOME and for the agent directory");
	console.log("PASS isolation: lib.sh fails closed on dangling and cyclic symlinks");
	console.log("PASS isolation: lib.sh refuses any '..' path instead of collapsing it (no write-through)");
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

// --- 2b. the battery refuses a symlink that escapes its scratch HOME ------
// The path as written is inside the scratch HOME, so a string-prefix check
// passes and the battery writes permission-modes.json through the link into a
// directory outside HOME. That is the reproduced failure: HOME/.pi is a
// symlink to a directory outside the scratch tree.
{
	const escapeTarget = path.join(scratch, "escape-target");
	fs.mkdirSync(path.join(escapeTarget, "agent"), { recursive: true });
	fs.writeFileSync(path.join(escapeTarget, "keep.json"), '{"keep":true}\n');
	const before = fs.readdirSync(escapeTarget).sort();

	const escapeHome = path.join(scratch, "escape-home");
	fs.mkdirSync(escapeHome);
	fs.symlinkSync(escapeTarget, path.join(escapeHome, ".pi"));
	// Empty means unset for the battery: it falls back to HOME/.pi/agent, which
	// reaches escapeTarget/agent only through the escaping symlink.
	const escaped = run(process.execPath, [path.join(here, "test-classifier-config.mjs")], {
		HOME: escapeHome,
		TMPDIR: scratch,
		PI_CODING_AGENT_DIR: "",
	});
	assert.notEqual(escaped.status, 0, "a HOME/.pi symlink that escapes the scratch HOME must be refused");
	assert.match(escaped.stderr, /refusing to run: agent dir .* is outside/, `symlink refusal is explicit: ${escaped.stderr}`);
	assert.deepEqual(fs.readdirSync(escapeTarget).sort(), before, "nothing was written through the escaping symlink");

	const danglingTarget = path.join(scratch, "dangling-target");
	const dangling = path.join(scratch, "dangling-agent");
	fs.symlinkSync(danglingTarget, dangling);
	const danglingRun = run(
		process.execPath,
		[path.join(here, "test-classifier-config.mjs")],
		{ HOME: scratch, TMPDIR: scratch, PI_CODING_AGENT_DIR: dangling },
	);
	assert.notEqual(danglingRun.status, 0, "a dangling agent symlink must be refused, not treated as missing");
	assert.match(danglingRun.stderr, /cannot be resolved|dangling symlink/, `dangling refusal is explicit: ${danglingRun.stderr}`);
	assert.equal(fs.existsSync(danglingTarget), false, "the refused run did not create the link target");

	const loopedHome = path.join(scratch, "looped-home");
	fs.symlinkSync(loopedHome, loopedHome);
	const loopedRun = run(
		process.execPath,
		[path.join(here, "test-classifier-config.mjs")],
		{ HOME: loopedHome, TMPDIR: scratch, PI_CODING_AGENT_DIR: path.join(loopedHome, ".pi/agent") },
	);
	assert.notEqual(loopedRun.status, 0, "a HOME that is a symlink loop must be refused");
	console.log("PASS isolation: classifier config battery refuses escaping, dangling and cyclic symlinks");
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
