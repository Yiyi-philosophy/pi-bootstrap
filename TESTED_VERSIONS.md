# Tested versions

Last verified: 2026-10-23

Status key: **PASS** = installed and exercised; **TESTED (load)** = installs and loads with registration verified, core behavior not exercised; **SKIP** = not run in that environment; **UNVERIFIED** = not exercised at all. Every PASS below is backed by a committed script in [`scripts/tests/`](scripts/tests); run `scripts/tests/run-all.sh` to reproduce, and read [`docs/r4-closure-report.md`](docs/r4-closure-report.md) for the most recent results (`docs/r3-closure-report.md` covers the round before it) (R2 results remain in [`docs/r2-closure-report.md`](docs/r2-closure-report.md)).

The real-runtime rows require the **exact** versions below. A newer Pi or extension is reported as SKIP, not PASS: these tests assert the combination this repository ships. `scripts/tests/test-version-matrix.mjs` keeps `install.sh` and the test harness on the same pins.

## Default stack

| Component | Version | Source | Status |
|---|---:|---|---|
| Pi Coding Agent | 1.4.0 | npm | PASS: isolated install, RPC startup and command invocation (`test-rpc-smoke.mjs`), extension loading under Node 24.14.0; staged install + activation and rollback to 1.0.2 verified with the real CLI (`test-real-upgrade.mjs`); TUI startup verified interactively in the 2026-10 audit, not by a committed test |
| permission-modes | 2.8.0 | pinned upstream commit `cf77816f28e102409dddbf8e537e4cf57aa092f0` (git source, **not an npm release**) | PASS: installed via `pi install git:…@<sha>`, pre- and post-install verification against commit + tree + 69-file SHA256 manifest; gate and classifier tests in `scripts/tests/`; real upgrade from the 2.7.0 npm package and back (`test-real-upgrade.mjs`) |
| pi-btw | 0.62.0 | npm | PASS: installed and registered `/btw` (`test-default-stack.mjs`); TUI side question completed against a loopback fixture during the 2026-10 audit (interactive, no committed test) |
| pi-advisor-flow | 0.14.2 | npm | PASS: `/advisor`, `/advisor-models`, `/advisor-settings`, `/advisor-stats` registered (`test-default-stack.mjs`); selector save, no-credential error path, and a full `ask_advisor` consultation against a loopback fixture were verified interactively in the 2026-10 audit, not by a committed test |
| classifier-model | repository version (changed in R4: cross-directory writes removed) | local | PASS: registered under Pi 1.4.0; JSON-safety battery committed as `test-classifier-config.mjs`; config-path battery committed as `test-config-path.sh` (default HOME including trailing-slash/relative spellings, `PI_AGENT_DIR` ignored, every custom `PI_CODING_AGENT_DIR` refused with the real `$HOME` file byte-identical, reload persistence) |
| minimal-mode.ts | Pi v1.4.0 tag | raw tag URL | PASS: exact tag URL fetched; SHA256 `040cbc76…a8770` pinned and verified |

## Upgrade safety (R3, extended in R4)

