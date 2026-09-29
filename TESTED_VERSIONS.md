# Tested versions

Last verified: 2026-09-29

## Default stack

| Component | Version | Status |
|---|---:|---|
| Pi Coding Agent | 0.87.1 | PASS: package tarball and release contents inspected locally |
| permission-modes | 2.7.0 | PINNED CANDIDATE: npm registry unavailable during this verification |
| pi-btw | 0.61.1 | PINNED CANDIDATE: npm registry unavailable during this verification |
| pi-advisor-flow | 0.9.0 | PINNED CANDIDATE: npm registry unavailable during this verification |
| classifier-model | repository version | PASS: checked against Pi 0.87.1 extension declarations |
| minimal-mode.ts | Pi v0.87.1 | PASS: exact release package inspected locally |

## Compatibility notes

- Pi 0.87.1 exposes `registerCommand`, `ctx.hasUI`, `ctx.modelRegistry.refresh()`, `getAvailable()`, `ctx.ui.select()`, and `ctx.reload()` used by `classifier-model.ts`.
- Pi 0.87.1 documents the exact `minimal-mode.ts` path and the tmux 3.5 / 3.2-3.4 split.
- The default extension package versions remain candidates until npm metadata, peer dependencies, changelogs, and a live load test can be checked with network access.
- Live npm and GitHub lookups were unavailable in this environment because DNS could not resolve the public registries; the pinned plugin candidates must be rechecked during the next connected maintenance run.
- `pi-retry` remains excluded because modern Pi provides built-in retry and timeout behavior.

## Optional extensions

No optional extension version is marked tested in this snapshot. The monthly maintenance audit must verify and record exact versions before recommending them.
