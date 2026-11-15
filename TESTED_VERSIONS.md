# Tested versions

Current verification: **2026-11-14**, America/Los_Angeles, Node **24.22.1** / npm **11.19.1**. See [`docs/upgrade-audit-2026-11.md`](docs/upgrade-audit-2026-11.md) for sources, acceptance results, and limits.

October evidence remains historical: [`docs/upgrade-audit-2026-10.md`](docs/upgrade-audit-2026-10.md), [`docs/upgrade-risk-review.md`](docs/upgrade-risk-review.md), and [`docs/independent-hardening-report.md`](docs/independent-hardening-report.md). Their upstream test counts, typechecks and physical TUI results were not rerun or relabeled as November results.

## Default stack

| Component | Previous main | Accepted version | November evidence |
|---|---:|---:|---|
| Pi Coding Agent | 1.4.0 | **1.5.2** (npm) | PASS: fresh isolated install, real CLI/loader, RPC command registration, repeat-run identity, previous-main upgrade and rollback |
| permission-modes | 2.8.0 source | **2.8.0 source**, unchanged commit `cf77816f28e102409dddbf8e537e4cf57aa092f0` | PASS: exact commit/tree and 69-file SHA256 manifest; real classifier allow/deny, failure cases and Ask/Plan/Auto safety gates |
| `@narumitw/pi-btw` | 0.62.0 | **0.63.8** (npm) | PASS: `/btw` registration, real answer/composer rendering and tools-free side request through Pi registry and loopback HTTP |
| `pi-advisor-flow` | 0.14.2 | **0.15.1** (npm) | PASS: commands registered; real `/advisor-models` selectors save the chosen Advisor; `/advisor` and `ask_advisor` complete; missing credentials fail without HTTP |
| classifier-model | repository version | unchanged | PASS: merge, disable, model/timeout/permissions preservation, invalid JSON/root rejection, atomic-write failure, default timeout and reload |
| minimal-mode.ts | Pi v1.4.0 tag | **Pi v1.5.2 tag** | PASS: exact release-tag bytes; unchanged SHA256 `040cbc7619b2e903888c8626e2fa55ca5e3f820535dfd1aadcb2060e156a8770` |

All five default extension modules load together. No user credentials, provider endpoints, or model choices are added by installation. The previous-main migration fixture verifies byte preservation of `auth.json`, `models.json`, `permission-modes.json`, and `advisor.json`, plus unrelated settings.

## Compatibility notes

- Pi 1.5.2 requires Node >=22.19.0. Its internal Pi dependencies are exact 1.5.2 versions. The classifier extension APIs remain available; no extension source change was required.
- permission-modes npm `latest` remains **2.7.0**, and 2.8.0 is not an npm release or tagged release. Upstream `master` still points to the already accepted source snapshot. This upgrade retains that existing exception; it introduces no new git pin. The installer verifies immutable tree `480649739171c272f355850cf6b6228ffa823c0c` and the exact 69-file manifest before execution.
- The 2.7.0 classifier's authentication-resolved `baseUrl` regression was reproduced under Pi 1.5.2. The 2.8.0 source snapshot uses Pi's registry completion path and posts to the resolved endpoint with the fixture credentials. Malformed/empty responses, timeout and HTTP errors fail closed, without hidden SDK retries; the real Auto gate makes exactly three attempts on those errors. Dangerous Bash, PowerShell, embedded commands and outside-cwd writes remain blocked in Ask/Plan/Auto; safe Ask reads remain available.
- pi-btw 0.63.8 depends on `@narumitw/pi-tui-kit ^0.70.0` (0.70.0 resolved in this audit). Changelog changes since 0.62.0 include explicit main-context import, deep-tree fixes, lazy UI initialization and terminal handoff improvements. This audit exercises the published command and registry request path; the controlled UI bypasses only fullscreen terminal handoff. Physical terminal, split-pane and mouse behavior remain unverified.
- Advisor 0.15.1 peers remain Pi `^1.0.0` and TypeBox `^1.1.38`; development dependencies target Pi 1.5.2. Upstream adds virtual Advisor models, session-id forwarding and header-only authentication, and fixes repeated update notices. The ordinary API-key/resolved-endpoint path is exercised here; virtual routing and header-only auth are upstream claims, not separately certified by this run. Executor follows the current session unless the user explicitly selects an override.
- Pi 1.5 renames Azure provider `azure-openai-responses` to `azure`. Azure users must migrate provider keys/references in auth, models and settings according to upstream documentation. Pi 1.5.1 changes `cacheWarming`'s default to `idle`; use `"cacheWarming": "streaming"` for previous behavior. Neither change is written into user config by this bootstrap. Older proxies that require tools after tool history may need `compat.requiresToolsWithToolHistory: true` in their model configuration.
- Pi 1.0.2's historical fixture now uses npm `--before=2026-10-05T00:00:00Z`. Its published `^1.0.2` internal ranges otherwise resolve today's 1.5.2 internals and break the old permission extension before an upgrade even begins. The release cutoff reconstructs the old runtime without modifying published files.
- Top-level pins do not freeze all transitive dependencies. Future installs may resolve newer versions within upstream dependency ranges and must be revalidated.

## Known upstream issues

Issue states were checked on **2026-11-14**; the source snapshot is unchanged. The behavior findings below originate from October's audit unless a November result is explicitly stated.

- **#3 remains open:** permission mode profiles can override manual in-session model changes. Clear the per-mode mappings in `~/.pi/agent/model-profiles.json` to keep the current model. A November RPC startup also observed default profile creation; full profile switching was not separately rerun.
- **#4 remains open:** mode changes modify the injected system prompt and invalidate provider prompt caches. Keep one mode per session where cache cost matters.
- **PR #1 remains closed, unmerged:** the source classifier still sends `temperature: 0` for Codex models, which reject it. Do not select Codex as permission classifier; no real Codex-provider request was made in this audit.

## Optional extensions

No optional extension is certified or installed by default. The four updated packages below were installed **individually** and loaded with Pi 1.5.2 on 2026-11-14. Their functional integrations were not exercised.

| Package | Latest stable checked | Pi 1.5.2 result | Limits |
|---|---:|---|---|
| `pi-openai-service-tier` | 0.1.4 | UNVERIFIED; excluded from certification | Peers still use old `@mariozechner` names; runtime service-tier effect not tested |
| `pi-subagents` | 0.88.1 | TESTED (load): 19 commands | No child execution; shares `/subagents` with the other package |
| `@narumitw/pi-subagents` | 3.4.5 | TESTED (load): `/subagents` | Separate package; choose one subagents implementation |
| `pi-mcp-adapter` | 7.0.1 | TESTED (load): `/mcp-adapter`, `/mcp`, `/mcp-auth` | `/mcp` overlaps Pi's built-in; no live MCP connection tested; prefer built-in MCP |
| `@narumitw/pi-lsp` | 0.49.12 | TESTED (load): `/lsp` | No language-server execution tested |
| `pi-retry` | — | Registry HTTP 404 | Remains excluded; Pi has built-in retry/timeout handling |

PUBLISHED means confirmed in npm. METADATA_COMPATIBLE means only the peer/source check passed. PASS means the stated runtime behavior was exercised; TESTED (load) means installation/loading/registration only; UNVERIFIED means no runtime exercise.

Install a chosen optional package only after reviewing those limits, for example:

```bash
pi install npm:pi-subagents@0.88.1
```
