# R4 closure report — independent review findings H1–H4

Baseline: `ae0421fe7805a889b76d1a1bc04f54a786db1a0e` on `r3-closure`. **No version
pin changed**: Pi 1.4.0 / permission-modes 2.8.0 @ `cf77816` / pi-btw 0.62.0 /
pi-advisor-flow 0.14.2 / minimal-mode v1.4.0.

Every finding below is backed by a before/after pair: the same scenario run
against the baseline installer (`git show ae0421f:install.sh`) and against this
branch. The tests added here are committed; the ad-hoc probes used to produce
the "before" column are not (they existed only to demonstrate the defect).

## Status summary

| Finding | Status | Evidence |
|---|---|---|
| H1 — classifier wrote into a directory other than Pi's | **FIXED** (fail closed; no mirror) | `test-config-path.sh` before/after |
| **P0 — the gate itself read `$HOME`, not Pi's agent directory** | **NOT FIXABLE upstream; UNSUPPORTED and refused** | `test-config-source.mjs` (real loader, contradictory rules) |
| H2 — recovery ran after preflight / network work | **FIXED** | `test-rollback.sh` "offline recovery" cases |
| H3 — `journal_write` ignored write/rename failure | **FIXED** | `test-rollback.sh` six journal-fault cases |
| H4 — `package.existed` recorded after the move | **FIXED** | `test-rollback.sh` five SIGKILL boundary cases |
| Isolation of HOME / agent dir / npm prefix / config, incl. symlink escape | **DONE** | `run-all.sh` forced isolation; `lib.sh` `physical_path`; `test-isolation-guards.mjs` |
| Complexity: duplicated state / paths / journal handling | **REDUCED** | see "Simplification" |

## H1 — no cross-directory write, ever

**What was wrong.** `resolveConfigPaths()` returned `[Pi's dir, $HOME/.pi/agent]`
whenever the two differed, and the handler wrote the classifier block to both.
A test or throwaway Pi instance started with `PI_CODING_AGENT_DIR` set therefore
rewrote the *developer's real* `~/.pi/agent/permission-modes.json`. That is the
same accident the R3 report recorded under "Incident", and it was still
reachable in code.

**Reproduction against the baseline** (`HOME=/tmp/r4-repro/home`,
`PI_CODING_AGENT_DIR=/tmp/r4-repro/custom`, a real classifier block already in
`$HOME`):

```text
notices: ["…saved to /tmp/r4-repro/custom/permission-modes.json and mirrored to
           /tmp/r4-repro/home/.pi/agent/permission-modes.json…"]
HOME file before=cb05e2fc…465f after=7afa0c38…cec9
RESULT: real HOME config OVERWRITTEN
```

**Can the upstream read path be fixed instead?** No. The pinned source
(`config.ts` in the audited commit, checked against the manifest hash
`cfea6ae4…`) sets

```ts
let _configPath = join(homedir(), ".pi", "agent", "permission-modes.json")
```

at module load. The only setter is `setConfigPath`, exported through
`permissions-loader.ts` as `setGlobalConfigPathForTests`, and nothing in
`index.ts` consults `PI_CODING_AGENT_DIR` (grep of the pinned `index.ts`,
`permissions-loader.ts`, `config.ts`: no such read). There is no supported
redirection.

**Fix.** `requireSupportedAgentDir()` accepts a directory only when it *is*
`$HOME/.pi/agent` after `resolve()`; otherwise `resolveConfigPath()` throws a
message naming the file permission-modes actually reads. The handler resolves
the path **before** showing the picker, so the user never spends a selection on
a write that cannot reach the gate. `resolveConfigPaths()`, `safeReadConfig()`
and the mirror branch are deleted.

**After** (same scenario):

```text
notices: ["/classifier-model cannot save a selection here: Pi is using
           /tmp/r4-repro2/custom, but permission-modes 2.8.0 always reads
           /tmp/r4-repro2/home/.pi/agent/permission-modes.json and cannot be
           redirected. … nothing was written. …"]
pickerShown: false
HOME file before=1aac2a7a…d20f after=1aac2a7a…d20f
RESULT: HOME config UNCHANGED; custom dir empty
```

