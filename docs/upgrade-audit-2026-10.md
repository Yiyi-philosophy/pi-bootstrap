# October 2026 upgrade audit — Pi 1.4.0 matrix

Date: 2026-10-22 (UTC). Result: **PASS — recommended matrix adopted in this working tree.**

Previous confirmed snapshot: commit `c327aaa8975bf9d0ae89112b113cf6fd244ffe49` (Pi 1.0.2 / permission-modes 2.7.0 / pi-btw 0.61.1 / pi-advisor-flow 0.11.0). The October 16 audit (`/tmp/pi-oct2026-audit/REPORT.md`) rejected Pi 1.3.0 because published permission-modes 2.7.0 ignored authentication-resolved custom `baseUrl`. This audit re-ran that reproduction and verified the fix.

## Old vs. recommended matrix

| Component | Old (c327aaa) | Recommended | Provenance |
|---|---|---|---|
| Pi Coding Agent | 1.0.2 | 1.4.0 | official npm release |
| permission-modes | 2.7.0 (npm) | 2.8.0 @ `cf77816f28e102409dddbf8e537e4cf57aa092f0` | **source snapshot, not npm**; pinned commit + SHA256 manifest |
| pi-btw | 0.61.1 | 0.62.0 | official npm release |
| pi-advisor-flow | 0.11.0 | 0.14.2 | official npm release |
| classifier-model.ts | repository | unchanged | local |
| minimal-mode.ts | Pi v1.0.2 tag | Pi v1.4.0 tag | exact release tag URL + SHA256 pin |

npm facts checked on 2026-10-22: `@earendil-works/pi-coding-agent` dist-tags `latest=1.4.0` (published 2026-10-21, engines `>=22.19.0`); `@georgedong32/permission-modes` dist-tags `latest=2.7.0` and **no 2.8.0 in the versions map** (404); `@narumitw/pi-btw` `latest=0.62.0`; `pi-advisor-flow` `latest=0.14.2` (peers `^1.0.0`); `pi-retry` absent from the registry (404).

## Approach decision for permission-modes (A vs. B vs. C)

- **A (chosen): pinned 2.8.0 source snapshot.** Pi 1.4.0 natively supports `pi install git:github.com/owner/repo@<commit>` with pinned commits (documented in its `packages.md`); the installer pins the immutable commit and independently verifies a 69-file SHA256 manifest so no trust is placed in GitHub availability or in git's SHA-1 object hashing alone. Includes upstream B1 (embedded-command gate for fusion tools, PowerShell mapping onto the bash approval surface) and B2 (classifier through `ctx.modelRegistry.complete()` with the resolved `baseUrl`), plus the bounded single-layer retry (`maxRetries: 0` at the SDK layer, `MAX_CLASSIFIER_FAILURES = 3` above it).
- **B (rejected): 2.7.0 + backported B2.** B2 is a substantial classifier-client rewrite; carrying a private fork loses B1's security work, diverges from the eventual official 2.8.0, and multiplies patch provenance concerns. Nothing in 2.7.0 published form is preferable.
- **C (fallback, not needed):** retain the old matrix — available as the documented rollback.
- 2.6.x was never considered: it predates 2.7.0's fixes and B1/B2 entirely.
- Evidence that the snapshot is publish-equivalent: the published npm 2.7.0 tarball is **byte-identical** (51/51 files) to the `v2.7.0` git tag `4005e71`, and the snapshot's `package.json` `files` field is unchanged — so when upstream publishes 2.8.0 to npm, switching the pin from the git source to `npm:@georgedong32/permission-modes@2.8.0` should be a no-op byte-for-byte (re-verify at that time).

## Classifier regression: reproduction and fix (HTTP-level evidence)

Harness: `/tmp/pi-oct2026-upgrade/bin/classifier-baseurl-regression.mjs` — one real Pi 1.4.0 `ModelRegistry` (via `ModelRuntime.create`) with a native provider whose `ApiKeyAuth.resolve()` returns a per-credential `baseUrl` (the documented credential-dependent routing case, pi-ai `auth/types.ts`), and a local HTTP mock whose only valid route is the resolved URL.

