# Tested versions

Last verified: 2026-10-04

## Default stack

| Component | Version | Status |
|---|---:|---|
| Pi Coding Agent | 1.0.2 | PASS: isolated install, RPC startup, and release contents inspected locally |
| permission-modes | 2.7.0 | PASS: installed and registered commands under Pi 1.0.2 |
| pi-btw | 0.61.1 | PASS: installed and registered `/btw` under Pi 1.0.2 |
| pi-advisor-flow | 0.11.0 | PASS: installed and registered advisor commands under Pi 1.0.2 |
| classifier-model | repository version | PASS: registered under Pi 1.0.2; APIs present in release declarations |
| minimal-mode.ts | Pi v1.0.2 | PASS: exact release URL fetched successfully |

## Compatibility notes

- Pi 1.0.2 requires Node.js >=22.19.0 and exposes `registerCommand`, `ctx.hasUI`, `ctx.modelRegistry.refresh()`, `getAvailable()`, `ctx.ui.select()`, and `ctx.reload()` used by `classifier-model.ts`.
- Pi 1.0.2 documents the exact `minimal-mode.ts` path and the tmux 3.5 / 3.2-3.4 split.
- PUBLISHED means the specified release is confirmed published. COMPATIBLE is reserved for a successful peer-dependency/upstream-metadata check; PASS is reserved for an actual install and runtime smoke test.
- npm metadata confirms `permission-modes@2.7.0` and `pi-btw@0.61.1` accept Pi packages through wildcard peer dependencies; `pi-advisor-flow@0.11.0` declares `^1.0.0` peers and is the Pi 1.x-compatible release.
- An isolated Pi 1.0.2 RPC startup registered `/classifier-model`, `/btw`, `/advisor`, `/advisor-models`, and `/advisor-settings` without extension load errors.
- `pi-mcp-adapter@5.0.0` is not certified for Pi 1.x because its peer range only lists pre-1.0 `@earendil-works/pi-ai` versions. `pi-openai-service-tier@0.1.4` still targets the old `@mariozechner` package names. Pi's built-in MCP support remains available.
- `pi-retry` remains excluded because modern Pi provides built-in retry and timeout behavior.

## Optional extensions

No optional extension version is marked tested in this snapshot. `pi-subagents@0.75.0` and `@narumitw/pi-lsp@0.49.9` are published, but their Pi 1.x runtime behavior was not exercised; `pi-mcp-adapter@5.0.0` and `pi-openai-service-tier@0.1.4` are explicitly not compatible candidates for this stack.