**Cost, stated plainly.** `/classifier-model` is now unavailable under a custom
agent directory. That is an accepted limitation, not a silent behaviour: the
command says so and points at the file to edit. `docs/upgrade-risk-review.md`
and README were updated to describe this instead of the mirror.

**Note on a symlinked agent directory.** Both layers compare *physical* paths
(`physicalPath` in the extension, `same_directory` in the installer), so
`$HOME/.pi/agent`, `$HOME/.pi/agent/`, a relative spelling and a symlink that
resolves to the default directory are all accepted, while a symlink that
resolves elsewhere is refused. Both directions are tested
(`test-config-path.sh`, `test-install-run.sh`).

## P0 — the permission gate reads `$HOME/.pi/agent`, not Pi's directory

H1 stopped *writing* into the wrong directory. It did not answer the larger
question the reviewer asked: **which file does the gate obey?** It obeys
`homedir()`.

### Reproduction (real Pi 1.4.0 loader, real pinned source)

Two isolated directories with contradictory rules:

- `$HOME/.pi/agent/permission-modes.json` → `deny: ["Bash(denytest:*)"]`
- `PI_CODING_AGENT_DIR/permission-modes.json` → `allow: ["Bash(denytest:*)"]`

```text
PASS gate source: a deny rule in $HOME/.pi/agent decides, although PI_CODING_AGENT_DIR allows it
PASS gate source: a deny rule in PI_CODING_AGENT_DIR is NOT read (the gate ignores it)
PASS gate source: control - the default layout honours the rule
```

The decision is observed on the `tool_call` handler's actual verdict
(`Denied by permission rule [global]: Bash(denytest:*)`), after
`before_agent_start` refreshes the merged rules — not by comparing paths.
Committed as `scripts/tests/test-config-source.mjs`.

Source, at the pinned commit: `config.ts:47`
`let _configPath = join(homedir(), ".pi", "agent", "permission-modes.json")`.
`profiles.ts` (model-profiles, settings) and `permission-forwarding.ts`
(subagent root) resolve from `homedir()` too.

### Can the pinned upstream be redirected without patching it? No.

- `config.ts` exports `setConfigPath()`, but `index.ts` does not re-export it;
  the only path out is `permissions-loader.ts`'s
  `setGlobalConfigPathForTests()`, which `index.ts` does not re-export either.
- Even reaching it would not help: Pi 1.4.0 creates a **new jiti instance per
  extension with `moduleCache: false`** (`dist/core/extensions/loader.js`), so
  two extensions importing the same `config.ts` get separate module instances.
  Verified with two probe extensions: A's `setConfigPath()` changed A's path and
  left B's at `$HOME/.pi/agent`.
- Patching the checkout would change the audited bytes, the 69-file SHA256
  manifest, the tree pin and the maintenance procedure. Rejected: it is not a
  minimal fix, and it would make the verified source "the audited source plus a
  local patch".

So the honest options were "silently run with the gate reading a different
configuration" or "refuse". The installer refuses.

### The refusal

`require_supported_agent_dir` (called first in `preflight`, before any
directory is created, before the Git fetch, before the transaction):

```text
pi-bootstrap: error: <dir> is UNSUPPORTED: Pi would run with this agent
directory, but permission-modes 2.8.0 always reads $HOME/.pi/agent
(permission-modes.json, model-profiles.json, settings.json) and cannot be
redirected. … nothing was changed. Run the installer with the default agent
directory (unset PI_AGENT_DIR and PI_CODING_AGENT_DIR).
```

The comparison resolves symlinks on both sides (`same_directory`), so
`$HOME/.pi/agent`, `$HOME/.pi/agent/`, a relative spelling and a symlink to it
are all accepted, while a symlink pointing elsewhere is not.

`/classifier-model` refuses the same layout in-session (H1), so the two layers
agree.

### Evidence

