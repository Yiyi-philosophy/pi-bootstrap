# Upgrade risk review — 2026-10-22 matrix, updated 2026-10-23 (Pi 1.4.0)

Risks, mitigations, and residual exposure for the recommended matrix. Severity reflects worst-case impact on users of this bootstrap. Updated by R2 ([`r2-closure-report.md`](r2-closure-report.md)), which closed the installer and test-coverage findings, and by R3 ([`r3-closure-report.md`](r3-closure-report.md)), which made failure recovery actually restore a working environment.

## Source-built dependency

**Risk (medium):** permission-modes 2.8.0 is consumed from an upstream commit, not an npm release. The bootstrap depends on a git checkout plus a verification manifest rather than an immutable registry artifact.

- Mitigations: the commit SHA `cf77816f28e102409dddbf8e537e4cf57aa092f0` is immutable; `pi install git:` pins and reconciles to exactly that ref; the installer verifies the commit HEAD, the git tree object, a clean working tree, and a 69-file SHA256 manifest **before** installing and again after; the label everywhere says "source snapshot … not an npm release".
- Residual: the manifest and pins live in this repository — a compromised repository could substitute both. This is the same trust level as the installer script itself (`curl | bash`), unchanged in kind.
- Watch item: when upstream publishes 2.8.0 (or newer) to npm, switch the pin to the npm release and re-verify; the 2.7.0 precedent (npm tarball byte-identical to the git tag) makes this expected to be a no-op, but it must be re-checked, not assumed.

**Risk (low):** the git checkout lives under `~/.pi/agent/git/…` with a full `.git` directory and npm-generated `package-lock.json`.

- Mitigation: the manifest covers exactly the tracked files Pi loads; extra files (`.git`, lockfile) are inert. `pi update` is never run by the bootstrap and reconciles only to the pinned ref.

## Install-time code execution

**Risk (medium, mostly mitigated):** `pi install <git source>` clones, checks out, and then runs `npm install --omit=dev --legacy-peer-deps` inside the checkout **with lifecycle scripts enabled**. Pi 1.4.0 offers no flag to disable them (verified: no Pi option or `PI_*` variable; `npmCommand` in settings or inherited npm config are the only knobs).

- Mitigations: (1) the pinned commit, tree, clean tree, and all 69 checksums are verified in an isolated staging clone **before** Pi is asked to install anything, so the code that would run is exactly the audited code; (2) managed installs export `npm_config_ignore_scripts=1`, so no `preinstall`/`install`/`postinstall`/`prepare` script runs; (3) the installed checkout is re-verified afterwards.
- Evidence: `scripts/tests/test-install-lifecycle.mjs` runs the real Pi CLI twice against a probe package over localhost — with the variable no lifecycle script runs, without it all three run.
- Residual: verification is of **content**, not of what the npm dependency tree pulls in at install time. `--omit=dev` limits this to runtime dependencies, and the pinned `package.json` declares only `peerDependencies`. A future pin with real `dependencies` would need the same review before adoption.

## Custom agent directory

**Risk (high, mitigated by refusal):** permission-modes 2.8.0 resolves every user file from `homedir()` and never reads Pi's `PI_CODING_AGENT_DIR`. Under a custom agent directory Pi would use directory A while the permission gate read directory B — silently, and with contradictory rules in the two places a user could not tell which one governed a tool call.

