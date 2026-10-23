#!/usr/bin/env node
// Load the managed stack through the REAL Pi extension loader.
//
// The installer embeds this file (see install.sh, VERIFY_STACK_JS) so that a
// `curl | bash` install can verify its own result without a checkout. It is
// used in two ways:
//
//   capture  before a mutation: record the Pi version and the commands the
//            current installation actually registers.
//   verify   after a rollback (or at the end of a successful install): prove
//            that Pi and the managed packages still load and that the recorded
//            commands are registered again.
//
// Only packages this bootstrap manages are loaded, plus the two extension files
// it writes. Unrelated user packages are never executed by this check.
//
// Paired copy: the same source lives in scripts/lib/verify-stack.mjs;
// scripts/check-embedded-extension.sh keeps the two byte-identical.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const PI_PACKAGE = "@earendil-works/pi-coding-agent";

// Identities this bootstrap manages. Mirrors managed_spec() in install.sh.
const MANAGED = [
	"npm:@narumitw/pi-btw",
	"npm:pi-advisor-flow",
	"npm:@georgedong32/permission-modes",
	"git:github.com/GeorgeDong32/pi-permission-modes",
];

const EXTENSION_FILES = ["classifier-model.ts", "minimal-mode.ts"];

function usage(message) {
	if (message) console.error(message);
	console.error(
		"usage: verify-stack.mjs --pi-bin <path> --agent-dir <dir> [--mode capture|verify] [--expect <file>] [--json-out <file>] [--require-command <name>]",
	);
	process.exit(2);
}

function parseArgs(argv) {
	const options = { mode: "capture", expectFrom: undefined, jsonOut: undefined, requireCommands: [] };
	for (let i = 0; i < argv.length; i += 1) {
		const flag = argv[i];
		const value = argv[i + 1];
		switch (flag) {
			case "--mode":
				if (value !== "capture" && value !== "verify") usage(`--mode must be capture or verify, got ${value}`);
				options.mode = value;
				i += 1;
				break;
			case "--pi-bin":
				options.piBin = value;
				i += 1;
				break;
			case "--agent-dir":
				options.agentDir = value;
				i += 1;
				break;
			case "--expect":
				options.mode = "verify";
				options.expectFrom = value;
				i += 1;
				break;
			case "--require-command":
				if (!value) usage("--require-command needs a command name");
				options.requireCommands.push(value);
				i += 1;
				break;
			case "--json-out":
				options.jsonOut = value;
				i += 1;
				break;
			default:
				usage(`unknown argument: ${flag}`);
		}
	}
	if (!options.piBin || !options.agentDir) usage("--pi-bin and --agent-dir are required");
	return options;
}

