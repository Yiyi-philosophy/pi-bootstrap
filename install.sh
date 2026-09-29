#!/usr/bin/env bash
set -euo pipefail

AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
EXTENSIONS_DIR="$AGENT_DIR/extensions"
KEYBINDINGS_FILE="$AGENT_DIR/keybindings.json"
TMUX_CONFIG="${TMUX_CONFIG_FILE:-$HOME/.tmux.conf}"
MINIMAL_MODE_URL="https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/examples/extensions/minimal-mode.ts"

tmp_files=()
cleanup() {
	if ((${#tmp_files[@]})); then
		rm -f "${tmp_files[@]}"
	fi
}
trap cleanup EXIT

die() {
	echo "pi-bootstrap: $*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_command node
require_command npm
require_command curl

mkdir -p "$EXTENSIONS_DIR"

echo "Installing Pi Coding Agent..."
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# npm's global bin directory may not have been on PATH when this script started.
PI_BIN="$(command -v pi || true)"
if [[ -z "$PI_BIN" ]]; then
	NPM_GLOBAL_BIN="$(npm prefix -g)/bin"
	if [[ -x "$NPM_GLOBAL_BIN/pi" ]]; then
		PI_BIN="$NPM_GLOBAL_BIN/pi"
	else
		die "Pi was installed but the pi command could not be found"
	fi
fi

echo "Installing default Pi extensions..."
"$PI_BIN" install npm:@georgedong32/permission-modes
"$PI_BIN" install npm:@narumitw/pi-btw
"$PI_BIN" install npm:pi-advisor-flow

install_classifier_extension() {
	local local_source="${PI_BOOTSTRAP_SOURCE_DIR:-}"
	if [[ -z "$local_source" && -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
		local_source="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	fi

	if [[ -n "$local_source" && -f "$local_source/extensions/classifier-model.ts" ]]; then
		install -m 0644 "$local_source/extensions/classifier-model.ts" "$EXTENSIONS_DIR/classifier-model.ts"
		return
	fi

	# Keep the curl | bash path self-contained. Local checkouts use the source file above.
	cat > "$EXTENSIONS_DIR/classifier-model.ts" <<'CLASSIFIER_MODEL_EXTENSION'
import { mkdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type JsonObject = Record<string, unknown>;

const CONFIG_PATH = join(homedir(), ".pi", "agent", "permission-modes.json");
const DEFAULT_TIMEOUT_MS = 60_000;
const DISABLE_LABEL = "Disable classifier";

function readConfig(): JsonObject {
	let text: string;
	try {
		text = readFileSync(CONFIG_PATH, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
		throw new Error(`Could not read ${CONFIG_PATH}: ${String(error)}`);
	}

	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch (error) {
		throw new Error(`Could not parse ${CONFIG_PATH}: ${error instanceof Error ? error.message : String(error)}`);
	}

	if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
		throw new Error(`Could not parse ${CONFIG_PATH}: the JSON root must be an object`);
	}
	return parsed as JsonObject;
}

function writeConfig(config: JsonObject): void {
	const directory = dirname(CONFIG_PATH);
	mkdirSync(directory, { recursive: true });

	let mode: number | undefined;
	try {
		mode = statSync(CONFIG_PATH).mode;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}

	const temporaryPath = `${CONFIG_PATH}.tmp-${process.pid}-${Date.now()}`;
	try {
		writeFileSync(temporaryPath, `${JSON.stringify(config, null, 2)}\n`, {
			encoding: "utf8",
			mode: mode ?? 0o600,
		});
		renameSync(temporaryPath, CONFIG_PATH);
	} catch (error) {
		try {
			// Best effort cleanup. The original file is left untouched on failure.
			unlinkSync(temporaryPath);
		} catch {
			// Ignore cleanup errors and report the original write failure.
		}
		throw new Error(`Could not write ${CONFIG_PATH}: ${String(error)}`);
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

			let config: JsonObject;
			try {
				config = readConfig();
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
				writeConfig({ ...config, classifier: nextClassifier });
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				return;
			}

			try {
				await ctx.reload();
				ctx.ui.notify(`Classifier ${nextClassifier.enabled === false ? "disabled" : "updated"}.`, "info");
			} catch (error) {
				ctx.ui.notify(
					`Classifier configuration saved, but Pi could not reload it. Run /reload. ${error instanceof Error ? error.message : String(error)}`,
					"warning",
				);
			}
		},
	});
}
CLASSIFIER_MODEL_EXTENSION
}

install_classifier_extension

echo "Installing the official minimal-mode example..."
minimal_tmp="$(mktemp)"
tmp_files+=("$minimal_tmp")
curl -fsSL "$MINIMAL_MODE_URL" -o "$minimal_tmp"
install -m 0644 "$minimal_tmp" "$EXTENSIONS_DIR/minimal-mode.ts"

merge_keybindings() {
	node - "$KEYBINDINGS_FILE" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const file = process.argv[2];
const directory = path.dirname(file);
fs.mkdirSync(directory, { recursive: true });

let config = {};
let mode;
try {
  mode = fs.statSync(file).mode;
  config = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (error) {
  if (error && error.code !== "ENOENT") {
    console.error(`Could not parse ${file}: ${error.message}`);
    process.exit(1);
  }
}
if (config === null || typeof config !== "object" || Array.isArray(config)) {
  console.error(`Could not parse ${file}: the JSON root must be an object`);
  process.exit(1);
}

config["app.thinking.cycle"] = "ctrl+shift+tab";
const temporary = `${file}.tmp-${process.pid}-${Date.now()}`;
try {
  fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`, { encoding: "utf8", mode: mode ?? 0o600 });
  fs.renameSync(temporary, file);
} catch (error) {
  try { fs.unlinkSync(temporary); } catch {}
  console.error(`Could not write ${file}: ${error.message}`);
  process.exit(1);
}
NODE
}

echo "Merging Pi keybindings..."
merge_keybindings

if command -v tmux >/dev/null 2>&1; then
	touch "$TMUX_CONFIG"
	if ! grep -Fqx "set -g extended-keys on" "$TMUX_CONFIG"; then
		printf '\n%s\n' "set -g extended-keys on" >> "$TMUX_CONFIG"
	fi
	if [[ -n "${TMUX:-}" ]]; then
		tmux source-file "$TMUX_CONFIG" || echo "pi-bootstrap: could not reload tmux configuration; restart tmux or run tmux source-file $TMUX_CONFIG" >&2
	fi
fi

cat <<'EOF'

Pi bootstrap installed.

Next steps:

1. Configure your providers/models in Pi as usual.
2. Start Pi:
     pi
3. Choose the permission classifier:
     /classifier-model
4. Choose Advisor models:
     /advisor-models
5. Switch permission modes:
     /mode
EOF