| Test | Baseline | This branch |
|---|---|---|
| `test-config-source.mjs` | n/a (new) | PASS, 3 cases |
| `test-install-run.sh` case 11 (custom dir) | FAIL — "Fetching permission-modes source…" (it installed) | PASS — refused before any mutation |
| `test-install-run.sh` case 11b (symlink to default) | n/a | PASS — accepted, run proceeds past preflight |

## H2 — recovery is local-first

**What was wrong.** `main()` ran `preflight` (which calls `check_settings plan`
and `resolve_global_paths` → `npm root -g`), then `prepare_permission_modes_snapshot`
(a Git fetch), and only then `recover_interrupted_run`. Both a corrupt
`settings.json` and an unreachable network could therefore stop a crashed
upgrade from being rolled back — on exactly the run whose purpose was to repair
it.

**Reproduction against the baseline** (crash after backup, then damage
`settings.json`, then recover-only with npm/curl/GitHub unusable):

```text
error: /…/settings.json is not valid JSON (…); fix or move it before running the installer
H2 recovery skipped, stopped first at: is not valid JSON
```

The second probe (recover-only with the registry unreachable) failed even
earlier, at `could not determine the npm global root (npm root -g / npm prefix -g)`.

**Fix.**

- `main()` now calls `materialize_verify_stack` (embedded heredoc, no network)
  and `recover_interrupted_run` **before** `preflight`, the settings check and
  the Git fetch.
- `journal_write` stores `GLOBAL_PI_PACKAGE`, `GLOBAL_PI_BIN`, `GLOBAL_NPM_PREFIX`
  and `GLOBAL_NPM_ROOT` as shell assignments, so recovery never asks npm where
  Pi lives. Journals from the previous round (lowercase `global_package` /
  `global_bin`) are still understood.
- `global_cli_paths()` and `verify_restored_environment()` are the single
  implementation of "where is the CLI" and "prove the restore" used by both
  recovery paths (`recover()` and `recover_interrupted_run()`); verification is
  skipped as *unproven* (status 3) when Node is absent, instead of aborting the
  restore that already happened.

**After:**

```text
H2 recovered locally despite damaged settings (crash_state=1)
```

`test-rollback.sh` commits this as two cases: recover-only with npm replaced by
a stub that logs any invocation (assertion: the log is empty), curl failing, and
the repo pointed at an unreachable path; and a full run over damaged settings
that must report "was interrupted", restore, and only then stop at the fetch.

## H3 — the journal fails closed

**What was wrong.** `journal_write` ended every step with `|| return 0`. A
read-only state directory, a full disk, or a failed `rename` silently produced
a run with **no crash record** — and the run continued mutating.

**Reproduction against the baseline** (a directory occupies
`.pi-bootstrap/transaction.env.tmp`, so the write cannot succeed):

```text
H3 fail-OPEN: continued, settings=[{ "packages": [ "npm:@narumitw/pi-btw@0.62.0",
    "npm:pi-advisor-flow@0.14.2", …
```

**Fix.**

- `journal_write` returns non-zero on a missing state dir, a write failure, a
  failed atomic `rename`, or the final `mv`, and removes its temporary file.
- `begin_transaction` treats failure as fatal **before** `MUTATION_STARTED=1`
  and removes the empty backup directory, so nothing is left for the next run.
- `install_pi_cli_staged` writes `active activated-cli` before touching the
  global package and refuses to continue if it cannot.
- `commit_transaction` only sets `RUN_COMMITTED` after the `committed` record is
  durable; if it cannot be written, `fail()` leaves `MUTATION_STARTED` set and
  the EXIT trap rolls back rather than leaving backups a later run must undo.

**After:** `H3 fail-closed: refused to continue without a journal`.

Injected faults (`PI_BOOTSTRAP_TEST_JOURNAL`, `…_AT`), one case each:

| Fault | Phase | Expected |
|---|---|---|
| write failure | backup | nothing mutated, no backup/journal/tmp left |
| no space (write) | backup | same |
| rename failure | backup | same |
| write failure | activated-cli | rolled back |
| rename failure | activated-cli | rolled back |
| write failure | complete | rolled back |

