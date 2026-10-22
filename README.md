# pi-bootstrap

`pi-bootstrap` is a small, public bootstrap for one version-pinned Pi Coding Agent ecosystem snapshot. It pins the Pi runtime and default extensions, installs no credentials, and never chooses a provider or model for the user.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/Yiyi-philosophy/pi-bootstrap/main/install.sh | bash
```

For a reviewable install:

```bash
git clone https://github.com/Yiyi-philosophy/pi-bootstrap.git
cd pi-bootstrap
less install.sh
./install.sh
```

Third-party Pi extensions run with the user's permissions. Read the source and install only extensions you trust.

## Version policy

This repository reproduces one pinned ecosystem snapshot; it does not install whatever happens to be latest. Exact versions are kept in `install.sh` so the one-line installer remains self-contained. A newer upstream release is adopted only after the complete Pi plus extension combination passes compatibility checks. See [`TESTED_VERSIONS.md`](TESTED_VERSIONS.md) for the verification record and the distinction between published, metadata-compatible, and runtime-tested releases.

The stable Pi release is the anchor. `minimal-mode.ts` is always downloaded from the matching `earendil-works/pi` release tag, never from `main`, and its SHA256 is verified. Default and optional extensions are checked against that Pi release before their pins are changed. When a component is pinned to a git commit instead of an npm release, the commit is immutable, never a moving branch, and every installed file is verified against an embedded SHA256 manifest; source-built pins are always labeled as such and never presented as official npm releases.

## Known upstream issues

See [`TESTED_VERSIONS.md`](TESTED_VERSIONS.md) for the full list. In short: permission mode switches override manual model changes while a model profile maps the mode (upstream #3 — clear the mappings in `~/.pi/agent/model-profiles.json` to opt out), mode switches invalidate provider prompt caches (upstream #4), and OpenAI Codex models cannot be used as the permission classifier because they reject the `temperature` parameter (upstream PR #1).

## What it installs

### Core

- Pi Coding Agent: `@earendil-works/pi-coding-agent@1.4.0`
- `permission-modes` 2.8.0 from the pinned upstream commit `cf77816f28e102409dddbf8e537e4cf57aa092f0`
- The local [`extensions/classifier-model.ts`](extensions/classifier-model.ts), which adds `/classifier-model`

`permission-modes@2.8.0` is **not an npm release** (npm still ships 2.7.0, which has a classifier bug that ignores authentication-resolved custom `baseUrl`). The installer pins the upstream commit and verifies all 69 files against a SHA256 manifest embedded in `install.sh`, so the install is reproducible without depending on a registry publication.

### Default convenience extensions

- `@narumitw/pi-btw@0.62.0` for `/btw` side questions
- `pi-advisor-flow@0.14.2` for `/advisor`, `/advisor-models`, `/advisor-settings`, and `/advisor-stats`
- The official Pi `minimal-mode.ts` example from Pi `v1.4.0`

The pinned source URL is `https://raw.githubusercontent.com/earendil-works/pi/v1.4.0/packages/coding-agent/examples/extensions/minimal-mode.ts`, and its SHA256 is pinned and verified so a re-tagged release cannot change the installed bytes.

Pi `1.4.0` requires Node.js `>=22.19.0`.

The installer also merges `app.thinking.cycle = "ctrl+shift+tab"` into `~/.pi/agent/keybindings.json`.

## How the install is protected

1. **Preflight.** Required commands, Node.js version, `HOME`, and `settings.json` are checked before anything changes. An unreadable, non-object, or ambiguous `packages` array stops the install with an explanation and no writes.
2. **Pre-install source verification.** The pinned permission-modes commit is fetched into a temporary staging repository and checked for the exact commit, the exact git tree, a clean working tree, and all 69 file checksums *before* Pi is asked to install it.
3. **No lifecycle scripts.** Pi's git install would otherwise run the package's `npm install` with `preinstall`/`install`/`postinstall`/`prepare` enabled and offers no flag to disable them (verified against Pi 1.4.0 with a probe package; see [`docs/upgrade-audit-2026-10.md`](docs/upgrade-audit-2026-10.md)). The installer exports `npm_config_ignore_scripts=1` for managed installs. Both npm packages and the pinned source ship prebuilt files, so nothing is lost.
4. **Exact migration.** Stale entries for the three managed packages are identified by Pi's own package identity (npm package name; git host and path without the ref), never by substring. Unrelated packages, local paths, and look-alike names are left alone. Entries carrying extra keys are reported as conflicts instead of being rewritten.
5. **Post-install verification.** The installed checkout is re-verified (commit, tree, clean tree, 69 checksums), and `settings.json` must list exactly the pinned sources; `pi install` can otherwise exit 0 after silently failing to persist.
6. **Rollback.** A failure after the first change restores `settings.json` and any replaced extension files, so no half-activated matrix remains.

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

