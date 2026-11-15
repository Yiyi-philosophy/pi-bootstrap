# November 2026 upgrade audit

Initial audit date: **2026-11-14**, America/Los_Angeles. Base: `main` at `a4fea2bcc70ca62b97b988d4efb3de0b6cc7a8ef`. Host: macOS arm64, Node **24.22.1**, npm **11.19.1**. Machine-readable results: [`evidence/2026-11-14.json`](evidence/2026-11-14.json).

Final acceptance: **2026-11-15**, America/Los_Angeles. Candidate base: `bc4cbe1d8d91752fcf006916fcda641341d87364`. This follow-up keeps every pin and the generated installer unchanged. Current machine-readable results: [`evidence/2026-11-15.json`](evidence/2026-11-15.json). Package metadata, release decisions, optional-package checks and upstream issue states below remain dated November 14.

## Accepted matrix

| Component | Previous main | Accepted | Decision |
|---|---:|---:|---|
| Pi Coding Agent | 1.4.0 | **1.5.2** | npm stable/latest and matching GitHub release verified; full default stack exercised |
| `@narumitw/pi-btw` | 0.62.0 | **0.63.8** | Published stable, real side-question request and controlled UI passed |
| `pi-advisor-flow` | 0.14.2 | **0.15.1** | Published stable, selectors and full consultation passed |
| permission-modes | 2.8.0 source | unchanged | npm still 2.7.0; upstream master remains `cf77816f28e102409dddbf8e537e4cf57aa092f0`; retain the previously documented source exception |
| minimal-mode | v1.4.0 tag | **v1.5.2 tag** | Bytes unchanged; exact release URL and existing hash verified |
| classifier-model | local | unchanged | Current APIs and behavior pass on Pi 1.5.2 |

Pi 1.5.2 was published on November 10, BTW 0.63.8 on November 11, and Advisor 0.15.1 on November 14. Only stable published versions were adopted. The permission-modes commit/tree/69-file SHA256 manifest are unchanged; it is still a source snapshot, **not** an official npm 2.8.0 release.

Pi's internal packages are exact 1.5.2 dependencies and require Node >=22.19.0. BTW peers accept current Pi and its UI dependency is `@narumitw/pi-tui-kit ^0.70.0` (resolved 0.70.0). Advisor peers remain Pi `^1.0.0` and TypeBox `^1.1.38`, with development dependencies targeting Pi 1.5.2. Floating transitive dependencies remain an upstream reproducibility limit.

## Why update

Pi 1.5 adds package changelogs, rendering improvements, provider/authentication fixes, shell login commands, and improved handling of sessions whose working directory moved. BTW adds explicit main-thread context import and fixes deep-history stack overflow, lazy UI startup and terminal lifecycle behavior. Advisor adds virtual-model support and session-id forwarding; 0.15.1 fixes header-only authentication and repeated update notices. The audit tests the ordinary authenticated request paths; it does not independently certify every new upstream feature.

## Configuration changes to review

The installer continues to preserve user-selected configuration. Current-main migration tests compare `auth.json`, `models.json`, `permission-modes.json`, and `advisor.json` byte for byte and retain unrelated settings. No provider, endpoint, model, permission rule, bypass mode or optional package is selected by installation.

Upstream changes that may need explicit user action:

- Azure provider `azure-openai-responses` becomes `azure`. Migrate keys/references in auth, model definitions and settings according to the release notes. The bootstrap does not rewrite them.
- `cacheWarming` now defaults to `idle`, keeping eligible caches warm between runs. Set `"cacheWarming": "streaming"` in Pi settings for the previous behavior; existing explicit settings are preserved.
- OpenAI-compatible requests omit empty `tools` arrays. Older proxies requiring tools after tool history may need `compat.requiresToolsWithToolHistory: true` in their model configuration.

## Acceptance evidence

**Final execution PASS: 34 real gates / 0 FAIL / 0 SKIP; 78 offline tests / 0 FAIL / 0 SKIP; ShellCheck 0.11.0 PASS with zero diagnostics.**

All 34 real gates ran in **one uninterrupted invocation** of the corrected `scripts/test-real.mjs`, from **2026-11-15T13:23:13.616Z** to **2026-11-15T13:40:50.419Z** (1057 seconds). No earlier or focused PASS was reused. The complete offline suite, including fixture isolation, was rerun after the fixture changes and passed all 78 tests with no cancellations or TODOs. Generated-installer consistency, embedded-extension consistency, individual syntax checks for all three Shell files, and whitespace checks passed.

The November 14 record assembled 34 gates from separate runs; that JSON remains unchanged as historical evidence. Its four optional-package install/load checks were **not rerun** in this follow-up and are not included in the current totals.

### Closing the integrated-run coverage gap