## H4 — no window without a recovery record

**What was wrong.**

```bash
move_path "$GLOBAL_PI_PACKAGE" "$BACKUP_DIR/cli/package"
: >"$BACKUP_DIR/cli/package.existed"      # recorded AFTER the move
```

A SIGKILL between the two left the package moved aside with no marker;
`restore_from_backup` requires both `package.existed` and the backup tree, so
the next run deleted the backup as unusable — losing the global Pi.

**Reproduction against the baseline** (a wrapper `mv` kills the installer right
after it moves anything matching `.pi-bootstrap/backup/cli/package`):

```text
H4 old Pi package LOST (moved_aside=1 marker_before_kill=0, backup_left=no)
```

**Fix.** Every decision is recorded before the operation it describes. A crash
in the new window leaves a marker with the package still live:

- `package.existed` exists, `backup/cli/package` absent → restore does nothing,
  the live package was never touched (correct);
- `package.existed` and the tree both exist → restore puts it back (unchanged);
- `package.created` exists → the run removes a Pi it installed (unchanged).

The same ordering is applied to `bin.existed` / `bin-target` / `bin-file` /
`bin.created`. `move_path`'s cross-filesystem fallback now copies into
`<dst>.incoming.$$` and renames it into place, so a crash mid-copy never leaves
a half-copied `backup/cli/package` that recovery would move over the live tree.

**After:** `H4 old Pi package recovered (moved_aside=1 marker_before_kill=1)`.

Committed as five SIGKILL boundaries in `test-rollback.sh`
(`before-package-move`, `after-package-move`, `recorded-cli`,
`after-package-activate`, `after-bin-link`), each followed by a recover-only run
and a full fingerprint comparison of package, bin entry, npm/git trees,
extensions, settings and keybindings.

## Isolation (the "extra requirements")

`run-all.sh` no longer merely *drops* agent-directory overrides. For every test
it now **forces** `HOME`, `TMPDIR`, `npm_config_prefix`, `npm_config_cache` and
`TMUX_CONFIG_FILE` into that test's own scratch tree, and unsets `PI_CONFIG_DIR`,
`NPM_CONFIG_PREFIX`, `NPM_CONFIG_CACHE`, `TMUX`. `PI_BOOTSTRAP_*` fixtures stay
inherited: they are read-only inputs for the real-runtime tests.

Isolation is checked physically, not textually: `lib.sh` gained
`physical_path()`, and `require_scratch_home` now rejects a `HOME` or a
`PI_CODING_AGENT_DIR` that *resolves* into the real home even when the path as
written looks like a scratch directory (a symlink to `/home/<user>`, a symlink
to its parent, or an agent-directory symlink pointing at `~/.pi/agent`).
`test-isolation-guards.mjs` covers all three, and all three are refused.

No test reads, writes, or "repairs" `~/.pi/agent/permission-modes.json`. The
real file was fingerprinted before and after this round (`size=357`,
`sha256=ec33359e…46b11`, mtime `2026-10-23 02:36:32`, unchanged); the incident
from R3 is still the user's to resolve. Credentials were never opened:
`auth.json`/`models.json` are only ever created empty inside a scratch agent
directory by the RPC test.

## Simplification

| Before | After |
|---|---|
| two recovery paths each computing the CLI location inline (4 fallback expressions) | `global_cli_paths()`, one place, journalled first |
| two copies of the "verify the restored stack" block with different skip conditions | `verify_restored_environment()`, same statuses (0 / 3 / error) for both |
| `resolveConfigPaths()` returning 1 or 2 paths, plus `safeReadConfig` and a baseline-merge branch | one path, `requireSupportedAgentDir()` |
| pause/`kill` logic inline in `test_hook` | `test_pause()`, shared by `test_hook` and the new `test_boundary()` |
| rollback-then-verify duplicated in `recover` / `recover_interrupted_run` | shared helpers above; ~35 lines net removed from the extension, ~40 from the installer despite the new guards |