These are intentionally not installed by the bootstrap. No optional version is certified in this snapshot. As of 2026-10-22, `pi-subagents@0.80.0` (29 commands), `@narumitw/pi-subagents@3.3.0`, `pi-mcp-adapter@5.4.0`, and `@narumitw/pi-lsp@0.49.10` install and load on Pi 1.4.0 with registration verified, but their core functionality was not exercised; `pi-openai-service-tier@0.1.4` still targets pre-1.0 package metadata. Pi has built-in MCP support, which is preferred over adapters for standard MCP use. After an audit records an exact tested version, install it explicitly (replace `<TESTED_VERSION>`):

```bash
# OpenAI/Codex service tier controls (not currently a certification candidate)
pi install npm:pi-openai-service-tier@<TESTED_VERSION>

# Parallel and delegated agents
pi install npm:pi-subagents@<TESTED_VERSION>

# Language Server Protocol integration
pi install npm:@narumitw/pi-lsp@<TESTED_VERSION>
```

`pi-retry` is not present on npm and remains excluded; modern Pi includes provider retry and timeout handling.

## Files and safety

The installer is idempotent. It creates `~/.pi/agent/extensions/` as needed, atomically merges JSON objects, keeps unrelated fields, and refuses to replace malformed JSON. It never edits `auth.json` or `models.json`, changes shell profiles, installs sudo packages, enables bypass mode, or installs optional extensions. `npm install -g` for Pi itself uses `--ignore-scripts`.

It writes only inside `~/.pi/agent`:

- `settings.json` (managed package entries, via `pi install` / `pi remove`)
- `extensions/classifier-model.ts`, `extensions/minimal-mode.ts`
- `keybindings.json` (one key)
- `git/…` and `npm/…` (Pi's own package storage)
- `.pi-bootstrap/` (this run's `settings.json` snapshot and restored-file backups)

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

Monthly maintenance starts by finding the newest stable Pi and stable releases of the default and optional extensions. It checks package metadata, peer dependencies, changelogs, Pi release documentation, and the exact Pi-bound files. If any core component is incompatible, the previous confirmed-good matrix remains in place. The maintenance instructions are in [`docs/monthly-maintenance-prompt.md`](docs/monthly-maintenance-prompt.md); the 2026-10 upgrade evidence is in [`docs/upgrade-audit-2026-10.md`](docs/upgrade-audit-2026-10.md) and [`docs/upgrade-risk-review.md`](docs/upgrade-risk-review.md); the R2 engineering closure is in [`docs/r2-closure-report.md`](docs/r2-closure-report.md).

## Upstream API verification

The classifier extension uses Pi's current APIs for the pinned release: `pi.registerCommand`, `ctx.hasUI`, `ctx.modelRegistry.refresh()`, `ctx.modelRegistry.getAvailable()`, `ctx.ui.select()`, and command-context `ctx.reload()`. All are present and unchanged in Pi 1.4.0's release declarations.

## Testing

```bash
scripts/tests/run-all.sh           # everything available offline
scripts/tests/run-all.sh --fetch   # also download test fixtures
```

Each test runs with its own scratch `HOME`, stubbed `pi`/`npm`/`curl`/`tmux`, and loopback mock servers; none reads the real `~/.pi`, and none needs a credential. Tests that cannot run report `SKIP`, never a false `PASS`.

| Suite | Covers |
|---|---|
| `scripts/tests/test-install-settings.sh` | stale-entry detection: string/object entries, npm→git, version bumps, unrelated packages, malformed settings, `pi remove` failure |
| `scripts/tests/test-install-run.sh` | fresh install, repeat install, upgrade from 1.0.2, pre-install/pinned-source verification, tamper detection, rollback |
| `scripts/tests/test-install-lifecycle.mjs` | real Pi git install with and without `npm_config_ignore_scripts` |
| `scripts/tests/test-classifier-config.mjs` | `/classifier-model` merge, disable, timeout, invalid JSON, atomic write, reload failure |
| `scripts/tests/test-permission-gate.mjs` | fail-closed, bounded retries, allow/deny, embedded commands, powershell, outside-cwd |
| `scripts/tests/test-classifier-baseurl.mjs` | 2.7.0 misroutes / 2.8.0 honors the auth-resolved `baseUrl` (real `ModelRegistry`) |
| `scripts/tests/test-rpc-smoke.mjs` | headless Pi start plus command registration and invocation |
| `scripts/tests/test-default-stack.mjs` | all five default extensions on one real loader |
| `scripts/test-tmux.sh` | tmux `3.1`, `3.2`, `3.3a`, `3.4`, `3.5`, `3.5a`, `3.6`, downgrade, no-trailing-newline, reload failure |
| `scripts/check-embedded-extension.sh` | embedded `classifier-model.ts` is byte-identical to the repository source |

The real-runtime tests need Pi 1.4.0 and the pinned permission-modes source; set `PI_BOOTSTRAP_PI_PACKAGE` and `PI_BOOTSTRAP_PM_280` (or `PI_BOOTSTRAP_AGENT_DIR`) to point at them, or the suite reports those as skipped.
