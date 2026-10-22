#!/usr/bin/env node
// Stand-in for the `pi` CLI (Pi 1.4.0 package-manager semantics), used only by
// the pi-bootstrap test suite. It reproduces the behaviors the installer
// depends on, including the awkward ones:
//
//   * install clones/checks out, installs dependencies, and only then writes
//     settings.json (installAndPersist order);
//   * settings entries are matched by package identity (npm name / git
//     host+path, ignoring the ref), never by the raw string;
//   * `remove` deletes package files BEFORE it checks settings, so a "not
//     found" result (exit 1) can still have destroyed the installation;
//   * a settings file that cannot be parsed makes save() a silent no-op while
//     the command still exits 0;
//   * settings.json is rewritten as 2-space JSON with no trailing newline.
//
// Failure knobs (env):
//   FAKE_PI_LOG                 append one line per invocation
//   FAKE_PI_CLONE_DIR           local repository cloned for git sources
//   FAKE_PI_FAIL_INSTALL_MATCH  install fails when the source contains this text
//   FAKE_PI_SILENT_SETTINGS     1 = install exits 0 without writing settings
//   FAKE_PI_FAIL_REMOVE         1 = `remove` exits 1 without doing anything
//   FAKE_PI_REMOVE_NOOP         1 = `remove` exits 0 but changes nothing
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const AGENT_DIR = process.env.PI_CODING_AGENT_DIR || path.join(process.env.HOME || "", ".pi", "agent");
const SETTINGS = path.join(AGENT_DIR, "settings.json");

function log(line) {
	if (process.env.FAKE_PI_LOG) fs.appendFileSync(process.env.FAKE_PI_LOG, line + "\n");
}

function readSettings() {
	if (!fs.existsSync(SETTINGS)) return {};
	try {
		const text = fs.readFileSync(SETTINGS, "utf8");
		if (text.trim() === "") return {};
		return JSON.parse(text);
	} catch {
		return undefined; // unparseable: mirror Pi's silent save() no-op
	}
}

function writeSettings(config) {
	fs.mkdirSync(AGENT_DIR, { recursive: true });
	fs.writeFileSync(SETTINGS, JSON.stringify(config, null, 2));
}

