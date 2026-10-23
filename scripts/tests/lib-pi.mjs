#!/usr/bin/env node
// Resolve the installed Pi Coding Agent package for tests that must run against
// the real runtime (loader, ModelRegistry) rather than a stub.
//
// Order: PI_BOOTSTRAP_PI_PACKAGE (explicit path) -> global npm root.
//
// The resolved version must equal the pinned matrix (M3). "newer than the pin"
// is NOT accepted: these tests assert the exact combination the installer
// ships, and Pi's loader/internal APIs change between releases, so a newer Pi
// would make a PASS mean something the repository never tested. Any mismatch is
// a SKIP with a message naming both versions, never a PASS.
import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Keep in sync with install.sh. scripts/tests/test-version-matrix.sh asserts
// that these values match the installer's pins.
export const PI_VERSION = "1.4.0";
export const PERMISSION_MODES_VERSION = "2.8.0";
export const PERMISSION_MODES_COMMIT = "cf77816f28e102409dddbf8e537e4cf57aa092f0";
export const PI_BTW_VERSION = "0.62.0";
export const PI_ADVISOR_FLOW_VERSION = "0.14.2";
export const MINIMAL_MODE_SHA256 = "040cbc7619b2e903888c8626e2fa55ca5e3f820535dfd1aadcb2060e156a8770";

function readJson(file) {
	try {
		return JSON.parse(readFileSync(file, "utf8"));
	} catch {
		return undefined;
	}
}

export function readVersion(packageDir) {
	return readJson(path.join(packageDir, "package.json"))?.version;
}

// Return { dir, version } or undefined when Pi is not installed anywhere.
export function findPi() {
	const candidates = [];
	if (process.env.PI_BOOTSTRAP_PI_PACKAGE) candidates.push(process.env.PI_BOOTSTRAP_PI_PACKAGE);
	try {
		const globalRoot = execFileSync("npm", ["root", "-g"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
		if (globalRoot) candidates.push(path.join(globalRoot, "@earendil-works/pi-coding-agent"));
	} catch {
		// npm unavailable: rely on an explicit override.
	}
	candidates.push(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../node_modules/@earendil-works/pi-coding-agent"));
	for (const dir of candidates) {
		if (!dir || !existsSync(path.join(dir, "package.json"))) continue;
		const version = readVersion(dir);
		if (version) return { dir, version };
	}
	return undefined;
}

// SKIP (exit 77) unless the real Pi is exactly the pinned version. Returning
// the Pi descriptor keeps the call sites unchanged.
export function skipUnlessPi(testName) {
	const pi = findPi();
	if (!pi) {
		console.log(`SKIP ${testName}: Pi Coding Agent is not installed (set PI_BOOTSTRAP_PI_PACKAGE)`);
		process.exit(77);
	}
	if (pi.version !== PI_VERSION) {
		console.log(
			`SKIP ${testName}: Pi ${pi.version} at ${pi.dir} is not the pinned ${PI_VERSION} (set PI_BOOTSTRAP_PI_PACKAGE to the pinned install)`,
		);
		process.exit(77);
	}
	return pi;
}

// Locate a package directory as npm would, by walking node_modules upward from
// the Pi package. Package "exports" hides package.json, so resolve paths by
// probing the filesystem instead of require.resolve("pkg/package.json").
export function findPackageDir(startDir, name) {
	let current = path.resolve(startDir);
	for (;;) {
		const candidate = path.join(current, "node_modules", name);
		if (existsSync(path.join(candidate, "package.json"))) return candidate;
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

// Resolve a package that Pi itself depends on (for example pi-ai), whether npm
// nested it under Pi or hoisted it to a shared node_modules.
export function requireFromPi(piDir, name) {
	const dir = findPackageDir(piDir, name);
	if (!dir) throw new Error(`${name} is not installed next to ${piDir}`);
	return dir;
}

// Return SKIP (exit 77) unless an installed directory is exactly `expected`.
// The message names the installed version, so a wrong matrix is never mistaken
// for an exercised test.
export function skipUnlessPackage(testName, label, dir, expected) {
	if (!dir || !existsSync(path.join(dir, "package.json"))) {
		console.log(`SKIP ${testName}: ${label} is not installed at ${dir ?? "(unknown path)"}`);
		process.exit(77);
	}
	const version = readVersion(dir);
	if (version !== expected) {
		console.log(`SKIP ${testName}: ${label} ${version ?? "unknown"} at ${dir} is not the pinned ${expected}`);
		process.exit(77);
	}
	return { dir, version };
}

// Return the git HEAD of a checkout, or undefined.
export function gitHead(dir) {
	try {
		return execFileSync("git", ["-C", dir, "rev-parse", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
	} catch {
		return undefined;
	}
}

// Return SKIP (exit 77) unless DIR is a git checkout of the pinned
// permission-modes commit whose package.json reports the pinned version. 2.8.0
// was never published to npm, so its provenance is the commit itself; a
// different 2.8.0 build must not be reported as the tested snapshot.
export function skipUnlessPinnedPermissionModes(testName, dir) {
	if (!dir || !existsSync(path.join(dir, "index.ts"))) {
		console.log(`SKIP ${testName}: permission-modes ${PERMISSION_MODES_VERSION} source not found (set PI_BOOTSTRAP_PM_280)`);
		process.exit(77);
	}
	const version = readVersion(dir);
	if (version !== PERMISSION_MODES_VERSION) {
		console.log(
			`SKIP ${testName}: permission-modes at ${dir} is ${version ?? "unknown"}, the pinned matrix requires ${PERMISSION_MODES_VERSION}`,
		);
		process.exit(77);
	}
	const head = gitHead(dir);
	if (head !== PERMISSION_MODES_COMMIT) {
		console.log(`SKIP ${testName}: ${dir} is at ${head ?? "not a git checkout"}, the pinned commit is ${PERMISSION_MODES_COMMIT}`);
		process.exit(77);
	}
	return { dir, version, head };
}