1. Sanity: `find()` returns the model with catalog `baseUrl` B; `getApiKeyAndHeaders()` returns `{ok, apiKey, baseUrl: A}` with A ≠ B (divergence active).
2. **2.7.0 (published npm, unmodified): FAILS** — the classifier posts to B, the mock tripwire answers 400 `Classifier ignored resolved auth.baseUrl`, the call errors. Regression deterministically reproduced.
3. **2.8.0 (snapshot cf77816): PASSES** — `registry.complete()` routes through `ModelRuntime.prepareRequest`, which applies `resolution.auth.baseUrl` over the model; requests land on A with the `Authorization` header, correct `classify_result` tool schema and forced tool choice, and valid allow/deny verdicts.
4. Faults (malformed SSE JSON, empty stream, timeout): no silent allow; exactly one HTTP attempt per call (no stacked SDK retries — `maxRetries: 0`).

Extension-gate evidence (real Pi 1.4.0 loader, `/tmp/pi-oct2026-upgrade/bin/extension-gate-test.mjs`): classifier unavailable → fail-closed block with exactly 3 attempts; classifier deny blocks / allow passes; B1 `then_run` embedded commands surface in ask prompts and are blocked in plan; `powershell` runs the bash tier ladder; unknown tools without command fields keep their characterized passthrough; outside-cwd writes gated; `/classifier-model` persists and reloads.

## Upstream issues and PR

- **#3** reproduced (see TESTED_VERSIONS.md). Mechanism unchanged from 2.7.0; no patch applied (UX issue, would fork upstream).
- **#4** structurally unchanged in 2.8.0 (system-prompt mode block rebuilt per turn; changes on mode switch / plan progress). Same in 2.7.0 — not a regression of this upgrade.
- **PR #1** (closed, unmerged): `temperature` is still sent for `openai-codex-responses` classifiers in 2.8.0 — documented; Codex models must not be selected as classifier (fails closed if they are).

## Upstream test suite on the snapshot