- **Failure recovery is exercised, not asserted.** `scripts/tests/test-rollback.sh` fails a run at 19 distinct points (after backup, after `pi remove`, after new packages, after verification, after extensions, while writing keybindings, after tmux, at the last step, inside a nested function's command substitution, in a failing pipeline, in a subshell, and on `SIGINT`/`SIGTERM`/`SIGKILL`) and checks that settings, both extensions, keybindings and `.tmux.conf` are byte-identical, that the old packages and the old `pi` binary are back, and that the failed run's files are gone. The `SIGKILL` case proves the next invocation restores the environment before doing anything else.
- **R4 fault injection.** The same file also SIGKILLs the installer at each filesystem boundary of the staged CLI step (`before-package-move`, `after-package-move`, `recorded-cli`, `after-package-activate`, `after-bin-link`), fails the journal write, the atomic `rename`, and models a full disk at the backup, CLI and commit phases, and runs recovery with npm, curl and GitHub all unreachable and `settings.json` damaged by the crash. Each case asserts the previous `pi` package and bin entry are back.
- **Real-CLI acceptance.** `scripts/tests/test-real-upgrade.mjs` (`PI_BOOTSTRAP_REAL_UPGRADE=1`, needs npm + GitHub) installs Pi 1.0.2 with permission-modes 2.7.0, pi-btw 0.61.1 and advisor-flow 0.11.0 from the registry, fails the real installer after it installed the 1.4.0 matrix, and then proves with the real Pi 1.0.2 extension loader that all three old packages load again; a clean re-run then verifies the pinned matrix.
- **Boundaries.** Rollback restores what existed when the run started. It cannot undo a `SIGKILL` in the middle of the restore itself (the journal makes the next run retry), and it does not touch `permission-modes.json`, `advisor.json`, `auth.json`, or `models.json`.

## Compatibility notes

- Pi 1.4.0 requires Node.js >=22.19.0 (engines unchanged since 1.0.2); audit host used Node 24.14.0 / npm 11.9.0. Internal Pi dependencies are exactly pinned to 1.4.0.
- **Classifier baseUrl regression (October 2026 blocker) is fixed.** Published permission-modes 2.7.0 discarded the authentication-resolved `baseUrl` when calling the classifier. The 2.8.0 source snapshot routes completions through the host `ctx.modelRegistry.complete()`, so auth resolution (including the per-credential `baseUrl` merge in `ModelRuntime.prepareRequest`) happens inside Pi. Verified with a real Pi 1.4.0 `ModelRegistry` and a local HTTP mock: 2.7.0 misroutes (regression reproduced), 2.8.0 posts to the resolved URL, forwards credentials only to the resolved host, and returns valid allow/deny verdicts.
- permission-modes 2.8.0 is source-only: npm `latest` is still 2.7.0 and the npm versions map has no 2.8.0 (HTTP 404). The pinned commit `cf77816` is the upstream `release: 2.8.0` snapshot on `master`; there is no `v2.8.0` git tag. The installer pins the immutable commit SHA and verifies all 69 tracked files against the embedded SHA256 manifest (`install.sh`). It must never be described as an official npm release.
- Upstream's own test suite on the snapshot is **not fully green**: 439–440 of 441 pass across repeated runs (best case 440/441, never 441/441 on the audit host). One deterministic environment artifact (`findProjectRoot` finds a stale `/tmp/.git` on the audit host) and one upstream test-isolation flaw (two auto-mode classifier tests intermittently observe each other's module-level verdict-cache state; each passes deterministically in isolation). The pinned runtime behavior was re-verified independently: fail-closed with exactly `MAX_CLASSIFIER_FAILURES = 3` bounded attempts under the real Pi 1.4.0 loader.
- Production sources of the snapshot typecheck cleanly against Pi 1.4.0 types (`tsc --noEmit`; upstream devDependencies pin Pi `^0.85.1`, and only their test files' fake-pi surface drifts).
- `pi-ai@1.4.0` still ships the deprecated `./compat` export, so 2.7.0 still *loads* on Pi 1.4.0 — but its classifier still has the baseUrl bug. Do not "upgrade" Pi alone while keeping permission-modes 2.7.0.
- pi-btw 0.62.0 (published 2026-10-20) aligns the side-question workspace with native Pi input/session lifecycle; since 0.60.3 side-thread requests go through Pi's authenticated `modelRegistry.streamSimple()` (same fix family as the classifier B2 change). Its runtime dependency `@narumitw/pi-tui-kit` uses a floating range (`^0.64.0` resolved to 0.66.0 in this audit's installs), so future clean installs may resolve a newer transitive copy.
- pi-advisor-flow 0.14.2 (published 2026-10-21; peers `^1.0.0`): 0.11.2 fixed a startup crash when a host omits `systemPromptOptions`; 0.13.0 added optional Jev/System One providers (no credentials required for standard use); 0.14.0 changed Executor behavior — the Executor now follows the current session model by default and `/advisor` no longer switches models; 0.14.1 preserves the Executor prompt cache across budget changes; 0.14.2 fixes long-running Pi consultation cleanup. `advisor.json` is created only by explicit user selection.
- PUBLISHED means the specified release is confirmed published. COMPATIBLE/METADATA_COMPATIBLE is reserved for a successful peer-dependency/upstream-metadata check; PASS is reserved for an actual install and runtime exercise; TESTED (load) means the package installs and loads with registration verified but its core functionality was not exercised; UNVERIFIED means not exercised at all.
- The full default combination (permission-modes + pi-btw + advisor-flow + classifier-model + minimal-mode) loads together on one real Pi 1.4.0 loader with no errors and all default commands registered (`test-default-stack.mjs`). An isolated RPC startup registers `/classifier-model`, `/mode`, `/btw`, `/advisor`, `/advisor-models`, `/advisor-settings`, and `/advisor-stats`. `/btw` and `/advisor` consultations completed against loopback fixtures in the 2026-10 audit through a real pseudoterminal; that pty harness was not committed because it depended on a hand-built agent tree, so those two remain interactive-audit evidence rather than a repeatable test.
- permission-modes registers a `shift+tab` shortcut that conflicts with a Pi 1.4.0 built-in; Pi skips it with a warning. The bootstrap's keybinding merge (`app.thinking.cycle` → `ctrl+shift+tab`) is unaffected.

