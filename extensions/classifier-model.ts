import { mkdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type JsonObject = Record<string, unknown>;

const DEFAULT_TIMEOUT_MS = 60_000;
const DISABLE_LABEL = "Disable classifier";

// Pi resolves its agent directory from PI_CODING_AGENT_DIR (see
// getAgentDir() in @earendil-works/pi-coding-agent). The classifier selection
// must be written to the same directory Pi and its packages use, otherwise
// `/classifier-model` appears to work while permission-modes keeps reading a
// different file. PI_AGENT_DIR is this repository's installer-only override
// and is deliberately not consulted here: Pi itself ignores it, so honoring
// it would reintroduce the mismatch. The installer translates PI_AGENT_DIR to
// PI_CODING_AGENT_DIR for the `pi` process it drives.
export function resolveAgentDir(): string {
	const configured = process.env.PI_CODING_AGENT_DIR?.trim();
	if (!configured) return join(homedir(), ".pi", "agent");
	if (configured === "~") return homedir();
	if (configured.startsWith("~/")) return join(homedir(), configured.slice(2));
	return resolve(configured);
}

export function resolveConfigPath(): string {
	return join(requireSupportedAgentDir(), "permission-modes.json");
}

// permission-modes 2.8.0 reads `join(homedir(), ".pi", "agent",
// "permission-modes.json")` and exposes no way to redirect it: the pinned
// source (config.ts) sets the path at module load and only its test helper
// `setGlobalConfigPathForTests` can change it. So with a custom
// PI_CODING_AGENT_DIR the gate and Pi would use two different files.
//
// The selection is deliberately NOT mirrored to the upstream path: a test or a
// throwaway Pi instance with PI_CODING_AGENT_DIR set would then rewrite the
// real user's `~/.pi/agent/permission-modes.json`, which is exactly the
// cross-directory write this command must never perform. Instead the command
// fails closed and says why, so nobody believes a selection was saved while
// the gate keeps reading another file.
function requireSupportedAgentDir(): string {
	const agentDir = resolve(resolveAgentDir());
	const upstreamDir = resolve(join(homedir(), ".pi", "agent"));
	if (agentDir === upstreamDir) return agentDir;
	const upstreamConfig = join(upstreamDir, "permission-modes.json");
	throw new Error(
		`/classifier-model cannot save a selection here: Pi is using ${agentDir}, but permission-modes 2.8.0 always reads ${upstreamConfig} and cannot be redirected. ` +
			`Writing that file anyway would change a directory this Pi does not own, so nothing was written. ` +
			`Run Pi with the default agent directory (unset PI_CODING_AGENT_DIR), or set the classifier block in ${upstreamConfig} yourself.`,
	);
}

function readConfig(configPath: string): JsonObject {
	let text: string;
	try {
		text = readFileSync(configPath, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
		throw new Error(`Could not read ${configPath}: ${String(error)}`);
	}

	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch (error) {
		throw new Error(`Could not parse ${configPath}: ${error instanceof Error ? error.message : String(error)}`);
	}

	if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
		throw new Error(`Could not parse ${configPath}: the JSON root must be an object`);
	}
	return parsed as JsonObject;
}

function writeConfig(configPath: string, config: JsonObject): void {
	const directory = dirname(configPath);
	mkdirSync(directory, { recursive: true });

	let mode: number | undefined;
	try {
		mode = statSync(configPath).mode;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}

	const temporaryPath = `${configPath}.tmp-${process.pid}-${Date.now()}`;
	try {
		writeFileSync(temporaryPath, `${JSON.stringify(config, null, 2)}\n`, {
			encoding: "utf8",
			mode: mode ?? 0o600,
		});
		renameSync(temporaryPath, configPath);
	} catch (error) {
		try {
			// Best effort cleanup. The original file is left untouched on failure.
			unlinkSync(temporaryPath);
		} catch {
			// Ignore cleanup errors and report the original write failure.
		}
		throw new Error(`Could not write ${configPath}: ${String(error)}`);
	}
}

function classifierConfig(config: JsonObject): JsonObject {
	const value = config.classifier;
	return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as JsonObject) : {};
}

function modelName(model: { provider: string; id: string }): string {
	return `${model.provider}/${model.id}`;
}

export default function classifierModelExtension(pi: ExtensionAPI) {
	pi.registerCommand("classifier-model", {
		description: "Choose the permission-modes classifier model",
		handler: async (_args, ctx) => {
			if (!ctx.hasUI) {
				ctx.ui.notify("Classifier model selection requires interactive UI.", "error");
				return;
			}

			// Resolved per invocation so a changed PI_CODING_AGENT_DIR (or a
			// reload in a new environment) always targets Pi's current directory.
			// An unsupported directory is refused before the picker is shown:
			// the user must not spend a selection on a write that cannot reach
			// the file permission-modes reads.
			let configPath: string;
			try {
				configPath = resolveConfigPath();
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			let config: JsonObject;
			try {
				config = readConfig(configPath);
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			try {
				await ctx.modelRegistry.refresh();
			} catch (error) {
				ctx.ui.notify(
					`Could not refresh model registry; showing cached models. ${error instanceof Error ? error.message : String(error)}`,
					"warning",
				);
			}

			const models = ctx.modelRegistry
				.getAvailable()
				.filter((model) => model.provider && model.id)
				.sort((a, b) => modelName(a).localeCompare(modelName(b)));
			if (models.length === 0) {
				ctx.ui.notify("No available models. Configure a provider/model in Pi first.", "error");
				return;
			}

			const current = classifierConfig(config);
			const currentModel = typeof current.model === "string" ? current.model : undefined;
			const labels = models.map((model) => {
				const id = modelName(model);
				return id === currentModel ? `✓ ${id}` : id;
			});
			const title = currentModel ? `Choose classifier model\nCurrent: ${currentModel}` : "Choose classifier model";
			const selected = await ctx.ui.select(title, [...labels, DISABLE_LABEL]);
			if (!selected) return;

			const selectedIndex = labels.indexOf(selected);
			const nextClassifier: JsonObject = { ...current };
			if (!("timeoutMs" in nextClassifier)) nextClassifier.timeoutMs = DEFAULT_TIMEOUT_MS;

			if (selected === DISABLE_LABEL) {
				nextClassifier.enabled = false;
			} else if (selectedIndex >= 0) {
				nextClassifier.enabled = true;
				nextClassifier.model = modelName(models[selectedIndex]);
			} else {
				ctx.ui.notify("Unknown classifier selection.", "error");
				return;
			}

			try {
				writeConfig(configPath, { ...config, classifier: nextClassifier });
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			try {
				ctx.ui.notify(`Classifier ${nextClassifier.enabled === false ? "disabled" : "updated"}.`, "info");
				await ctx.reload();
				return;
			} catch (error) {
				ctx.ui.notify(
					`Classifier configuration saved, but Pi could not reload it. Run /reload. ${error instanceof Error ? error.message : String(error)}`,
					"warning",
				);
			}
		},
	});
}
