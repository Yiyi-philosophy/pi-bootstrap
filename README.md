# pi-bootstrap

`pi-bootstrap` is a small, public bootstrap for Pi Coding Agent. It installs the core agent, a few convenience extensions, and two local extensions without choosing a provider or model for you.

## Quick install

Replace `<USER>` with the GitHub owner of this repository:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/pi-bootstrap/main/install.sh | bash
```

For a reviewable install, clone the repository first:

```bash
git clone https://github.com/<USER>/pi-bootstrap.git
cd pi-bootstrap
less install.sh
./install.sh
```

Pi extensions run with the user's permissions. Read the source and only install extensions you trust.

## What it installs

### Core

- Pi Coding Agent: `@earendil-works/pi-coding-agent`
- `@georgedong32/permission-modes`
- The local [`extensions/classifier-model.ts`](extensions/classifier-model.ts), which adds `/classifier-model`

### Default convenience extensions

- `@narumitw/pi-btw` for `/btw` side questions
- `pi-advisor-flow` for `/advisor`, `/advisor-models`, and `/advisor-settings`
- The official Pi `minimal-mode.ts` example from `earendil-works/pi`

The installer also merges `app.thinking.cycle = "ctrl+shift+tab"` into `~/.pi/agent/keybindings.json`. When tmux is installed, it adds `set -g extended-keys on` to `~/.tmux.conf` and reloads it for an active tmux session.

## Model configuration

This repository does not manage models. It does not create or edit `auth.json` or `models.json`, store API keys, add provider endpoints, or select a model during installation.

After configuring providers in Pi, use:

```text
/classifier-model
```

to choose the `permission-modes` classifier from Pi's current available model registry. The command also offers **Disable classifier**, preserves existing classifier fields and permission rules, and keeps a previous model when disabling.

Use the command supplied by `pi-advisor-flow` to choose its models:

```text
/advisor-models
```

The installer does not create `advisor.json`, choose an Executor, or choose an Advisor.

## Optional extensions

These are intentionally not installed by the bootstrap:

```bash
# OpenAI/Codex service tier controls
pi install npm:pi-openai-service-tier

# Parallel and delegated agents
pi install npm:pi-subagents

# MCP server adapter
pi install npm:pi-mcp-adapter

# Language Server Protocol integration
pi install npm:@narumitw/pi-lsp
```

`pi-retry` is intentionally not installed. Current Pi includes provider retry and timeout handling, and the old extension is deprecated/superseded.

## Files and safety

The installer is idempotent. It creates `~/.pi/agent/extensions/` as needed, atomically merges JSON objects, keeps unrelated fields, and refuses to replace malformed JSON. It never edits `auth.json` or `models.json`, changes shell profiles, installs sudo packages, enables bypass mode, or installs the optional extensions above.

The local extension writes only this file when the user selects a classifier:

```text
~/.pi/agent/permission-modes.json
```

It preserves existing `permissions`, classifier fields, and `timeoutMs`; a missing timeout defaults to 60000 ms. A successful change invokes Pi's supported `ctx.reload()` API. If reload is unavailable, the command saves the file and asks the user to run `/reload`.

## Upstream compatibility

The implementation follows the current `earendil-works/pi` coding-agent extension API: `ctx.modelRegistry.refresh()`, `ctx.modelRegistry.getAvailable()`, `ctx.ui.select()`, and command-context `ctx.reload()`. The official minimal mode source remains:

```text
packages/coding-agent/examples/extensions/minimal-mode.ts
```

The package names used by the installer are the current names requested above. The bootstrap deliberately does not wrap or duplicate `pi-advisor-flow` model selection.

## Testing

Run the basic shell check locally:

```bash
bash -n install.sh
shellcheck install.sh   # optional
```

Run the installer twice to verify idempotence. A second run should retain existing keybindings and permission rules and keep exactly one tmux setting line.
