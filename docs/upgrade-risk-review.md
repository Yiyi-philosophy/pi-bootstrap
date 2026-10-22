# Upgrade risk review — 2026-10-22 (Pi 1.4.0 matrix)

Risks, mitigations, and residual exposure for the recommended matrix. Severity reflects worst-case impact on users of this bootstrap. Updated by R2 ([`r2-closure-report.md`](r2-closure-report.md)), which closed the installer and test-coverage findings.

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

**Risk (medium if wrong):** upgrades must not remove another package, must not leave two permission-modes versions installed, and must not leave a half-activated matrix.

- Mitigations:
  - Stale entries are found by **Pi's package identity** (npm package name; git host+path without the ref), never by substring, and are removed with `pi remove` so Pi's own bookkeeping stays consistent. String and object entries are both handled; object entries with extra keys are a reported conflict, not a rewrite.
  - Malformed or ambiguous `settings.json` stops the install before any change (Pi would otherwise exit 0 after silently failing to persist, and a malformed `packages` entry crashes Pi at startup).
  - A `pi remove` failure is fatal, never swallowed: Pi deletes package files before it checks settings, so a "not found" can have destroyed the install.
  - `settings.json` is snapshotted and replaced extension files are backed up before the first change; any later failure restores them, which deactivates a partial matrix (the installed package files may remain on disk, but Pi only loads what settings lists).
- Evidence: `scripts/tests/test-install-settings.sh` (14 cases: string/object entries, npm→git, version bumps, look-alike names, unrelated packages, six malformed inputs, remove failure, verify mode) and `scripts/tests/test-install-run.sh` (fresh, repeat, upgrade from 1.0.2, wrong commit, tampered tree, tampered file, missing file, rollback, post-rollback re-run, malformed settings).
- Residual: `pi remove` leaves the old npm package's files on disk (unreferenced). Harmless; Pi only loads settings-referenced packages.

**Risk (low):** raw-tag downloads of `minimal-mode.ts` could change if upstream re-tags `v1.4.0`.

- Mitigation: the installer pins the tag URL *and* a SHA256 (`040cbc76…a8770`) and aborts on mismatch, then rolls back. The same protection is recommended for any future Pi-bound file.

## Environment / operational

- Node >=22.19.0 required (unchanged); enforced by the installer.
- `PI_OFFLINE=1` prevents Pi from installing `-e npm:` packages and from downloading helper binaries (fd, ripgrep) — a debugging surprise, not a defect; documented in the audit.
- The installer exports `PI_CODING_AGENT_DIR` for `pi install`, so `PI_AGENT_DIR`-style overrides and Pi's own directory variable can no longer disagree (a mismatch would have made the installer inspect a different settings file than Pi wrote).
- No sudo, no shell-profile edits, no `auth.json`/`models.json`/`advisor.json` writes, no optional installs, no bypass — verified by the test suite and by inspecting installer state across fresh, repeat, upgrade, and rollback runs.
- shellcheck is not installed on the audit host, so that gate reports SKIP rather than PASS.

## Rollback

Documented in `upgrade-audit-2026-10.md`; the previous matrix is preserved at commit `c327aaa8975bf9d0ae89112b113cf6fd244ffe49`. Automatic rollback covers failure *during* a run; rolling back to the previous matrix afterwards is manual and does not touch user configuration.
