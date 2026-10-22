# R2 closure report — review findings F1–F7

Baseline: `076f1c3df50f66e6d4b3fbb540e88028a6695d9c` (Pi 1.4.0 matrix). Branch: `r2-review-fixes`.
Scope: engineering-quality findings from an independent review of that commit. **No version pins changed** — the matrix stays Pi 1.4.0 / permission-modes 2.8.0 @ `cf77816` / pi-btw 0.62.0 / pi-advisor-flow 0.14.2 / minimal-mode v1.4.0 / current `classifier-model.ts`.

Result: **PASS** (one item partially closed by design — F2, see its "residual" note). Every claim below is backed by a committed script; `scripts/tests/run-all.sh` is the single entry point.

## F1 — Exact matching of old packages: FIXED

The old helper selected entries with `entry.includes(filter)` and `|| true`. Replaced by `settings_tool()` in `install.sh`, which mirrors Pi's own package identity:

- npm → package name only; git → host + path with the ref stripped. Matching is therefore by package, never by substring, and an `npm:@georgedong32/permission-modes@2.7.0` entry is recognized as the same package the git pin replaces.
- String entries and object entries are both handled; entries for unmanaged packages, local paths, and look-alike names are left untouched.
- An object entry carrying any key besides `source` (Pi resource filters, `autoload`) is reported as a conflict and the run stops: Pi would otherwise rewrite the entry and drop filters, so the user migrates it by hand.
- Malformed settings (invalid JSON, non-object root, non-array `packages`, `null` entries, entries without a string `source`) produce an explicit conflict and **no writes**. Pi itself treats an unreadable settings file as empty and still exits 0, so this is checked before anything else.
- `pi remove` failures are fatal. Pi deletes package files *before* it looks up the settings entry, so a swallowed "not found" could leave a destroyed package behind.
- Removal is verified afterwards: if a stale managed entry is still present, the run fails instead of continuing.
- `main` exports `PI_CODING_AGENT_DIR` before calling `pi`, so the settings file the installer inspects is the one Pi writes, whatever override style the user used.

Tests: `scripts/tests/test-install-settings.sh` (string/object entries, npm→git, version bump, look-alike, unrelated local + npm packages, six malformed inputs, `pi remove` failure, verify mode) and the upgrade case in `scripts/tests/test-install-run.sh`.

## F2 — Install-time safety: FIXED, with one documented residual

The review's ordering concern was real, and worse than stated: `pi install <git>` clones, checks out, and then runs `npm install --omit=dev --legacy-peer-deps` **inside the checkout with lifecycle scripts enabled**, before Pi writes settings. Pi 1.4.0 exposes no flag or `PI_*` variable to disable them.

What the installer does now, in order:

1. **Pre-install verification.** `git init` a staging repository, fetch only the pinned commit (`--depth 1`), check it out, verify commit, `HEAD^{tree}`, clean working tree, and all 69 SHA256 checksums. Nothing from the source runs before this passes.
2. **Lifecycle suppression.** `npm_config_ignore_scripts=1` is exported for managed installs, so no `preinstall`/`install`/`postinstall`/`prepare` runs. Both npm packages and the pinned source ship prebuilt files, so nothing is lost. `npm install -g` for Pi itself keeps `--ignore-scripts`.
3. **Fixed reference only.** The install source is the `git:…@<40-hex commit>` string; no branch, tag, `latest`, temp path, or local checkout is ever used as the installed reference.
4. **Post-install verification.** The checkout Pi produced is re-verified (commit, tree, clean tree, 69 checksums, tracked-file count), and `settings.json` must list exactly the pinned sources.

Evidence: `scripts/tests/test-install-lifecycle.mjs` proves both halves against the real Pi CLI with a probe package over localhost — with the variable no lifecycle script runs, without it all three do. `test-install-run.sh` proves a wrong commit, a tampered tree, a tampered file, and a missing file are each rejected, and that a failed pre-check installs nothing.

**Residual (stated, not claimed away):** this is pre-execution verification of *content*, plus suppression of lifecycle scripts — not a sandbox. The `npm install` Pi runs still resolves the pinned `package.json`'s runtime dependencies from the registry. Today that manifest declares only `peerDependencies` (suppressed), so nothing is fetched, but a future pin with real `dependencies` would need review before adoption. Recorded in `docs/upgrade-risk-review.md`.

## F3 — Failure recovery: FIXED

- Preflight validates commands, Node.js, `HOME`, and settings readability/ambiguity before any change.
- `settings.json` is snapshotted to `<agent>/ .pi-bootstrap/settings.json.snapshot` before the first mutation; each extension file the run will replace is backed up, and files it creates are recorded.
- Failures after that point call `recover()`: settings are restored (or removed if the run created them), replaced extension files are restored, created files are deleted. Restoring `settings.json` is what deactivates a partial matrix, because Pi loads only what settings lists. Package files may remain on disk; they are unreferenced, and the message says so.
- An unexpected non-zero exit is caught by an `ERR` trap installed inside `main` and routed through the same rollback.
- Rollback runs once (guarded), with `set +e`, so it cannot loop or mask the original error.