## Tests and results

```bash
scripts/tests/run-all.sh                      # offline
scripts/tests/run-all.sh --fetch              # + fixtures / network
PI_BOOTSTRAP_REAL_UPGRADE=1 PI_BOOTSTRAP_ALLOW_NETWORK=1 \
  scripts/tests/run-all.sh --fetch            # + real CLI acceptance
```

**Before/after on the same tests.** The new tests were run against the baseline
tree (`git archive ae0421f`, plus the new test files) and against this branch:

| Test | Baseline | This branch |
|---|---|---|
| `test-config-path.sh` | FAIL — "selection … mirrored to …$HOME…" | PASS (11 cases) |
| `test-rollback.sh` H4 boundary cases | FAIL — "never reached the boundary" | PASS (5) |
| `test-rollback.sh` H3 journal cases | FAIL — "Fetching permission-modes source…" | PASS (6) |
| `test-rollback.sh` H2 recover-only | FAIL — "could not determine the npm global root" | PASS |
| `test-rollback.sh` H2 damaged settings | FAIL — "settings.json is not valid JSON" | PASS |
| `test-rollback.sh` full file | FAIL | PASS (36 cases) |
| `test-install-run.sh` case 11 (custom agent dir) | FAIL — it installed | PASS — refused before any mutation |
| `test-install-run.sh` case 11b (symlink to default) | n/a | PASS — accepted |
| `test-isolation-guards.mjs` symlink escapes | FAIL (not covered) | PASS — three escapes refused |
| `test-config-source.mjs` (P0) | n/a | PASS — 3 cases on the real loader |

**Offline suite** (no network, no Pi): `22 passed, 8 skipped, 0 failed` — the
skips are the real-runtime tests (including the new P0 test), the real upgrade,
and ShellCheck when it is not on `PATH`.

**Offline suite with the pinned fixtures on `PATH`** (Pi 1.4.0 + the commit +
ShellCheck 0.10.0, network not needed for these tests):

```text
summary: 29 passed, 1 skipped, 0 failed      # the skip is the opt-in real upgrade
```

(The count moved to 30 with the P0 test; the final numbers are below.)

**Full run** in a scratch environment: Pi 1.4.0 installed into its own prefix,
the pinned commit fetched, ShellCheck 0.10.0 on `PATH`, network allowed, the
real-upgrade acceptance enabled:

```text
summary: 30 passed, 0 skipped, 0 failed
```

including the real acceptance test:

```text
PASS previous environment: Pi 1.0.2, 18 commands (…2.7.0, …0.61.1, …0.11.0)
PASS fault injection: the real installer failed after installing the new packages and rolled back
PASS rollback: Pi 1.0.2 is active again and the real loader loads every restored extension
PASS clean run: Pi 1.4.0, permission-modes 2.8.0 at the pinned commit, and every command registered
PASS rerun after upgrade: failure rolled back to the working 1.4.0 stack
```

**ShellCheck** 0.10.0, `--severity=warning`, over `install.sh`, `scripts/*.sh`,
`scripts/tests/*.sh` and `scripts/tests/fixtures/*.sh`: clean (one SC2034 found
and fixed in the rewritten config-path test).

**`git diff --check`**: clean (no whitespace errors).

**CI.** `.github/workflows/ci.yml` is unchanged and already runs the offline
gate (syntax, ShellCheck, embedded sources, pin matrix, the whole stubbed
suite) and the real-matrix job. The new cases run inside
`scripts/tests/test-rollback.sh`, `test-install-run.sh`,
`test-config-path.sh`, `test-isolation-guards.mjs`, and the new
`test-config-source.mjs` is registered in `run-all.sh` (SKIP without the pinned
fixtures, PASS in the real-matrix job, which is the environment where a
`moduleCache` or loader change would show up). **The workflow itself was not exercised by GitHub Actions here**: this
environment has no runner, so the CI claim is "the same commands pass locally",
not "the workflow ran".

