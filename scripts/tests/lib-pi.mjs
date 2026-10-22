#!/usr/bin/env node
// Resolve the installed Pi Coding Agent package for tests that must run against
// the real runtime (loader, ModelRegistry) rather than a stub.
//
// Order: PI_BOOTSTRAP_PI_PACKAGE (explicit path) -> global npm root.
// The resolved version is checked against the pinned matrix so a stale global
// install cannot silently weaken or invalidate these tests.
import { createRequire } from "node:module";
import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const MINIMUM_VERSION = "1.4.0";

function readVersion(packageDir) {
	try {
		return JSON.parse(readFileSync(path.join(packageDir, "package.json"), "utf8")).version;
	} catch {
		return undefined;
	}
}

function compareVersions(left, right) {
	const a = left.split(".").map(Number);
	const b = right.split(".").map(Number);
	for (let i = 0; i < 3; i += 1) {
		if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) - (b[i] ?? 0);
	}
	return 0;
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

// Print a SKIP line and exit 0 so the suite records "not exercised" instead of
// a false pass. Used when the real runtime is unavailable.
export function skipUnlessPi(testName) {
	const pi = findPi();
	if (!pi) {
		console.log(`SKIP ${testName}: Pi Coding Agent is not installed (set PI_BOOTSTRAP_PI_PACKAGE)`);
		process.exit(77);
	}
	if (compareVersions(pi.version, MINIMUM_VERSION) < 0) {
		console.log(`SKIP ${testName}: Pi ${pi.version} is older than the pinned ${MINIMUM_VERSION} (set PI_BOOTSTRAP_PI_PACKAGE)`);
		process.exit(77);
	}
	return pi;
}