Inspection found that the committed runner actually integrated **33** gates: the historically recorded RPC startup check was missing. The minimal fixture change uses Pi's published `RpcClient` to start the real CLI in RPC mode, request `get_commands`, and stop the process. The integrated runner asserts that `classifier-model`, `mode`, `btw`, `advisor`, `advisor-models`, `advisor-settings` and `advisor-stats` all register as extension commands. No production installer, dependency pin, assertion or failure case was weakened.

A preliminary run was intentionally stopped after 12 completed gates, with no active child operation, when this missing coverage was identified. It is not a full acceptance result. The RPC check passed independently in scratch, then the corrected complete runner started from another newly created outer scratch with empty HOME/prefix/cache/npmrc/Pi directories. Its fresh-install, historical 1.0.2 and previous-main 1.4.0 scenarios each used a separate guarded child scratch. All install, rollback and recovery operations stayed inside those roots; host HOME, npm globals, Pi configuration, credentials and historical backups were not modified.

### Failed integrated attempt and recovery

The first corrected integrated attempt stopped with **11 completed PASS gates and one failure**, leaving 22 further required gates unreached. During the old 1.0.2 upgrade, npm reached the unchanged production **180-second** subprocess timeout while dependency metadata requests were outstanding, before the expected `after:cli` injection. Its transaction restored the real 1.0.2 loader successfully. Subsequent scratch registry probes returned HTTP 200. Replaying the affected upgrade in the retained scratch completed npm, reached the expected injected failure, and proved complete managed-inventory and old-loader equality after rollback. The exact remote cause of the transient stall is not established.

No timeout, assertion, production code or pin was changed to bypass that failure. Both the failed attempt and focused replay remain separate records; neither contributes a PASS to the final 34-gate result, which was rerun from another empty scratch. This network dependency remains a reproduction risk.

### Closing the ShellCheck gap

ShellCheck **0.11.0** was obtained as the official `koalaman/shellcheck` release asset `shellcheck-v0.11.0.darwin.aarch64.tar.xz`. Its SHA256, `56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79`, matched the official GitHub release API asset digest before extraction and execution. The tool was extracted to a private temporary directory and run with a scratch HOME; no host package installation or global configuration was changed. The full `shellcheck install.sh scripts/*.sh` scan covered three files with no exclusions or suppressed checks, exited 0 and emitted no diagnostics.

A temporary static-check harness initially omitted `dirname` from its isolated PATH. Adding a wrapper for `/usr/bin/dirname` in that temporary scratch allowed the embedded consistency wrapper to run; all static checks were repeated successfully. This required no repository code or environment-guard change. Raw logs, request traces, downloaded tools, installed packages and backups remain only in private scratch; the committed JSON contains gate results, timings, source/output hashes and tool provenance.

Validation elapsed through evidence collection: **2427 seconds**; the real-suite duration above is measured separately.

### Behavior verified by the final integrated run

- Fresh isolated installation pins every default component and loads all five extension modules. Repeating installation leaves managed trees and retained state byte-identical. No auth/model/permission/Advisor config is created on a fresh install.
- Enabled-resource probing respects disabled packages, resource filters and autoload semantics, and prevents module initialization side effects from contaminating the original snapshots.
- A real Pi package-manager lifecycle positive control executes its marker; the installer's ignore-scripts environment suppresses the same marker.
- Failure after real CLI replacement restores working Pi **1.0.2** and **1.4.0** stacks, including bin/tree inventories and commands loaded by the old runtime.
- Broken live settings and unavailable npm/curl/git still recover the old 1.0.2 stack offline. Its subsequent npm-to-source migration preserves object resource filters, unrelated package entries, settings and credentials.
- The previous-main **1.4.0 + BTW 0.62.0 + Advisor 0.14.2 + permission-modes source** combination upgrades successfully and preserves the four user config files.
- `/classifier-model` merges existing JSON, disables without discarding the chosen model, retains timeout and permission rules, defaults a missing timeout, rejects invalid JSON/root types, preserves the original on atomic-write failure, and invokes reload.
- Published Advisor selectors render and save the chosen Advisor with Executor following the current session. `/advisor` and `ask_advisor` return the loopback marker through real Pi registry authentication and the resolved endpoint. Missing credentials cause no HTTP request.
- Published `/btw` renders an answering view and retained composer, returns a loopback response through real Pi registry routing, omits tools, and closes with its default `Ctrl+C`. Only fullscreen terminal handoff is replaced by the controlled UI harness.
- permission-modes 2.7.0's resolved-baseUrl bug is reproduced. The retained 2.8.0 snapshot produces allow/deny results at the correct endpoint. Malformed, empty, timeout and HTTP failures fail closed; Auto is bounded to exactly three attempts. Ask/Plan/Auto block dangerous Bash/PowerShell/embedded commands and outside-cwd writes; safe reads remain available.
- Actual Pi RPC startup registers `/classifier-model`, `/mode`, `/btw`, `/advisor`, `/advisor-models`, `/advisor-settings` and `/advisor-stats` together.