Tests: `test-install-run.sh` case 8 fails a run after the mutation point and asserts settings and extension bytes are byte-identical to the pre-run state; case 9 re-runs to convergence; case 10 confirms malformed settings stop the run before any change.

## F4 — Reproducible tests: FIXED

The 2026-10 harnesses were absolute-path, `/tmp`-bound scripts that would write into the developer's real `~/.pi` if run outside their hand-built environment. They are now committed, path-independent, and isolated:

| Script | Replaces / covers |
|---|---|
| `scripts/tests/test-classifier-baseurl.mjs` | the 2.7.0 → 2.8.0 baseUrl regression on a real `ModelRegistry` + loopback mock, including malformed/empty/timeout faults and the "one attempt per call" bound |
| `scripts/tests/test-permission-gate.mjs` | real-loader gate battery: fail-closed with exactly 3 attempts, allow/deny, embedded `then_run`, powershell, outside-cwd, `/classifier-model` |
| `scripts/tests/test-classifier-config.mjs` | classifier JSON safety: merge, disable, timeout/permission preservation, invalid JSON, atomic write, reload failure, unwritable directory |
| `scripts/tests/test-install-settings.sh` | settings identity matching and fail-closed handling (F1) |
| `scripts/tests/test-install-run.sh` | fresh, repeat, upgrade, pre-install verification, tamper detection, rollback (F2/F3) |
| `scripts/tests/test-install-lifecycle.mjs` | lifecycle-script suppression against the real Pi CLI (F2) |
| `scripts/tests/test-rpc-smoke.mjs` | headless Pi start, command registration and invocation |
| `scripts/tests/test-default-stack.mjs` | all five default extensions on one loader |
| `scripts/tests/test-pin-helper.sh` | the pin-generation helper (F7) |

Isolation rules, enforced by `scripts/tests/lib.sh` / `run-all.sh`: every test gets its own scratch `HOME` and `TMPDIR`; fake `pi`/`npm`/`curl`/`tmux` come from `scripts/tests/fixtures/`; model traffic goes to loopback mocks; fixtures use empty `auth.json` and `apiKey: "audit-placeholder"`. No token, no real `~/.pi`, no network for the offline suite. No large logs are committed.

`run-all.sh` treats exit 77 as SKIP and prints the skip list, so "not exercised" is visible in the summary rather than blended into green.

## F5 — tmux coverage: FIXED

`scripts/test-tmux.sh` now runs `3.1`, `3.2`, `3.3a`, `3.4`, `3.5`, `3.5a`, `3.6` (3.3a was the documented-but-missing case; a naive addition would also have asserted `csi-u` for it, contrary to the minor-version rule). Added: downgrade from 3.5 to 3.1, a config without a trailing newline, an unparseable version, and a `tmux source-file` failure. It runs in an isolated `HOME` with a stub `tmux`, and the caller's EXIT trap survives sourcing `install.sh` (trap installation moved into `main`).

## F6 — Documentation accuracy: FIXED

- `README.md`: `<USER>` replaced with `Yiyi-philosophy`; new "How the install is protected" section describing the real order and the lifecycle-script suppression; "Files and safety" now lists exactly what is written, including `.pi-bootstrap/`; testing section lists the real, committed suites.
- `TESTED_VERSIONS.md`: status key added; cells that were interactive-audit evidence are marked as such instead of reading like committed tests; upstream's suite is described as **not fully green** (439–440/441, never 441/441 on the audit host) with both causes retained; optional-plugin rows are explicitly "TESTED (load) at most" with the `PI_OFFLINE` trap noted.
- `docs/upgrade-audit-2026-10.md`: `<USER>` replaced; harness references point at the committed scripts; the tmux 3.3a omission in the original run is stated; evidence index no longer implies `/tmp` transcripts are durable.
- `docs/monthly-maintenance-prompt.md`: the test section now names the committed suite instead of a list of aspirations; the manifest is regenerated by the helper, never hand-edited; a PASS recorded before the last edit is explicitly not acceptance.
- `docs/upgrade-risk-review.md`: rewritten with the install-time execution risk, the F1/F3 evidence, and the residual risks.

## F7 — Long-term maintenance cost: PARTIAL (evaluated, deliberately kept)