## Known open upstream issues (evaluated 2026-10-22)

- **#3 (open, reproduced):** model profiles auto-generate (`~/.pi/agent/model-profiles.json` with the settings default model for ask/plan/auto) and every mode switch calls `pi.setModel(profileModel)`, overriding manual in-session model changes. Reproduced live under the real Pi 1.4.0 loader (profile auto-creation + `setMode → applyProfileModelForMode → pi.setModel` stack). Not a safety issue; workaround: clear the per-mode mappings in `model-profiles.json` (empty mapping keeps the current model). Same behavior in 2.7.0.
- **#4 (open, not a regression):** mode switches (and plan-step progress) change the injected system-prompt block, invalidating provider-side prompt KV caches. Identical mechanism in 2.7.0; unchanged in 2.8.0. Mitigation: keep one mode per session where cache cost matters.
- **PR #1 (closed, unmerged):** OpenAI Codex rejects `temperature`. The 2.8.0 classifier still sends `temperature: 0` for `openai-codex-responses` models; using a Codex model as the classifier will fail (the gate fails closed). Do not select Codex models in `/classifier-model`.

## Optional extensions

No optional extension is certified in this snapshot. Load/registration was smoke-tested on Pi 1.4.0 in an isolated environment on 2026-10-22 by an ad-hoc script that was **not** reproducible enough to commit; treat every row below as TESTED (load) at most, never PASS, and re-check before relying on one. In particular, `PI_OFFLINE=1` silently prevents `-e npm:` installation, so an offline rerun will report built-ins only:

| Package | Latest stable | Load on Pi 1.4.0 | Notes |
|---|---:|---|---|
| `pi-openai-service-tier` | 0.1.4 | loads | Peers still target pre-1.0 `@mariozechner` package names; runtime effect on Pi 1.4.0 unverified — not a certification candidate |
| `pi-subagents` | 0.80.0 | TESTED (load): registers 29 commands | Peers require `@earendil-works/pi-ai >=1.2.0`; no child-agent execution tested |
| `@narumitw/pi-subagents` | 3.3.0 | TESTED (load) | Distinct package from `pi-subagents`; no execution tested |
| `pi-mcp-adapter` | 5.4.0 | TESTED (load) | Peer range now includes `^1.0.0`; loads cleanly (a transient "Extension issues: builtin:mcp" notice appeared once during first install, not reproducible); no live MCP connection tested — prefer Pi's built-in MCP support |
| `@narumitw/pi-lsp` | 0.49.10 | TESTED (load) | No language-server execution tested |
| `pi-retry` | — | — | Not present on npm (registry HTTP 404); remains excluded — modern Pi has built-in retry/timeout |

Install any optional package explicitly only after your own review:

```bash
pi install npm:pi-subagents@0.80.0
```