The offline suite additionally covers journal/input validation, unsupported paths and symlinks, interrupted workers, partial restoration, package-remove failure, and SIGINT/SIGTERM/SIGKILL recovery. All **78** passed in the final November 15 rerun. The earlier ShellCheck SKIP is retained only in the historical November 14 JSON and is superseded by the successful scan above.

## Fixture corrections during the initial November 14 audit

The first old-runtime fixture failed **before upgrade**: Pi 1.0.2's published internal `^1.0.2` dependencies resolved to current 1.5.2 packages. The mixed runtime broke the old permission extension's TypeBox alias. Installing the old CLI with npm `--before=2026-10-05T00:00:00Z` reconstructs the historical runtime without patching published files. Its loader, failure rollback, offline recovery and eventual migration passed.

A later migration run reached the test wrapper's four-minute limit during final validation. Its evidence was retained. Installer-level tests now allow ten minutes for per-file fsync/snapshot work; production subprocess limits are unchanged. Migration was repeated from the verified old snapshot in a new isolated home and passed. The current-main migration and rollback also passed.

The initial optional harness encountered denied ancestor-directory discovery. Using an isolated project root and untrusted in-memory settings fixed the fixture without broadening filesystem access. All four packages then installed and loaded separately.

## tmux and optional packages

The exact v1.5.2 tmux documentation retains the existing rules: 3.1 gets no extended-key settings; 3.2/3.3a/3.4 get `extended-keys on`; 3.5/3.5a/3.6 also get `extended-keys-format csi-u`. All seven transformation/idempotence cases passed. No running tmux server was contacted. Upstream also documents a tmux 3.6 startup-text issue and recommends upgrading tmux.

Optional latest versions checked and installed individually: `pi-subagents@0.88.1` (19 commands), `@narumitw/pi-subagents@3.4.5` (`/subagents`), `pi-mcp-adapter@7.0.1` (three commands), and `@narumitw/pi-lsp@0.49.12` (`/lsp`). These are **TESTED (load)** only. Both subagents packages register `/subagents`; choose one. The adapter registers `/mcp`, overlapping Pi's built-in; prefer built-in MCP. None is added to defaults. `pi-openai-service-tier@0.1.4` still has old peer package names and remains unverified; `pi-retry` still returns npm HTTP 404.

permission-modes issues #3 and #4 remain open; PR #1 remains closed and unmerged. Their known limitations remain documented in [`../TESTED_VERSIONS.md`](../TESTED_VERSIONS.md).

## Limits and reproduction

No real credentials, external inference, live MCP service, child agent or language server was used. UI components were exercised with controlled input, not a physical terminal; fullscreen handoff, mouse/split-pane operation and real tmux key forwarding remain unverified. Advisor virtual routing and header-only auth were not separately exercised. October upstream unit-test/typecheck/physical-TUI results remain historical.

```bash
node scripts/build-installer.mjs --check
for file in install.sh scripts/*.sh; do bash -n "$file"; done
shellcheck install.sh scripts/*.sh
scripts/check-embedded-extension.sh
node --test scripts/test-offline.mjs
node scripts/test-real.mjs /absolute/scratch/evidence-directory
```

All real operations use guarded scratch HOME/prefix/cache/npmrc/Pi/PATH environments. The test driver creates those environments itself. This final run also launched the driver inside a fresh outer scratch, so its children and temporary probes stayed beneath that scratch. Do not run acceptance against a production Pi home.

Primary sources checked:

- [Pi v1.5.2 release](https://github.com/earendil-works/pi/releases/tag/v1.5.2), [coding-agent package.json](https://github.com/earendil-works/pi/blob/v1.5.2/packages/coding-agent/package.json), [changelog](https://github.com/earendil-works/pi/blob/v1.5.2/packages/coding-agent/CHANGELOG.md), [tmux documentation](https://github.com/earendil-works/pi/blob/v1.5.2/packages/coding-agent/docs/tmux.md), [minimal-mode source](https://github.com/earendil-works/pi/blob/v1.5.2/packages/coding-agent/examples/extensions/minimal-mode.ts).
- npm registry metadata for [Pi](https://registry.npmjs.org/@earendil-works/pi-coding-agent), [BTW](https://registry.npmjs.org/@narumitw/pi-btw), [Advisor](https://registry.npmjs.org/pi-advisor-flow), [permission-modes](https://registry.npmjs.org/@georgedong32/permission-modes), and the optional packages listed above; published tarball changelogs and entrypoints were inspected.
- [Retained permission-modes source](https://github.com/GeorgeDong32/pi-permission-modes/tree/cf77816f28e102409dddbf8e537e4cf57aa092f0), issues [#3](https://github.com/GeorgeDong32/pi-permission-modes/issues/3), [#4](https://github.com/GeorgeDong32/pi-permission-modes/issues/4), and [PR #1](https://github.com/GeorgeDong32/pi-permission-modes/pull/1).