## Read-only review of this diff

A second agent was asked to review the diff independently; it produced no
output within 40 minutes and was stopped rather than waited on. I reviewed the
diff myself instead. Two low-severity items found, both stated rather than
silently accepted:

1. **Leftover copy staging after a crash.** `move_path`'s cross-filesystem
   fallback can leave `<dst>.incoming.<pid>` behind if the process is killed
   during the copy. It is inside the backup directory and is never mistaken for
   a finished backup (every reader looks for the exact `package` / `trees/<name>`
   path), but it is residue the user may notice. Not fixed: cleaning it up would
   require deleting a directory at recovery time whose contents are
   indistinguishable from a partial backup, which is the more dangerous
   operation.
2. **`agent_dir` in the journal is written but never read.** The journal is
   located under `AGENT_DIR`, so a recovery run already knows the directory it
   came from; the field is documentary. Kept because it makes the journal
   readable by hand; harmless.

No finding was found in the areas H1–H4 actually target: no remaining write
path outside Pi's directory, no ordering hole before recovery, no code path
that continues after a journal failure, and no marker/backup combination that
destroys the live package.

## Residual risks

- **A custom agent directory is UNSUPPORTED** (P0). The installer refuses it and
  `/classifier-model` refuses it; both explain why. Users who need the stack
  elsewhere must change `HOME` or the npm prefix. Making `PI_CODING_AGENT_DIR`
  work needs an upstream change to permission-modes (read the variable, or
  export `setConfigPath`), which would change the pin, the tree, the manifest
  and the audit — out of scope for this round and not to be done silently.
- **`permission-modes` upstream was not modified.** The 69-file SHA256
  manifest, the commit pin and the tree pin are untouched, so every existing
  verification still proves the same bytes.
- **A SIGKILL during the restore itself** can still leave a partially restored
  tree. The journal and backups survive and the next run retries; this round
  does not make the restore atomic.
- **Journal faults are injected, not real.** `PI_BOOTSTRAP_TEST_JOURNAL`
  simulates a write failure, ENOSPC and a failed `rename` in-process. A genuine
  full filesystem was not created (the suite must not fill the developer's
  disk); the simulated failure exercises the same branches.
- **SIGKILL boundaries are injected at named points**, not at arbitrary
  instructions. The five boundaries are the ones recovery depends on.
- **CI is unexecuted here** (no GitHub runner in this environment).
- **The developer's real `~/.pi/agent/permission-modes.json` still contains the
  R3 test fixture** (`sha256 ec33359e…`). This round did not touch it and did
  not attempt to repair it; restoring it needs the user's own classifier model
  and rules.

## Local commits

Only local commits were made: no push, merge, tag, or production change.

| Commit | Contents |
|---|---|
| `8f58d91` | H1 fail-closed classifier path, H2 local-first recovery, H3 journal fail-closed, H4 marker ordering; new and rewritten tests; forced test isolation |
| `c047581` | README / TESTED_VERSIONS / risk review / maintenance prompt for H1–H4; first version of this report |
| `5ed2dc3` | P0: `require_supported_agent_dir` (installer + extension), physical-path isolation guards, `test-config-source.mjs`, refusal/symlink cases |
| this commit | README / TESTED_VERSIONS / risk review / maintenance prompt for P0; this report's P0 section and final numbers |

## Verdict

**READY_FOR_INDEPENDENT_REVIEW.** H1–H4 are each closed by a fix and by a
committed test that fails on the baseline and passes here, including an offline
recovery over damaged settings and a SIGKILL matrix that no longer loses the
global Pi. P0 is closed by *proving* the gate's configuration source on the real
loader and refusing the unsupported layout, rather than by a mirror or an
upstream patch.

Two things this branch cannot fix and does not hide:

1. `/classifier-model` and the installer are unavailable under a custom agent
   directory (an upstream limitation, documented as UNSUPPORTED).
2. The workstation file an earlier round's test overwrote is still the user's to
   restore; this round only guarantees it cannot happen again from the suite.