- Evidence (P0, real runtime): `scripts/tests/test-config-source.mjs` loads the pinned source on the real Pi 1.4.0 loader with `$HOME/.pi/agent` denying `Bash(denytest:*)` and `PI_CODING_AGENT_DIR` allowing it; the gate denies and cites `[global]: Bash(denytest:*)`, i.e. the `$HOME` file. The reverse pairing is not denied, proving the custom directory is not read at all. Source: `config.ts` line 47 (`let _configPath = join(homedir(), …)`) at the pinned commit; `profiles.ts` (model-profiles, settings), `permission-forwarding.ts` (subagent root) do the same.
- Why it cannot be redirected from outside: the only setter `setConfigPath()` is exported from `config.ts` but not from `index.ts`, and Pi loads each extension with `moduleCache: false` (`dist/core/extensions/loader.js`), so a second extension importing `config.ts` gets a **separate** module instance — verified: extension A's `setConfigPath()` is visible to A and not to B.
- Mitigation: **UNSUPPORTED and refused.** `require_supported_agent_dir` in `install.sh` compares the installer's agent directory with `$HOME/.pi/agent` (symlinks resolved, so a symlink or trailing-slash spelling of the same directory is accepted) and fails before any mutation, naming the file the gate reads. `/classifier-model` refuses the same layout in-session.
- Residual: users who need the stack elsewhere must move `HOME` or the npm prefix, not `PI_CODING_AGENT_DIR`. There is no supported per-directory permission configuration with this pinned version; fixing that upstream needs a change to permission-modes itself (for example exporting `setConfigPath` and reading `PI_CODING_AGENT_DIR`), which would change the pin, the manifest and the audit.

## Classifier and permission-gate security

**Risk (high if unmitigated):** classifier errors must never silently grant unsafe permissions.

- Evidence: transport faults (malformed JSON, empty stream, timeout) produce no silent allow; the gate blocks after exactly 3 bounded attempts unless `failClosed: false` was explicitly set by the user; `maxRetries: 0` prevents stacked invisible retries (worst-case wait `timeoutMs × 3`). Committed as `scripts/tests/test-permission-gate.mjs` (real Pi loader) and `scripts/tests/test-classifier-baseurl.mjs` (transport faults).
- Note: with `failClosed: false` (explicit user opt-out) the gate falls back to local tier rules and prompting, never to silent bypass.

**Risk (medium):** the October 2026 baseUrl bug could reappear through a future regression.

- Mitigation: the deterministic reproduction is committed at `scripts/tests/test-classifier-baseurl.mjs` (2.7.0 must misroute, 2.8.0 must honor the resolved URL); the monthly audit must re-run it whenever the permission-modes pin changes. It previously existed only in an ephemeral `/tmp` workspace.

**Risk (low):** credential forwarding to the wrong host via the resolved `baseUrl` path.

- Evidence: in the fixed path the credential header appears only on requests to the resolved host; the mock records no other host receiving traffic. The regression case (2.7.0) fails closed rather than being allowed, but it did send the classifier credential to the model's **catalog** URL. Users who ran 2.7.0 with a custom-baseUrl classifier model should rotate that key if the catalog URL was untrusted.

## Upstream open issues carried into this snapshot

- **#3 model-profile override (UX, reproduced):** mode switches force the profile model over manual changes. No permission impact. Workaround documented. If a user's workflow depends on manual mid-session model switching, they should clear per-mode mappings in `~/.pi/agent/model-profiles.json`.
- **#4 KV-cache invalidation (cost, unchanged from 2.7.0):** mode switches and plan-progress updates change the injected system prompt. For cache-sensitive hosted endpoints, keep one mode per session.
- **PR #1 / Codex `temperature` (availability):** selecting a Codex model as classifier fails (fail-closed). Documented in README and TESTED_VERSIONS.md.
- **Upstream test flakiness (maintenance):** two upstream tests are order/timing dependent (shared verdict-cache state). Re-running upstream's suite in a future audit may show 1–2 failures that are not product defects; check isolation first (run the file/test alone) before escalating.
- **`shift+tab` shortcut conflict:** permission-modes registers a shortcut Pi 1.4.0 already binds; Pi skips it with a warning at startup. Harmless but visible.

## Transitive dependencies

**Risk (low):** `@narumitw/pi-btw` depends on `@narumitw/pi-tui-kit` with a floating range (`^0.64.0` → resolved 0.66.0 in this audit). Future clean installs may resolve a newer transitive version than tested.

