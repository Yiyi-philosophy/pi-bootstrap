# Monthly pi-bootstrap maintenance

You are maintaining this repository. First read:

- `README.md`
- `install.sh`
- `TESTED_VERSIONS.md`
- `extensions/classifier-model.ts`

Do not update anything merely because a newer release exists.

## 1. Find the current stable Pi

Check the npm stable/latest dist-tag, the `earendil-works/pi` GitHub release or tag, and the coding-agent `package.json`. Ignore dev, rc, beta, and other prereleases. Treat the newest stable Pi as a candidate only.

## 2. Audit default extensions

Check current stable versions of:

- `@georgedong32/permission-modes`
- `@narumitw/pi-btw`
- `pi-advisor-flow`

For each, inspect npm metadata, the GitHub package when available, `peerDependencies`, changelog, compatibility notes, and known broken or excluded Pi versions. Confirm that the version is formally published as stable; do not pin a GitHub-only commit.

## 3. Audit optional extensions

Check `pi-openai-service-tier`, `pi-subagents`, `pi-mcp-adapter`, and `@narumitw/pi-lsp`. Do not install them by default. Record exact tested-compatible versions in `TESTED_VERSIONS.md` and use those versions in README examples only after they pass.

## 4. Check Pi-bound files and APIs

Using exactly the candidate Pi release tag, verify:

- `packages/coding-agent/examples/extensions/minimal-mode.ts`
- `packages/coding-agent/docs/tmux.md`
- the extension APIs used by `classifier-model.ts`: command registration, `ctx.hasUI`, model registry refresh and reads, `ctx.ui.select`, and `ctx.reload`

Never use `main` as the source for an installed Pi-bound file when a release tag exists. Update `classifier-model.ts` only if the candidate release requires a minimal compatibility fix.

## 5. Validate tmux behavior

Read the candidate Pi release documentation. Currently expected:

- tmux >= 3.5: `extended-keys on` plus `extended-keys-format csi-u`
- tmux 3.2-3.4: `extended-keys on` only
- tmux < 3.2: warn and do not add settings

If upstream changes this guidance, update `install.sh`, README, and tests. Never run `tmux kill-server`.

## 6. Build the compatibility matrix

Construct and review:

```text
Pi candidate
+ permission-modes candidate
+ pi-btw candidate
+ advisor-flow candidate
+ classifier-model
+ minimal-mode from the exact Pi tag
```

Install the candidate in an isolated environment, load each default extension, and exercise `/classifier-model`, `/advisor-models`, and `/btw` where the environment permits. If any core component is incompatible, stop the upgrade and keep the previous confirmed-good stack. Document why.

## 7. Test before changing pins

At minimum run:

- `bash -n install.sh`
- `shellcheck install.sh` when available
- classifier merge, disable, timeout preservation, permissions preservation, invalid JSON, and atomic-write tests
- `scripts/check-embedded-extension.sh`
- isolated repeated installer tests
- exact minimal-mode URL and exact npm version checks
- Pi start and default extension load tests
- registration checks for `/classifier-model`, `/advisor-models`, and `/btw`
- tmux branch tests for `3.1`, `3.2`, `3.3a`, `3.4`, `3.5`, `3.5a`, and `3.6`

Use stubs or isolated temporary homes for tmux tests. Do not kill real tmux sessions.

## 8. Update only after PASS

If the whole candidate stack passes, update the pinned constants and exact minimal-mode tag in `install.sh`, README, and `TESTED_VERSIONS.md`. Keep the installer self-contained. If no meaningful change is required, make no source changes.

## 9. Security

Never edit `auth.json` or `models.json`, expose credentials, add private endpoints, enable bypass, auto-select models, auto-install optional extensions, modify shell profiles, install sudo packages, or execute `tmux kill-server`.

## 10. Final report

Report the previous and candidate matrices, accepted or rejected upgrades, compatibility evidence, tmux findings, tests and results, files modified, and remaining risks. Do not tag, publish, push, or merge a release unless explicitly requested.