function identity(source) {
	if (source.startsWith("npm:")) {
		const match = source.slice(4).trim().match(/^(@?[^@]+(?:\/[^@]+)?)(?:@(.+))?$/);
		return match ? `npm:${match[1]}` : undefined;
	}
	let url = source.startsWith("git:") ? source.slice(4).trim() : source;
	let host;
	let rest;
	const scp = url.match(/^git@([^:]+):(.+)$/);
	if (scp) {
		host = scp[1];
		rest = scp[2];
	} else if (/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) {
		const parsed = new URL(url);
		host = parsed.hostname;
		rest = parsed.pathname.replace(/^\/+/, "");
	} else {
		const slash = url.indexOf("/");
		if (slash < 0) return undefined;
		host = url.slice(0, slash);
		rest = url.slice(slash + 1);
	}
	const separator = rest.search(/[@#]/);
	if (separator >= 0) rest = rest.slice(0, separator);
	return `git:${host}/${rest.replace(/^\/+/, "").replace(/\.git$/, "")}`;
}

function sourceString(entry) {
	return typeof entry === "string" ? entry : entry && entry.source;
}

function parse(source) {
	if (source.startsWith("npm:")) {
		const id = identity(source);
		return { type: "npm", name: id.slice(4) };
	}
	const url = source.startsWith("git:") ? source.slice(4).trim() : source;
	const at = url.lastIndexOf("@");
	const slash = url.lastIndexOf("/");
	const [repo, ref] = at > slash ? [url.slice(0, at), url.slice(at + 1)] : [url, undefined];
	const host = repo.replace(/^[a-z]+:\/\//i, "").split("/")[0];
	const repoPath = repo.replace(/^[a-z]+:\/\//i, "").split("/").slice(1).join("/");
	return { type: "git", repo, ref, host, path: repoPath };
}

function installNpm(source) {
	const parsed = parse(source);
	const root = path.join(AGENT_DIR, "npm");
	const packageJson = path.join(root, "package.json");
	fs.mkdirSync(root, { recursive: true });
	if (!fs.existsSync(packageJson)) {
		fs.writeFileSync(packageJson, JSON.stringify({ name: "pi-extensions", private: true }, null, 2));
	}
	const target = path.join(root, "node_modules", parsed.name);
	fs.mkdirSync(target, { recursive: true });
	fs.writeFileSync(path.join(target, "package.json"), JSON.stringify({ name: parsed.name }, null, 2));
}

function installGit(source) {
	const parsed = parse(source);
	const target = path.join(AGENT_DIR, "git", parsed.host, parsed.path);
	fs.mkdirSync(path.dirname(target), { recursive: true });
	if (fs.existsSync(target)) {
		if (!parsed.ref) return;
		run("git", ["fetch", "--quiet", "origin", parsed.ref], target);
		run("git", ["reset", "--quiet", "--hard", `${parsed.ref}^{commit}`], target);
		run("git", ["clean", "-fdxq"], target);
		return;
	}
	const repo = process.env.FAKE_PI_CLONE_DIR || parsed.repo;
	run("git", ["clone", "--quiet", repo, target], process.cwd());
	if (parsed.ref) run("git", ["checkout", "--quiet", parsed.ref], target);
}

function run(command, args, cwd) {
	const result = spawnSync(command, args, { cwd, stdio: "pipe", encoding: "utf8" });
	if (result.status !== 0) {
		throw new Error(`${command} ${args.join(" ")} failed: ${result.stderr.trim()}`);
	}
}

function install(source) {
	if (process.env.FAKE_PI_FAIL_INSTALL_MATCH && source.includes(process.env.FAKE_PI_FAIL_INSTALL_MATCH)) {
		console.error(`fake-pi: simulated install failure for ${source}`);
		process.exit(1);
	}
	if (parse(source).type === "npm") installNpm(source);
	else installGit(source);

	if (process.env.FAKE_PI_SILENT_SETTINGS === "1") {
		log(`install ${source} (settings write skipped)`);
		return;
	}
	const config = readSettings();
	if (config === undefined) {
		// Pi prints success and exits 0 even though nothing was persisted.
		console.log(`Installed ${source}`);
		log(`install ${source} (settings unparseable)`);
		return;
	}
	const entries = Array.isArray(config.packages) ? config.packages : [];
	const wanted = identity(source);
	const index = entries.findIndex((entry) => identity(sourceString(entry) || "") === wanted);
	if (index >= 0) {
		entries[index] = typeof entries[index] === "string" ? source : { ...entries[index], source };
	} else {
		entries.push(source);
	}
	config.packages = entries;
	writeSettings(config);
	log(`install ${source}`);
}

function remove(source) {
	if (process.env.FAKE_PI_FAIL_REMOVE === "1") {
		console.error(`fake-pi: simulated remove failure for ${source}`);
		process.exit(1);
	}
	if (process.env.FAKE_PI_REMOVE_NOOP === "1") {
		log(`remove ${source} (no-op)`);
		return;
	}
	const parsed = parse(source);
	// Files go first, exactly like Pi.
	if (parsed.type === "npm") {
		fs.rmSync(path.join(AGENT_DIR, "npm", "node_modules", parsed.name), { recursive: true, force: true });
	} else {
		fs.rmSync(path.join(AGENT_DIR, "git", parsed.host, parsed.path), { recursive: true, force: true });
	}
	const config = readSettings();
	const entries = config && Array.isArray(config.packages) ? config.packages : [];
	const wanted = identity(source);
	const kept = entries.filter((entry) => identity(sourceString(entry) || "") !== wanted);
	if (kept.length === entries.length) {
		console.error(`No matching package found for ${source}`);
		process.exit(1);
	}
	config.packages = kept;
	writeSettings(config);
	log(`remove ${source}`);
}

function list() {
	const config = readSettings();
	const entries = config && Array.isArray(config.packages) ? config.packages : [];
	if (entries.length === 0) {
		console.log("No packages installed.");
		return;
	}
	console.log("User packages:");
	for (const entry of entries) console.log(`  ${sourceString(entry)}`);
}

const [command, ...rest] = process.argv.slice(2);
try {
	switch (command) {
		case "install":
			if (!rest[0]) throw new Error("Missing install source.");
			install(rest[0]);
			break;
		case "remove":
		case "uninstall":
			if (!rest[0]) throw new Error("Missing remove source.");
			remove(rest[0]);
			break;
		case "list":
			list();
			break;
		case "--version":
		case "version":
			console.log("1.4.0");
			break;
		default:
			console.error(`fake-pi: unsupported command ${command}`);
			process.exit(1);
	}
} catch (error) {
	console.error(`fake-pi: ${error.message}`);
	process.exit(1);
}