// Resolve the Pi package directory from the CLI path npm created for it. The
// bin entry is a symlink into the package, so walk up until the manifest that
// belongs to this package is found.
function resolvePiPackage(piBin) {
	let current;
	try {
		current = fs.realpathSync(piBin);
	} catch {
		return undefined;
	}
	if (fs.statSync(current).isDirectory()) current = path.join(current, "package.json");
	for (;;) {
		const manifestPath = path.join(current, "package.json");
		if (fs.existsSync(manifestPath)) {
			try {
				const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
				if (manifest.name === PI_PACKAGE) return { dir: current, version: manifest.version, manifest };
			} catch {
				// unreadable manifest: keep walking
			}
		}
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function identity(source) {
	if (typeof source !== "string" || source.length === 0) return undefined;
	if (source.startsWith("npm:")) {
		const match = source.slice(4).trim().match(/^(@?[^@]+(?:\/[^@]+)?)(?:@(.+))?$/);
		return match && match[1] ? `npm:${match[1]}` : undefined;
	}
	let url = source.startsWith("git:") ? source.slice(4).trim() : source;
	let host;
	let packagePath;
	const scp = url.match(/^git@([^:]+):(.+)$/);
	if (scp) {
		host = scp[1];
		packagePath = scp[2];
	} else if (/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) {
		try {
			const parsed = new URL(url);
			host = parsed.hostname;
			packagePath = parsed.pathname.replace(/^\/+/, "");
		} catch {
			return undefined;
		}
	} else {
		const slash = url.indexOf("/");
		if (slash < 0) return undefined;
		host = url.slice(0, slash);
		packagePath = url.slice(slash + 1);
		if (!host.includes(".") && host !== "localhost") return undefined;
	}
	const separator = packagePath.search(/[@#]/);
	if (separator >= 0) packagePath = packagePath.slice(0, separator);
	packagePath = packagePath.replace(/^\/+/, "").replace(/\.git$/, "");
	if (!host || !packagePath) return undefined;
	return `git:${host}/${packagePath}`;
}

function installPath(agentDir, id) {
	if (id.startsWith("npm:")) return path.join(agentDir, "npm", "node_modules", id.slice(4));
	return path.join(agentDir, "git", id.slice(4));
}

function readJson(file) {
	try {
		return JSON.parse(fs.readFileSync(file, "utf8"));
	} catch {
		return undefined;
	}
}

// Entry points declared by a package manifest ("pi.extensions"), else index.ts
// / index.js, matching Pi's own resolveExtensionEntries().
function packageEntries(dir) {
	const manifest = readJson(path.join(dir, "package.json"));
	const declared = manifest?.pi?.extensions;
	if (Array.isArray(declared) && declared.length > 0) return declared.map((entry) => path.join(dir, entry));
	for (const candidate of ["index.ts", "index.js"]) {
		const full = path.join(dir, candidate);
		if (fs.existsSync(full)) return [full];
	}
	return [];
}

function describeSource(agentDir, id) {
	const dir = installPath(agentDir, id);
	const manifest = readJson(path.join(dir, "package.json"));
	const info = { id, path: dir, version: manifest?.version, present: fs.existsSync(dir) };
	if (manifest?.name) info.name = manifest.name;
	return info;
}

const options = parseArgs(process.argv.slice(2));
const pi = resolvePiPackage(options.piBin);
if (!pi) {
	const payload = {
		ok: true,
		skipped: true,
		reason: `could not resolve the ${PI_PACKAGE} package from ${options.piBin}`,
	};
	if (options.jsonOut) fs.writeFileSync(options.jsonOut, `${JSON.stringify(payload, null, 2)}\n`);
	console.log(`SKIP stack verification: ${payload.reason}`);
	// 3 = "nothing could be verified". Distinct from PASS (0) so a caller can
	// never mistake an unproven environment for a working one.
	process.exit(3);
}

const agentDir = path.resolve(options.agentDir);
const settings = readJson(path.join(agentDir, "settings.json")) ?? {};
const configured = new Map();
for (const entry of Array.isArray(settings.packages) ? settings.packages : []) {
	const source = typeof entry === "string" ? entry : entry && entry.source;
	const id = identity(source);
	if (id && MANAGED.includes(id) && !configured.has(id)) configured.set(id, source);
}

const packages = [];
const entryFiles = [];
for (const [id, source] of configured) {
	const info = describeSource(agentDir, id);
	info.source = source;
	if (info.present) {
		const entries = packageEntries(info.path);
		info.entries = entries;
		if (entries.length === 0) info.error = "no extension entry point";
		for (const entry of entries) entryFiles.push(entry);
	} else {
		info.error = "installed directory is missing";
	}
	packages.push(info);
}

const extensions = [];
for (const file of EXTENSION_FILES) {
	const full = path.join(agentDir, "extensions", file);
	if (fs.existsSync(full)) {
		extensions.push(full);
		entryFiles.push(full);
	}
}

const workDir = fs.mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "pi-bootstrap-verify."));
process.env.PI_OFFLINE = "1";
process.env.PI_SKIP_VERSION_CHECK = "1";
process.env.PI_CODING_AGENT_DIR = agentDir;

let loaded;
let loadError;
let skipped = false;
try {
	const loaderPath = path.join(pi.dir, "dist", "core", "extensions", "loader.js");
	if (!fs.existsSync(loaderPath)) {
		skipped = true;
		loadError = `Pi ${pi.version} at ${pi.dir} has no extension loader (${loaderPath})`;
		throw new Error(loadError);
	}
	const { loadExtensions, createExtensionRuntime } = await import(pathToFileURL(loaderPath).href);
	const runtime = createExtensionRuntime();
	for (const method of ["sendMessage", "sendUserMessage", "appendEntry", "setSessionName", "setLabel", "setActiveTools"]) {
		if (typeof runtime[method] === "function") runtime[method] = () => undefined;
	}
	runtime.getSessionName = () => "pi-bootstrap-verify";
	runtime.getSettings = () => ({});
	runtime.getActiveTools = runtime.getAllTools = () => [];
	loaded = await loadExtensions(entryFiles, workDir, undefined, runtime);
} catch (error) {
	loadError = error instanceof Error ? error.message : String(error);
} finally {
	fs.rmSync(workDir, { recursive: true, force: true });
}

const commands = loaded
	? [...new Set(loaded.extensions.flatMap((extension) => [...extension.commands].map(([name]) => name)))].sort()
	: [];
const permissionGate = loaded
	? loaded.extensions.some((extension) => extension.path.includes("permission-modes") && (extension.handlers.get("tool_call")?.length ?? 0) > 0)
	: false;

const payload = {
	ok: false,
	piVersion: pi.version,
	piDir: pi.dir,
	packages,
	extensions,
	extensionCount: loaded?.extensions.length ?? 0,
	errors: loaded?.errors ?? [],
	commands,
	permissionGate,
	loadError,
	skipped,
};

if (options.mode === "verify") {
	const problems = [];
	const expected = readJson(options.expectFrom);
	if (!expected) {
		problems.push(`cannot read the recorded pre-install state from ${options.expectFrom}`);
	} else {
		if (expected.skipped || expected.ok === false) {
			// The pre-run environment could not be inspected (for example a stub
			// `pi` in the test suite). A rollback can then only prove that what is
			// there now loads; it cannot compare command lists.
			payload.previousStateUnavailable = true;
		} else {
			if (expected.piVersion && expected.piVersion !== pi.version) {
				problems.push(`Pi is ${pi.version} after rollback, expected ${expected.piVersion}`);
			}
			for (const name of expected.commands ?? []) {
				if (!commands.includes(name)) problems.push(`command ${name} is not registered after rollback`);
			}
			for (const pkg of expected.packages ?? []) {
				const now = packages.find((info) => info.id === pkg.id);
				if (!now) {
					problems.push(`${pkg.id} was installed before the run and is not configured now`);
					continue;
				}
				if (now.version !== pkg.version) {
					problems.push(`${pkg.id} is ${now.version ?? "missing"} after rollback, expected ${pkg.version}`);
				}
			}
		}
	}
	if (loadError && !skipped) problems.push(`loader error: ${loadError}`);
	for (const error of loaded?.errors ?? []) problems.push(`${error.path}: ${error.error}`);
	for (const info of packages) if (info.error) problems.push(`${info.id}: ${info.error}`);
	if ((expected?.permissionGate ?? false) && !permissionGate) problems.push("permission-modes tool_call gate is not registered");
	payload.problems = problems;
	payload.ok = problems.length === 0;
} else {
	const problems = [];
	if (!loaded) problems.push(loadError ?? "extensions could not be loaded");
	for (const error of payload.errors) problems.push(`${error.path}: ${error.error}`);
	for (const info of packages) if (info.error) problems.push(`${info.id}: ${info.error}`);
	for (const name of options.requireCommands) {
		if (!commands.includes(name)) problems.push(`command ${name} is not registered`);
	}
	payload.requiredCommands = options.requireCommands;
	payload.problems = problems;
	payload.ok = problems.length === 0;
}

if (options.jsonOut) fs.writeFileSync(options.jsonOut, `${JSON.stringify(payload, null, 2)}\n`);

if (skipped) {
	// A stub `pi` (the installer's own test suite) or a Pi build without a
	// loader: nothing can be proven either way, so say so instead of guessing.
	console.log(`SKIP stack verification: ${loadError}`);
	process.exit(3);
}

const summary = `Pi ${pi.version}; ${payload.extensionCount} extension(s); ${commands.length} command(s)${
	packages.length ? `; packages ${packages.map((info) => `${info.id}@${info.version ?? "?"}`).join(", ")}` : ""
}`;
if (payload.ok) {
	console.log(`stack verification OK: ${summary}`);
	process.exit(0);
}
console.error(`stack verification FAILED: ${summary}`);
for (const problem of payload.problems ?? []) console.error(`  - ${problem}`);
for (const error of payload.errors ?? []) console.error(`  - ${error.path}: ${error.error}`);
if (loadError) console.error(`  - ${loadError}`);
for (const info of packages) if (info.error) console.error(`  - ${info.id}: ${info.error}`);
process.exit(1);