- Mitigation: none available without vendoring (out of scope); recorded here and in TESTED_VERSIONS.md. Re-audit monthly.

## Installer behavior

**Risk (high if wrong):** a failed upgrade must leave the previous environment *working*, not merely inactive.

- Rejected design: restoring `settings.json` only. `pi remove` deletes the old package files before it checks settings, and `npm install -g` replaces the global CLI in place, so a settings-only rollback could restore a configuration that points at files the failed run had already deleted. R2 shipped that design; R3 replaced it.
- What the installer does now:
  - Stale entries are found by **Pi's package identity** (npm package name; git host+path without the ref), never by substring. String and object entries are both handled; object entries with extra keys are a reported conflict, not a rewrite.
  - Malformed or ambiguous `settings.json` stops the install before any change (Pi would otherwise exit 0 after silently failing to persist, and a malformed `packages` entry crashes Pi at startup).
  - The global Pi is installed into a staging prefix and version-checked, then activated by moving the old package aside and the new one into place. The old bin entry is saved byte-for-byte.
  - `npm/` and `git/` are **moved** (not copied) into the backup directory and worked on as copies, so `pi remove` can only destroy the copy.
  - `settings.json`, both extension files, `keybindings.json`, and `.tmux.conf` are recorded before they are written; files the run creates are recorded for removal.
  - Failure detection uses one `EXIT` trap plus `set -e` and explicit `fail`, never an `ERR` trap (bash does not inherit `ERR` into functions, command substitutions, subshells, or pipelines). Signals have their own handler. A journal covers `SIGKILL`/power loss: the next run restores before doing anything else.
  - Rollback is verified with the **real Pi extension loader**: the restored Pi must start, the restored packages must load, and the commands captured before the run must be registered again. Only then are the backups deleted; a failed verification keeps them and blocks the next run.
- Evidence: `scripts/tests/test-install-settings.sh`, `test-install-run.sh`, `test-rollback.sh` (19 failure shapes, including `SIGKILL` recovery), and `test-real-upgrade.mjs` (real Pi 1.0.2 + registry packages, a real failed upgrade, and a real loader check afterwards).
- Residual: a `SIGKILL` during the restore itself can leave a partial tree; the journal makes the next run retry, and nothing is discarded silently. Deleting `.pi-bootstrap/backup` by hand removes the ability to roll back automatically.

**Risk (low):** raw-tag downloads of `minimal-mode.ts` could change if upstream re-tags `v1.4.0`.

- Mitigation: the installer pins the tag URL *and* a SHA256 (`040cbc76…a8770`) and aborts on mismatch, then rolls back. The same protection is recommended for any future Pi-bound file.

## Environment / operational

- Node >=22.19.0 required (unchanged); enforced by the installer.
- `PI_OFFLINE=1` prevents Pi from installing `-e npm:` packages and from downloading helper binaries (fd, ripgrep) — a debugging surprise, not a defect; documented in the audit.
- The installer exports `PI_CODING_AGENT_DIR` for `pi install`, so `PI_AGENT_DIR`-style overrides and Pi's own directory variable can no longer disagree (a mismatch would have made the installer inspect a different settings file than Pi wrote).
- No sudo, no shell-profile edits, no `auth.json`/`models.json`/`advisor.json` writes, no optional installs, no bypass — verified by the test suite and by inspecting installer state across fresh, repeat, upgrade, and rollback runs.
- shellcheck is not installed on the audit host, so that gate reports SKIP rather than PASS.

## Rollback

Automatic rollback covers failure *during* a run and is verified with the real Pi loader (see above). After a successful commit there is no automatic way back: rolling back to the previous matrix is manual (`pi install` the old sources), and the previous matrix is preserved at commit `c327aaa8975bf9d0ae89112b113cf6fd244ffe49`. User configuration (`permission-modes.json`, `advisor.json`, `auth.json`, `models.json`) is never written by the installer, so it is not part of either direction.