439–440/441 pass across repeated runs. Failures analyzed:
- `utils.test.ts findProjectRoot "returns null when no markers found"` — fails only because this audit host has a stale `/tmp/.git` directory (predating the audit); passes with a clean TMPDIR outside `/tmp`. Environment artifact.
- `index.test.ts` auto-mode classifier tests ("fail-closed when classifier is unavailable", "classifier retry loop is bounded…") — intermittent under full-file execution, deterministic in isolation (verified 3/3). Upstream test-isolation flaw: module-level shared state (verdict cache, 60 s TTL) couples tests that reuse `bash { command: "npm install lodash" }`. The runtime bound was re-verified independently on the real loader. Recommend filing upstream; not an adoption blocker.
- 2.7.0's own suite passes deterministically (403/403, 3 runs) — the flakiness was introduced by 2.8.0's expanded tests, not by the cache itself (the cache shipped in 2.7.0's parent commit `c22031c`).

Typecheck: `tsc --noEmit` with devDependencies pinned to Pi 1.4.0 — production sources clean; the 7 errors are confined to upstream's own test files (fake-pi surface drift between Pi 0.85.1 and 1.4.0). Log: `/tmp/pi-oct2026-upgrade/evidence/typecheck-pi140.log`.

## Isolated integration tests (all under `/tmp/pi-oct2026-upgrade`)

- Node 24.14.0 / npm 11.9.0; `bash -n install.sh` PASS; `git diff --check` PASS; shellcheck not installed (SKIP — no system packages were installed to obtain it); `scripts/check-embedded-extension.sh` PASS; tmux suite (`scripts/test-tmux.sh`) PASS for 3.1/3.2/3.4/3.5/3.5a/3.6 incl. migration + idempotence; no tmux server was contacted.
- Fresh-home installer run + repeat: byte-identical `.pi/agent` state (excluding `.git`), stable `settings.json` (exactly the three pinned sources), no `auth.json`, `models.json`, or `advisor.json` created; keybinding merge correct; minimal-mode.ts SHA256 matches the v1.4.0 tag pin; classifier-model.ts byte-identical to the repository source.
- Upgrade-path run (old 1.0.2 baseline seeded exactly, plus an unmanaged package entry and a user `permission-modes.json`): stale `npm:…permission-modes@2.7.0`, `pi-btw@0.61.1`, `pi-advisor-flow@0.11.0` entries removed via `pi remove` (two installer bugs found and fixed during the audit: an illegal top-level `return` in the removal helper's node script, and a filter string that matched the git repo name but not the npm package name); unmanaged entry and user config preserved; verified 2.8.0 ends up as the only permission-modes source. `pi remove` leaves the old npm package's files on disk (unreferenced; harmless).
- Tamper tests: modified tracked file → `verify_permission_modes` dies ("working tree has local modifications"); missing tracked file → dies; the SHA256 manifest provides defense-in-depth independent of git status.
- RPC startup on the installed CLI: all default commands registered, invocations succeed, `/btw` correctly requires TUI. TUI (pty): all five extensions load together; `/classifier-model`, `/advisor-models`, `/mode` open and cancel; `/btw` streams a real answer from the loopback fixture; `/advisor` completes a full `ask_advisor` consultation (executor model distinct from advisor model — same-model guard verified separately), and an uncredentialed advisor yields a clean error, not a crash.
- Advisor persistence: `advisor.json` is created only through explicit selector interaction; blind-Enter defaults are user-visible and user-fixable.
- classifier JSON-safety battery (merge, disable w/ retained model, timeout preservation, permission-rule preservation, invalid/non-object JSON refusal, cancellation, cached-registry fallback, no-UI guard, reload-failure fallback, atomic-rename-failure cleanup) — ALL PASS on the installer-produced environment.
- Optional plugins: load smoke on the installed Pi 1.4.0 (see TESTED_VERSIONS.md). Note: `PI_OFFLINE=1` silently prevents `-e npm:` package installation — early "loads" results without it were invalid and were discarded and re-run.

### UNVERIFIED (explicitly)

- Real interactive multi-turn sessions with real provider credentials (no credentials were used; all model traffic was loopback fixtures).
- Actual modified-key forwarding through each tmux release (stubbed version branches only, as in prior audits).
- Optional plugins' core functionality (subagent execution, MCP connections, LSP servers, service-tier effect) — load/registration only.
- `pi update` interactions with the git-pinned source (the bootstrap never runs `pi update`; `pi update --extensions` reconciles git sources to their pinned ref per Pi docs, but this was not exercised).

## Rollback procedure

The previous matrix remains available at commit `c327aaa8975bf9d0ae89112b113cf6fd244ffe49`:

```bash
# 1. Remove the source-built permission-modes and its settings entry
pi remove "git:github.com/GeorgeDong32/pi-permission-modes@cf77816f28e102409dddbf8e537e4cf57aa092f0"

# 2. Run the previous installer (old pins: Pi 1.0.2, permission-modes 2.7.0 npm,
#    pi-btw 0.61.1, pi-advisor-flow 0.11.0, minimal-mode v1.0.2)
git clone https://github.com/<USER>/pi-bootstrap.git
cd pi-bootstrap
git checkout c327aaa8975bf9d0ae89112b113cf6fd244ffe49
./install.sh
```

User files (`permission-modes.json`, `advisor.json`, `auth.json`, `models.json`) are not touched by either direction; the 2.7.0/2.8.0 classifier config fields are the same shape, so a configured classifier model survives rollback.

## Evidence index

- `evidence/classifier-baseurl-regression.json` — full request/verdict records for 2.7.0 (fail) and 2.8.0 (pass).
- `evidence/permission-modes-2.8.0-cf77816.SHA256SUMS` — the 69-file manifest (embedded in `install.sh`).
- `evidence/extension-gate-test.json`, `bin/extension-gate-test.mjs` — real-loader gate battery.
- `evidence/typecheck-pi140.log` — tsc output against Pi 1.4.0 types.
- `evidence/rpc-stdout.jsonl`, `evidence/rpc-stderr.log` — RPC startup records.
- `evidence/tui-output.log`, `evidence/advisor-consult-output.log`, `evidence/advisor-consult-requests.json` — pty sessions.
- `evidence/install-first.log`, `install-second.log`, `install-third.log`, `upgrade-run.log`, `upgrade-run2.log`, `inst-snapshot-*.txt` — installer runs.
- `evidence/issue3-summary.md`, `evidence/issue3-repro.log` — issue #3 reproduction.
- `evidence/optional-smoke.json` — optional plugin results.
