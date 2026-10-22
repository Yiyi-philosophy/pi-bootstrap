# Upgrade risk review — 2026-10-22 (Pi 1.4.0 matrix)

Risks, mitigations, and residual exposure for the recommended matrix. Severity reflects worst-case impact on users of this bootstrap.

## Source-built dependency

**Risk (medium):** permission-modes 2.8.0 is consumed from an upstream commit, not an npm release. The bootstrap now depends on a git checkout plus a verification manifest rather than an immutable registry artifact.

- Mitigations: the commit SHA `cf77816f28e102409dddbf8e537e4cf57aa092f0` is immutable; `pi install git:` pins and reconciles to exactly that ref; the installer independently verifies the commit HEAD, a clean tree, and a 69-file SHA256 manifest embedded in `install.sh`; the label everywhere says "source snapshot … not an npm release".
- Residual: the manifest and pins live in this repository — a compromised repository could substitute both. This is the same trust level as the installer script itself (curl | bash), unchanged in kind.
- Watch item: when upstream publishes 2.8.0 (or newer) to npm, switch the pin to the npm release and re-verify; the 2.7.0 precedent (npm tarball byte-identical to the git tag) makes this expected to be a no-op, but it must be re-checked, not assumed.

**Risk (low):** the git checkout lives under `~/.pi/agent/git/…` with a full `.git` directory and npm-generated `package-lock.json`.

- Mitigation: the manifest covers exactly the tracked files Pi loads; extra files (`.git`, lockfile) are inert. `pi update` is never run by the bootstrap and reconciles only to the pinned ref.

## Classifier and permission-gate security

**Risk (high if unmitigated):** classifier errors must never silently grant unsafe permissions.

- Evidence: transport faults (malformed JSON, empty stream, timeout) produce no silent allow; the extension gate blocks after exactly 3 bounded attempts unless `failClosed: false` was explicitly set by the user; `maxRetries: 0` prevents stacked invisible retries (worst-case wait `timeoutMs × 3`).
- Note: with `failClosed: false` (explicit user opt-out) the gate falls back to local tier rules + prompting, never to silent bypass.

**Risk (medium):** the October 2026 baseUrl bug could reappear through a future regression.

- Mitigation: the deterministic reproduction harness from this audit (2.7.0 fails / 2.8.0 passes) is preserved in the audit workspace and described in `upgrade-audit-2026-10.md`; the monthly audit must re-run it whenever the permission-modes pin changes.

**Risk (low):** credential forwarding to the wrong host via the resolved `baseUrl` path.

- Evidence: in the fixed path the credential header appears only on requests to the resolved host; the mock recorded no other host receiving traffic. The regression case (2.7.0) fails closed rather than sending credentials elsewhere — the request to the wrong URL used the same classifier API key, which is worth noting: the pre-fix behavior sent the classifier credential to the model's catalog URL. Users who ran 2.7.0 with a custom-baseUrl classifier model should rotate that key if the catalog URL was untrusted.

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

**Risk (medium if wrong):** upgrades must not leave two permission-modes versions installed.

- Evidence: the stale-entry removal was tested against a seeded 1.0.2 baseline; both an npm→git transition and version bumps for btw/advisor leave exactly one entry per package. Two real bugs in the removal helper were found and fixed during this audit (see audit doc) — re-run the upgrade-path test whenever the helper changes.
- Residual: `pi remove` leaves the old npm package's files on disk (unreferenced). Harmless; Pi only loads settings-referenced packages.

**Risk (low):** raw-tag downloads of `minimal-mode.ts` could change if upstream re-tags `v1.4.0`.

- Mitigation: the installer pins the tag URL *and* a SHA256 (`040cbc76…a8770`) and aborts on mismatch. The same protection is recommended for any future Pi-bound file.

## Environment / operational

- Node >=22.19.0 required (unchanged); enforced by the installer.
- `PI_OFFLINE=1` prevents Pi from installing `-e npm:` packages and from downloading helper binaries (fd, ripgrep) — a debugging surprise, not a defect; documented in the audit.
- No sudo, no shell-profile edits, no `auth.json`/`models.json`/`advisor.json` writes, no optional installs, no bypass — verified by inspecting the installer output state across fresh, repeat, and upgrade runs.

## Rollback

Documented in `upgrade-audit-2026-10.md`; the previous matrix is preserved at commit `c327aaa8975bf9d0ae89112b113cf6fd244ffe49`. Rollback does not touch user configuration.