The 69-line SHA256 manifest **stays**. Considered and rejected: a single aggregate hash (loses which file failed, which is the one thing that makes low-cost review possible), tree-SHA-only verification (couples content checks to git's SHA-1 object hashing), and dropping pre-install verification (makes F2 worse).

What changed is the *cost of maintenance*, not the security:

- The manifest is generated **only** by `scripts/update-permission-modes-pin.sh`, which refuses a dirty or commit-less checkout and rewrites commit, tree, count, and file list in one operation; its check mode doubles as a CI/PR assertion. Hand-editing is no longer needed or expected.
- Tested by `scripts/tests/test-pin-helper.sh` (mismatch detection, atomic rewrite, acceptance, dirty refusal, empty-checkout refusal).
- A pinned git tree was added next to the file manifest: added/removed files are detected even if hashing were ever mistrusted, and the failure message names the tree.

## Modified files

| File | Change |
|---|---|
| `install.sh` | identity-exact migration with fail-closed settings handling; pre-install verification in a staging clone; `npm_config_ignore_scripts=1`; settings snapshot + rollback; `PI_CODING_AGENT_DIR` alignment; pinned tree; trap installation moved into `main` |
| `scripts/check-embedded-extension.sh` | still compares bytes; now also fails if the heredoc cannot be extracted or if the delimiter appears more than once |
| `scripts/test-tmux.sh` | 3.3a, downgrade, no-trailing-newline, unparseable version, reload failure; isolated `HOME`; trap preserved |
| `scripts/update-permission-modes-pin.sh` | **new**: generate/verify the pin block |
| `scripts/tests/lib.sh`, `lib-pi.mjs`, `fixtures/*` | **new**: isolation helpers, Pi resolver, fake `pi`/`npm`/`curl`/`tmux` |
| `scripts/tests/test-*.sh`, `test-*.mjs`, `run-all.sh` | **new**: the suite described above |
| `README.md`, `TESTED_VERSIONS.md`, `docs/*.md` | accuracy fixes, new protection/risk sections, this report |

## Acceptance gates

| Gate | Result |
|---|---|
| `bash -n install.sh` | PASS |
| shellcheck | SKIP (not installed on this host; no system packages installed to obtain it) |
| `scripts/check-embedded-extension.sh` | PASS |
| tmux suite (7 versions + edge cases) | PASS |
| old → new migration | PASS |
| idempotent install | PASS |
| unrelated packages preserved | PASS |
| removal failure and recovery | PASS |
| SHA/file tamper detection | PASS |
| real HTTP baseUrl regression | PASS (2.7.0 fails, 2.8.0 passes) |
| classifier fail-closed | PASS (exactly 3 attempts) |
| core plugin load + RPC smoke | PASS |

Final run — a **completely fresh isolated environment**, not the audit workspace: Pi 1.4.0 installed into a new prefix with `npm install -g --ignore-scripts`, the pinned permission-modes commit installed with `pi install git:…@cf77816`, permission-modes 2.7.0 fetched fresh from npm for the regression fixture, a new `HOME`, and a new npm cache:

```text
== static checks           embedded classifier-model.ts is in sync; SKIP shellcheck: not installed
== installer behavior      10 + 11 + 5 + 6 PASS
== extension behavior      10 PASS
== real runtime            2 + 8 + 7 + 2 + 3 PASS

summary: 20 passed, 1 skipped, 0 failed
skipped: shellcheck install.sh
```

The PASS recorded before the final refactor was not treated as acceptance; this run was performed after the last code change.

## Remaining risks (not closed)

- **shellcheck never ran** on this host. The scripts are `bash -n` clean and exercised, but a shellcheck gate should be added where it is installed.
- **TUI-level behavior** (`/btw` and `/advisor` completing against a fixture, selector dialogs in a real terminal) is 2026-10 interactive evidence, not a committed test: the pty harness depended on a hand-built agent tree. RPC-level registration and invocation are committed.
- **Optional plugins** remain TESTED (load) only, from an ad-hoc script that was not committed because it depends on live npm installs.
- **Upstream test suite** stays 439–440/441 (environment artifact + upstream isolation flaw) — reported, not patched.
- **TUI, multi-turn sessions, and real credentials**: UNVERIFIED, unchanged from the 2026-10 audit.
- **Install-time dependency resolution** (F2 residual) is not sandboxed; see F2.

## Local commits

| Commit | Contents |
|---|---|
| `0e92857` | installer hardening (F1/F2/F3), committed test suite (F4/F5), documentation accuracy (F6), pin helper (F7) |
| `93b7f03` | bash <4.4 empty-array guard in `recover()`, one shared settings-plan parser, unused test helpers removed |

Both are local on `r2-review-fixes`; nothing was pushed, merged, or tagged.

## Final verdict

**PASS.** F1, F3, F4, F5, F6 FIXED; F2 FIXED with a documented residual; F7 PARTIAL by deliberate choice (kept the per-file manifest, automated its generation, added a test for the helper). No version pins changed, no push, merge, tag, or production Pi configuration touched.
