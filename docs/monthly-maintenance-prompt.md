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

For each, inspect npm metadata, the GitHub package when available, `peerDependencies`, changelog, compatibility notes, and known broken or excluded Pi versions. Confirm that the version is formally published as stable; do not pin a GitHub-only commit **unless** there is a documented reason (the current permission-modes 2.8.0 pin is such an exception: the baseUrl fix is source-only). A non-npm pin must carry an immutable commit, a verification manifest, a source-built label, and a note in `TESTED_VERSIONS.md` explaining when it can move to npm.

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

`scripts/test-tmux.sh` encodes this and is the source of truth; if upstream guidance changes, update the installer and that test together.

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

Run the committed suite — it covers everything below:

```bash
scripts/tests/run-all.sh
```

What it runs (each in its own scratch `HOME`, with stubs and loopback mocks; a test that cannot run reports SKIP, never PASS):

- `bash -n install.sh` and every `scripts/**/*.sh`; `shellcheck install.sh` when available
- `scripts/check-embedded-extension.sh` (embedded `classifier-model.ts` byte-identical to the source)
- `scripts/tests/test-install-settings.sh` — stale-entry identity matching, unrelated packages, malformed settings, `pi remove` failure
- `scripts/tests/test-install-run.sh` — fresh, repeat, upgrade from 1.0.2, pre-install source verification, tamper detection, rollback
- `scripts/tests/test-install-lifecycle.mjs` — real Pi git install with and without `npm_config_ignore_scripts`
- `scripts/tests/test-classifier-config.mjs` — merge, disable, timeout and permission preservation, invalid JSON, atomic writes, reload failure
- `scripts/tests/test-permission-gate.mjs` — fail-closed, bounded retries, allow/deny, embedded commands, powershell, outside-cwd
- `scripts/tests/test-classifier-baseurl.mjs` — 2.7.0 misroutes / 2.8.0 honors the resolved `baseUrl`
- `scripts/tests/test-rpc-smoke.mjs` — headless Pi start, command registration and invocation
- `scripts/tests/test-default-stack.mjs` — all five default extensions on one loader
- `scripts/test-tmux.sh` — `3.1`, `3.2`, `3.3a`, `3.4`, `3.5`, `3.5a`, `3.6`, downgrade, no-trailing-newline, reload failure

The real-runtime tests need Pi 1.4.0 and the pinned permission-modes source: set `PI_BOOTSTRAP_PI_PACKAGE` and `PI_BOOTSTRAP_PM_280`. Add `--fetch` to let them download fixtures. Never contact a real tmux server; the tmux test uses a stub.

If you change the permission-modes pin, regenerate the manifest with the helper instead of editing it by hand — it verifies the checkout is clean and rewrites commit, tree, count, and file list together:

```bash
scripts/update-permission-modes-pin.sh <checkout>          # check only
scripts/update-permission-modes-pin.sh <checkout> --write  # update install.sh
```

## 8. Update only after PASS

If the whole candidate stack passes, update the pinned constants and exact minimal-mode tag in `install.sh`, README, and `TESTED_VERSIONS.md`. Keep the installer self-contained. If no meaningful change is required, make no source changes.

Then re-run `scripts/tests/run-all.sh` in a fresh isolated environment: a PASS recorded before the last edit is not acceptance. Record the summary line (passed/skipped/failed) and the skipped tests in the final report, and say which of them are UNVERIFIED rather than quietly green.

## 9. Security

Never edit `auth.json` or `models.json`, expose credentials, add private endpoints, enable bypass, auto-select models, auto-install optional extensions, modify shell profiles, install sudo packages, or execute `tmux kill-server`.

## 10. Final report

Report the previous and candidate matrices, accepted or rejected upgrades, compatibility evidence, tmux findings, tests and results, files modified, and remaining risks. Do not tag, publish, push, or merge a release unless explicitly requested.
