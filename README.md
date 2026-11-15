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

This repository reproduces one pinned ecosystem snapshot; it does not install whatever happens to be latest. Exact versions and the source manifest are maintained in `scripts/pins.mjs` and embedded into the self-contained `install.sh` by `node scripts/build-installer.mjs`. A newer upstream release is adopted only after the complete Pi plus extension combination passes compatibility checks. See [`TESTED_VERSIONS.md`](TESTED_VERSIONS.md) for the verification record and the distinction between published, metadata-compatible, and runtime-tested releases.

The stable Pi release is the anchor. `minimal-mode.ts` is always downloaded from the matching `earendil-works/pi` release tag, never from `main`, and its SHA256 is verified. Default and optional extensions are checked against that Pi release before their pins are changed. When a component is pinned to a git commit instead of an npm release, the commit is immutable, never a moving branch, and every installed file is verified against an embedded SHA256 manifest; source-built pins are always labeled as such and never presented as official npm releases.

## Known upstream issues

See [`TESTED_VERSIONS.md`](TESTED_VERSIONS.md) for the full list. In short: permission mode switches override manual model changes while a model profile maps the mode (upstream #3 — clear the mappings in `~/.pi/agent/model-profiles.json` to opt out), mode switches invalidate provider prompt caches (upstream #4), and OpenAI Codex models cannot be used as the permission classifier because they reject the `temperature` parameter (upstream PR #1).

## What it installs

### Core

- Pi Coding Agent: `@earendil-works/pi-coding-agent@1.5.2`
- `permission-modes` 2.8.0 from the pinned upstream commit `cf77816f28e102409dddbf8e537e4cf57aa092f0`
- The local [`extensions/classifier-model.ts`](extensions/classifier-model.ts), which adds `/classifier-model`

`permission-modes@2.8.0` is **not an npm release** (npm still ships 2.7.0, which has a classifier bug that ignores authentication-resolved custom `baseUrl`). The installer verifies the commit, immutable tree `480649739171c272f355850cf6b6228ffa823c0c`, exact tracked file set and all 69 SHA256 hashes before publishing the source into Pi’s managed git directory. It does not run the source checkout’s npm lifecycle.

### Default convenience extensions

- `@narumitw/pi-btw@0.63.8` for `/btw` side questions
- `pi-advisor-flow@0.15.1` for `/advisor`, `/advisor-models`, `/advisor-settings`, and `/advisor-stats`
- The official Pi `minimal-mode.ts` example from Pi `v1.5.2`

The pinned source URL is `https://raw.githubusercontent.com/earendil-works/pi/v1.5.2/packages/coding-agent/examples/extensions/minimal-mode.ts`, and its SHA256 is pinned and verified so a re-tagged release cannot change the installed bytes.

Pi `1.5.2` requires Node.js `>=22.19.0`.

When upgrading from 1.4.0, Pi renames the Azure provider from `azure-openai-responses` to `azure`; Azure users must migrate their provider references according to the upstream release notes. Pi also changes the default `cacheWarming` from `streaming` to `idle`; set `"cacheWarming": "streaming"` in Pi settings to retain the previous behavior. The bootstrap preserves existing configuration and does not perform either change for you.

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

Settings are maintained in a small idempotent block in `~/.tmux.conf`. The installer does not contact a running tmux server. After reviewing the file, reload it yourself; a server restart may be needed for modified-key changes.

## Optional extensions

These are intentionally not installed by the bootstrap. No optional version is certified in this snapshot. On 2026-11-14, `pi-subagents@0.88.1`, `@narumitw/pi-subagents@3.4.5`, `pi-mcp-adapter@7.0.1`, and `@narumitw/pi-lsp@0.49.12` installed and loaded individually on Pi 1.5.2 with command registration verified; child agents, MCP connections, and language servers were not exercised. The two subagents packages both register `/subagents`; choose one. The adapter registers `/mcp`, overlapping Pi's built-in command; prefer built-in MCP support. `pi-openai-service-tier@0.1.4` still targets pre-1.0 package metadata and remains excluded from certification. After reviewing the load-only evidence in [`TESTED_VERSIONS.md`](TESTED_VERSIONS.md), install a chosen optional package explicitly (replace `<TESTED_VERSION>`):

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

The installer uses one transaction for the global CLI/bin, managed npm/git trees, local extensions, settings, keybindings and tmux file. Before any replacement it copies and fsyncs the complete snapshots, fsyncs a checksummed manifest, then atomically writes and fsyncs a versioned JSON journal. `transaction.env` retains its legacy filename but contains **data only**; no shell parser or evaluator reads it. Canonical JSON, fixed keys, bounds, types, relative inventories, hashes and physical paths are validated before restoring or deleting anything.

Only the default `$HOME/.pi/agent` is supported. A `PI_CODING_AGENT_DIR` or legacy `PI_AGENT_DIR` override is accepted only when component-by-component physical resolution proves it names that exact default directory. Custom locations, redirected default/state/backup parents, dangling links and missing-component-plus-`..` paths fail before journal access or network/mutation. Permission-modes independently uses `homedir()/.pi/agent`; the installer never mirrors its configuration into another HOME.

The npm global prefix is independently anchored to `npm_config_prefix` / `NPM_CONFIG_PREFIX` (which must agree), or the running Node installation prefix. The actual `npm prefix -g` and `npm root -g` must agree before installation. Set both prefix environment variables explicitly if your npm configuration uses another prefix. A non-default `settings.npmCommand` is unsupported. npm lifecycle scripts are disabled for global and extension installs; real Pi lifecycle tests include an executing positive control. No sudo, shell profile changes or optional packages are involved.

Package migration matches exact npm identities and the exact permission-modes GitHub repository. String and object entries (including `autoload` and resource filters) are preserved; duplicate identities, duplicate JSON keys, malformed objects and ambiguous specifications stop the installation. Every `pi remove` failure aborts and rolls back. Unrelated settings and package entries are retained. The installer does not write `auth.json`, `models.json`, `permission-modes.json` or `advisor.json`.

On ordinary errors, SIGINT or SIGTERM it restores snapshots and verifies the old CLI version and extension commands with the real old loader. A gated child process records its worker PID durably before running and kills its process group on installer death. SIGKILL/power loss recovery happens on the next invocation, before parsing live settings or calling npm/curl/git:

```bash
./install.sh --recover
```

Use the same HOME and prefix environment as the interrupted invocation. Recovery does not resume installation automatically. A missing previous CLI is reported as `UNVERIFIED`. Validation failures retain the journal and backup and stop installation. Successful installs also retain their prior backup; an unchanged repeat checks the real loader and performs no package installation. Valid committed/rolled-back evidence is validated before a later transaction replaces it.

Recovery is retryable if restoration itself is killed; the live tree can be partial until the next successful recovery. A truncated temporary journal is never interpreted and is retained as `journal-fragment`; review it before a new installation. A crash during committed-backup cleanup, unsupported legacy shell journals, changed prefix, unsafe ownership/modes or conflicting evidence requires manual review. Do not delete evidence to force installation. Run the installer with Pi sessions stopped: the lock coordinates bootstrap invocations, not arbitrary concurrent processes or a hostile process with the same UID. fsync durability depends on filesystem/OS guarantees.

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

Monthly maintenance starts by finding the newest stable Pi and stable releases of the default and optional extensions. It checks package metadata, peer dependencies, changelogs, Pi release documentation, and the exact Pi-bound files. If any core component is incompatible, the previous confirmed-good matrix remains in place. The maintenance instructions are in [`docs/monthly-maintenance-prompt.md`](docs/monthly-maintenance-prompt.md); the current upgrade evidence is in [`docs/upgrade-audit-2026-11.md`](docs/upgrade-audit-2026-11.md). Historical 2026-10 evidence is in [`docs/upgrade-audit-2026-10.md`](docs/upgrade-audit-2026-10.md) and [`docs/upgrade-risk-review.md`](docs/upgrade-risk-review.md).

## Upstream API verification

The classifier extension uses Pi's current APIs for the pinned release: `pi.registerCommand`, `ctx.hasUI`, `ctx.modelRegistry.refresh()`, `ctx.modelRegistry.getAvailable()`, `ctx.ui.select()`, and command-context `ctx.reload()`. All are present and unchanged in Pi 1.5.2's release declarations.

## Testing

Tests create fresh scratch homes and explicitly set both npm prefixes, caches, user/global npmrc paths, TMPDIR, Pi directory, tmux file and PATH. Before every real global operation they check npm’s actual prefix/root. Never run acceptance against a production HOME.

```bash
node scripts/build-installer.mjs --check
bash -n install.sh
shellcheck install.sh scripts/*.sh
node --test scripts/test-offline.mjs
node scripts/test-real.mjs /absolute/scratch/evidence-directory
```

The real suite installs the exact matrix in a fresh home, checks repeat-run filesystem identity, and proves npm lifecycle suppression. It exercises classifier selection, real Advisor selectors and consultation, and `/btw` through loopback HTTP with controlled UI input. It upgrades actual Pi 1.0.2 and previous-main 1.4.0 stacks, injects failures after CLI replacement, compares restored inventories and loader commands, verifies offline recovery, and exercises migration and classifier safety gates. Historical Pi 1.0.2 is installed with a publication cutoff so its floating internal dependency ranges cannot silently select today's runtime. Snapshot-heavy installer tests allow ten minutes; production subprocess limits are unchanged. Tests perform no real provider requests. Physical terminal forwarding, mouse interaction, and split-pane behavior are not certified. See [`docs/upgrade-audit-2026-11.md`](docs/upgrade-audit-2026-11.md) for this run and [`docs/independent-hardening-report.md`](docs/independent-hardening-report.md) for historical hardening evidence.
