# pi-bootstrap

`pi-bootstrap` is a small, public bootstrap for one version-pinned Pi Coding Agent ecosystem snapshot. It pins the Pi runtime and default extensions, installs no credentials, and never chooses a provider or model for the user.

## Quick install

Replace `<USER>` with the GitHub owner of this repository:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/pi-bootstrap/main/install.sh | bash
```

For a reviewable install:

```bash
git clone https://github.com/<USER>/pi-bootstrap.git
cd pi-bootstrap
less install.sh
./install.sh
```

Third-party Pi extensions run with the user's permissions. Read the source and install only extensions you trust.

## Version policy

This repository reproduces one pinned ecosystem snapshot; it does not install whatever happens to be latest. Exact versions are kept in `install.sh` so the one-line installer remains self-contained. A newer upstream release is adopted only after the complete Pi plus extension combination passes compatibility checks. See [`TESTED_VERSIONS.md`](TESTED_VERSIONS.md) for the verification record and the distinction between published, metadata-compatible, and runtime-tested releases.

The stable Pi release is the anchor. `minimal-mode.ts` is always downloaded from the matching `earendil-works/pi` release tag, never from `main`. Default and optional extensions are checked against that Pi release before their pins are changed.

## What it installs

### Core

- Pi Coding Agent: `@earendil-works/pi-coding-agent@0.87.1`
- `@georgedong32/permission-modes@2.7.0`
- The local [`extensions/classifier-model.ts`](extensions/classifier-model.ts), which adds `/classifier-model`

### Default convenience extensions

- `@narumitw/pi-btw@0.61.1` for `/btw` side questions
- `pi-advisor-flow@0.9.0` for `/advisor`, `/advisor-models`, and `/advisor-settings`
- The official Pi `minimal-mode.ts` example from Pi `v0.87.1`

The pinned source URL is `https://raw.githubusercontent.com/earendil-works/pi/v0.87.1/packages/coding-agent/examples/extensions/minimal-mode.ts`.

The installer also merges `app.thinking.cycle = "ctrl+shift+tab"` into `~/.pi/agent/keybindings.json`.

## Model configuration

This repository does not manage models. It does not create or edit `auth.json` or `models.json`, store API keys, add provider endpoints, or select a model during installation.

After configuring providers in Pi, use:

```text
/classifier-model
```

to choose the `permission-modes` classifier from Pi's current available model registry. The command shows the current model, offers **Disable classifier**, preserves existing classifier fields and permission rules, and keeps a previous model when disabling.

Use the command supplied by `pi-advisor-flow` to choose its models:

```text
/advisor-models
```

The installer does not create `advisor.json`, choose an Executor, or choose an Advisor.

## tmux compatibility

The installer checks `tmux -V` numerically and never kills the tmux server:

- tmux **3.5 or newer**: `set -g extended-keys on` and `set -g extended-keys-format csi-u`
- tmux **3.2 through 3.4**: `set -g extended-keys on`
- tmux **older than 3.2**: no extended-key configuration; upgrade tmux or run Pi outside tmux for modified Enter shortcuts

Settings are maintained in a small idempotent block in `~/.tmux.conf`. If the installer is running inside tmux it attempts `tmux source-file`; a full server restart may still be needed for modified-key changes to be guaranteed active.

## Optional extensions

These are intentionally not installed by the bootstrap. No optional version is certified in this snapshot. After a monthly audit records an exact tested version, install it explicitly (replace `<TESTED_VERSION>`):

```bash
# OpenAI/Codex service tier controls
pi install npm:pi-openai-service-tier@<TESTED_VERSION>

# Parallel and delegated agents
pi install npm:pi-subagents@<TESTED_VERSION>

# MCP server adapter
pi install npm:pi-mcp-adapter@<TESTED_VERSION>

# Language Server Protocol integration
pi install npm:@narumitw/pi-lsp@<TESTED_VERSION>
```

`pi-retry` is intentionally not installed. Modern Pi includes provider retry and timeout handling; the old extension is deprecated and superseded.

## Files and safety

The installer is idempotent. It creates `~/.pi/agent/extensions/` as needed, atomically merges JSON objects, keeps unrelated fields, and refuses to replace malformed JSON. It never edits `auth.json` or `models.json`, changes shell profiles, installs sudo packages, enables bypass mode, or installs optional extensions.

The local extension writes only this file when the user selects a classifier:

```text
~/.pi/agent/permission-modes.json
```

A missing classifier timeout defaults to 60000 ms; an existing `timeoutMs` is retained. Successful changes invoke Pi's supported `ctx.reload()` API. If reload fails, the command saves the file and asks the user to run `/reload`.

The embedded extension in `install.sh` is checked against the repository source with:

```bash
scripts/check-embedded-extension.sh
```

## Upgrade policy

Monthly maintenance starts by finding the newest stable Pi and stable releases of the default and optional extensions. It checks package metadata, peer dependencies, changelogs, Pi release documentation, and the exact Pi-bound files. If any core component is incompatible, the previous confirmed-good matrix remains in place. The maintenance instructions are in [`docs/monthly-maintenance-prompt.md`](docs/monthly-maintenance-prompt.md).

## Upstream API verification

The classifier extension uses Pi's current APIs for the pinned release: `pi.registerCommand`, `ctx.hasUI`, `ctx.modelRegistry.refresh()`, `ctx.modelRegistry.getAvailable()`, `ctx.ui.select()`, and command-context `ctx.reload()`.

## Testing

```bash
bash -n install.sh
shellcheck install.sh  # optional
git diff --check
scripts/check-embedded-extension.sh
```

The monthly maintenance prompt also specifies isolated tests for malformed JSON, config merging, installer idempotence, pinned URLs, and tmux versions `3.1`, `3.2`, `3.3a`, `3.4`, `3.5`, `3.5a`, and `3.6`.
