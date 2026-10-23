# R3 closure report — upgrade safety and review findings H1/H2, M1–M5

Baseline: `277e071cf0af14e82688d4948d75144e7593507d` on `r2-review-fixes`.
Branch: `r3-closure`. **No version pin changed**: Pi 1.4.0 / permission-modes
2.8.0 @ `cf77816` / pi-btw 0.62.0 / pi-advisor-flow 0.14.2 / minimal-mode v1.4.0.

The acceptance criterion used throughout was not "`recover()` was called" but
"after the failure the previous Pi and its packages still load". Every High
finding is backed by a test that starts from a working old installation, injects
a fault, and then loads the result with the **real** Pi extension loader.

**Read "Incident" at the end first if you care about the workstation state: while
developing this, one test run wrote the developer's real
`~/.pi/agent/permission-modes.json`.** The code findings are nevertheless closed.

## Status summary

| Finding | Status | Evidence |
|---|---|---|
| H1 — old plugins were not really restored | **FIXED** | `test-rollback.sh` (19 failure shapes), `test-real-upgrade.mjs` (real Pi 1.0.2 reload) |
| H2 — `ERR` trap could not reliably trigger rollback | **FIXED** | `test-rollback.sh`: nested `$( )`, pipeline, subshell, `SIGINT`/`SIGTERM`/`SIGKILL` |
| M1 — custom Pi config directory mismatch | **FIXED** (with a documented mirror) | `test-config-path.sh` |
| M2 — tests could modify production | **FIXED** | `test-isolation-guards.mjs`, `lib.sh require_scratch_home`, `test-default-stack.mjs` copy |
| M3 — version checks not strict | **FIXED** | `lib-pi.mjs` exact pins, `test-version-matrix.mjs` |
| M4 — config restore incomplete | **FIXED** | `test-rollback.sh` keybindings/tmux cases |
| M5 — pin update not atomic | **FIXED** | `test-pin-helper.sh` cases 7–8 |
| P2 — CI, docs, residual-risk review | **DONE** | `.github/workflows/ci.yml`, README, TESTED_VERSIONS, risk review |

## H1 — a failed upgrade now leaves a working environment

### What Pi 1.4.0 actually does (read from `packages/coding-agent/src/core/package-manager.ts`)

- `installAndPersist` = `install()` **then** `addSourceToSettings()`.
- `installGit` clones into `~/.pi/agent/git/<host>/<path>`, checks out the ref,
  and runs `npm install --omit=dev --legacy-peer-deps` **inside the checkout**;
  on failure it `rm -rf`s the checkout.
- `removeGit` is `rmSync(targetDir, {recursive, force})` and *then* the settings
  entry is removed by `removeAndPersist`. `pi remove` therefore destroys files
  before it can fail with "No matching package found".
- npm packages live in `~/.pi/agent/npm/node_modules/<name>` and are removed with
  `npm uninstall`.
- The global CLI is an ordinary `npm install -g`: the package directory is
  replaced in place and `bin/pi` is a relative symlink into it.

So the R2 rollback — restore `settings.json`, leave packages alone — could
restore a configuration that pointed at files the failed run had already
deleted, and could never restore the old global Pi. That is exactly what the
review said.

### The transaction (`install.sh`)

| Step | Code | Why |
|---|---|---|
| Journal before any mutation | `begin_transaction` (l. 1256), `journal_write` | survives `SIGKILL`; the next run knows a run was in flight |
| Global Pi staged, version-checked | `install_pi_cli_staged` (l. 678) | the live prefix is never half-written by npm |
| Old Pi package **moved** aside, new one moved in | same | `rename` on one filesystem; no copy window |
| Old `bin/pi` saved as link target *or* exact file | same + `restore_from_backup` | npm's usual symlink and a plain wrapper are both real shapes |
| `npm/` and `git/` **moved** aside, working copies restored in place | `snapshot_plugin_trees` (l. 1229) | `pi remove` can only destroy the copy |
| `settings.json`, both extensions, `keybindings.json`, `.tmux.conf` recorded | `snapshot_settings`, `track_install_target` (l. 1205) | restore or delete, decided per file |
| Exact versions checked | `verify_installed_versions` (l. 762) | "some version that loads" is not the matrix |
| Final proof on the real loader | `verify_installed_stack` (l. 1159) | the installed Pi must start and register the commands |
| Commit only after success | `commit_transaction` | a committed run leaves no journal |

Rollback (`restore_from_backup`, l. 1273) is data-driven: it walks
`backup/files.tsv`, `backup/created.list`, `backup/trees/*`, `backup/cli/*` and
restores whatever is present. That is what makes the trap path and the
after-crash path the same code. It removes a Pi the run *created* when there was
none before, so a failed first install leaves no `pi` behind.

`recover()` (l. 1378) then runs the embedded `verify-stack.mjs` in `verify` mode
against the state captured before the run (`pre-state.json`): same Pi version,
same package versions, and every command the previous installation registered
must be registered again. Outcomes are explicit:

- verified → backups deleted, "previous environment restored and verified";
- unprovable (no real loader, e.g. the stub `pi`) → backups deleted, the message
  says verification was not possible — **a real install fails instead** unless
  `PI_BOOTSTRAP_ALLOW_UNVERIFIED=1` is set (only the test suite does);
- verification failed → backups kept, the next run refuses to start.

## H2 — rollback no longer depends on an `ERR` trap

Bash does not inherit `ERR` into functions, command substitutions, subshells, or
pipelines (only `set -E` does, and even then a failing command in a `||` list is
excluded). The installer therefore has:

- `set -euo pipefail` + one `EXIT` trap installed in `main` (`on_exit`, l. 265),
  which runs rollback exactly once, only in the process that owns the run
  (`BASHPID == RUN_PID`; a subshell that inherited the trap only cleans its own
  temp files);
- explicit `fail` for expected errors, which keeps the original message and sets
  `FAIL_REPORTED` so the trap does not invent a second error;
- `INT`/`TERM`/`HUP` handlers that roll back and exit `128+n`;
- a journal + moved trees for `SIGKILL`/power loss, where no trap can run:
  `recover_interrupted_run` (l. 1418) restores before the new run mutates
  anything, and `PI_BOOTSTRAP_RECOVER_ONLY=1` stops after recovery (test hook).

The tests inject failures *through* these paths rather than around them:
`PI_BOOTSTRAP_TEST_FAIL_AT` stages call a nested function inside `$( )`, a
pipeline that fails under `pipefail`, and a failing subshell. Signals are
delivered by the installer to itself (`PI_BOOTSTRAP_TEST_SIGNAL`), because a
non-interactive shell starts background jobs with `SIGINT` ignored — a test that
signalled a background job would "pass" without ever running the trap.

## M1 — `/classifier-model` uses Pi's directory

`extensions/classifier-model.ts` now resolves `PI_CODING_AGENT_DIR` the way Pi's
`getAgentDir()` does (empty → `$HOME/.pi/agent`; `~` expanded; relative paths
resolved), per invocation, and writes `permission-modes.json` there.

permission-modes 2.8.0 resolves its own config from `homedir()/.pi/agent` and
ignores the variable (verified in the pinned source: `config.ts` line 47). With a
custom directory, the two paths differ and the gate would never see the choice.
The extension therefore also mirrors the classifier block to the upstream path,
preserving that file's other keys, and seeds the baseline from it on first use so
an existing model/timeout is not replaced by defaults. `PI_AGENT_DIR` is
deliberately ignored here (Pi ignores it); the installer still accepts it and
translates it for the `pi` process.

The embedded copy in `install.sh` is regenerated by
`scripts/check-embedded-extension.sh --write`, which also now owns the embedded
`verify-stack.mjs`; the check extracts both and compares bytes.

## M2 — tests cannot write a production directory

- `scripts/tests/lib.sh`: `require_scratch_home` refuses `HOME` when it is the
  account's real home, and refuses a `PI_CODING_AGENT_DIR` outside `HOME`.
- `run-all.sh` drops inherited `PI_CODING_AGENT_DIR`/`PI_AGENT_DIR` for every
  test, so a caller's environment cannot redirect one.
- `test-default-stack.mjs` **copies** the agent directory it is given into a
  scratch tree and loads the copy; the original is only read.
- `test-classifier-config.mjs` refuses an agent dir outside its scratch `HOME`
  and a non-scratch `HOME` before writing anything.
- `test-isolation-guards.mjs` asserts all of the above (and that default-stack
  SKIPs, rather than loads, a mismatched stack).

## M3 — exact versions only

`lib-pi.mjs` pins Pi 1.4.0, permission-modes 2.8.0 @ `cf77816`, pi-btw 0.62.0,
advisor 0.14.2 and the minimal-mode SHA256. Every real-runtime test calls
`skipUnlessPi` / `skipUnlessPackage` / `skipUnlessPinnedPermissionModes`; the
installer re-checks the installed versions itself. `test-version-matrix.mjs`
asserts `install.sh` and the harness agree on all nine pins, so a bump cannot be
half-applied. A newer Pi is a SKIP, not a PASS.

## M4 — configuration files in the rollback

`keybindings.json` and `.tmux.conf` are recorded before they are written
(`track_install_target`; tmux is recorded in every branch that may rewrite the
file, including the "unsupported version" cleanup), and removed again when they
did not exist. Cases: created-then-failed (must be gone), pre-existing with user
content (must be byte-identical), and a late failure after both were written.

## M5 — atomic pin updates

`update-permission-modes-pin.sh --write` now writes a candidate next to
`install.sh`, validates it (`bash -n`, the three pin lines, and a normalised diff
proving nothing outside the pin block changed), copies the mode, and `mv -f`s it
into place. A failing writer (injected with `PI_BOOTSTRAP_PIN_NODE`) leaves the
original byte-identical and no temp files.

## P2 — CI, documentation, residual review

`.github/workflows/ci.yml`: a required offline job (syntax, ShellCheck on every
script, embedded sources, pin matrix, stubbed suite) and a network job that
installs the pinned matrix and runs the real-runtime and real-upgrade tests.
No secrets, nothing published. README, TESTED_VERSIONS, the risk review and the
monthly maintenance prompt were updated to describe what is now true.

## Tests

```bash
scripts/tests/run-all.sh                                  # offline
scripts/tests/run-all.sh --fetch                          # download fixtures
PI_BOOTSTRAP_REAL_UPGRADE=1 PI_BOOTSTRAP_ALLOW_NETWORK=1 \
  scripts/tests/run-all.sh --fetch                        # + real acceptance test
```

New or substantially rewritten:

| Test | Covers |
|---|---|
| `test-rollback.sh` | 19 failure shapes: backup/remove/install/verify/extensions/keybindings/tmux/last step, fresh machine, created-file removal, customised config, advisor install failure, tampered source, nested/pipeline/subshell, `SIGINT`/`SIGTERM`/`SIGKILL` + recovery, committed-run cleanup |
| `test-real-upgrade.mjs` | real Pi 1.0.2 + 2.7.0/0.61.1/0.11.0 from npm; real `install.sh` fails after installing 1.4.0/2.8.0; real 1.0.2 loader reloads all three; clean run then verifies the pinned matrix |
| `test-config-path.sh` | default/custom/relative/trailing-slash/`~` agent dirs, `PI_AGENT_DIR` ignored, mirror contents, reload persistence |
| `test-isolation-guards.mjs` | real-HOME refusal, agent dir outside HOME, default-stack copy + SKIP |
| `test-version-matrix.mjs` | installer pins == harness pins; embedded verifier == source |
| `test-pin-helper.sh` (7–8) | repeat write byte-identical, failing writer leaves the file intact |
| `lib-pi.mjs`, `lib.sh`, `run-all.sh` | exact-version skipping, scratch-home guard, override stripping |

## Results

Offline suite (no network, no Pi): **22 passed, 7 skipped, 0 failed** — the skips
are ShellCheck (not installed on the host by default), the five real-runtime
tests, and the real upgrade test.

Full acceptance run in a fresh scratch environment: Pi 1.4.0 installed in a
scratch prefix, the pinned commit fetched, a copy of an installed agent
directory, permission-modes 2.7.0 fetched from npm for the regression control,
ShellCheck 0.10.0 on `PATH`, network allowed:

```text
== static checks           shellcheck, embedded sources, pin matrix          PASS
== installer behavior      10 + 11 + 23 + 5 + 8 + 3 cases                   PASS
== extension behavior      10 + 7 cases                                      PASS
== real runtime            lifecycle, gate (real loader), baseUrl regression,
                           RPC smoke, default stack, real upgrade/rollback   PASS
summary: 29 passed, 0 skipped, 0 failed
```

The real-upgrade test's decisive lines:

```text
PASS previous environment: Pi 1.0.2, 18 commands (…@2.7.0, …@0.61.1, …@0.11.0)
PASS fault injection: the real installer failed after installing the new packages and rolled back
PASS rollback: Pi 1.0.2 is active again and the real loader loads every restored extension
PASS clean run: Pi 1.4.0, permission-modes 2.8.0 at the pinned commit, and every command registered
```

## Remaining risks and rollback boundaries

- **A `SIGKILL` during the restore itself** can leave a partially restored tree.
  The journal and backups remain and the next run retries; nothing is silently
  discarded, but the machine is not usable until that run happens. Not claimed
  as transactional.
- **Deleting `.pi-bootstrap/backup` by hand** removes the ability to roll back.
  The next failed run reports that verification could not proceed and keeps
  what is left.
- **Rollback restores the state at the start of the run**, not an older matrix.
  It never touches `permission-modes.json`, `advisor.json`, `auth.json`, or
  `models.json`.
- **Verification needs a real Pi loader.** On a stub or a non-standard Pi build
  nothing can be proven; a real install fails rather than claiming success.
- **Root-owned npm prefix**: preflight now refuses before any backup. The
  documented workaround is a user-owned prefix (`npm config set prefix`).
- **Mirror file**: with a custom agent directory two files exist. `/classifier-model`
  keeps them in agreement; a hand edit of one is not propagated.
- **The real-upgrade test requires the network** and real registry packages. It
  is opt-in, so an offline run reports it as SKIP, not PASS.
- **CI is unexecuted here** (no GitHub runner in this environment). The workflow
  duplicates commands that were run locally, but its YAML has not been exercised
  by Actions.

## Incident — the developer's real `permission-modes.json` was overwritten

This must be reported as a failure of the execution policy, not as a code issue.

- **What happened.** Before the isolation guards existed, I ran
  `PI_CODING_AGENT_DIR="$HOME/.pi/agent" node scripts/tests/test-classifier-config.mjs`
  to show that the test would follow a custom directory. The test writes
  `permission-modes.json`, so it wrote the *fixture* into
  `/home/dyr/.pi/agent/permission-modes.json` (02:28, again 02:36).
- **What is there now** (357 bytes, sha256 `ec33359e…46b11`): the test fixture —
  `classifier.model = "audit/model"`, `timeoutMs: 12345`, `failClosed: true`,
  `stage: "tool"`, `enabled: true`, plus fixture permission rules
  (`allow Read(*)`, `deny Bash(rm *)`, `ask Write(*)`) and two `custom` keys.
  A copy is at `/tmp/r3-work/incident/permission-modes.json.after`.
- **The original content is not recoverable from this machine.** I searched
  `.pi` backups, editor swap files, trash, shell history, every file under
  `$HOME` mentioning `classifier`, and the previous session transcripts; no copy
  of the pre-run file exists. I cannot reconstruct the user's classifier model
  or permission rules, and I have deliberately **not** written the file again.
- **Consequence to fix.** The gate now reads fixture rules and a classifier model
  (`audit/model`) that does not exist, so the classifier will fail closed. Unless
  those values are wanted, the user should rewrite the file (for example
  `classifier.model` to a configured model, and the `permissions` block to their
  real rules) or delete it.
- **Root cause and the fix that now prevents it.** The test trusted
  `PI_CODING_AGENT_DIR` blindly. It now refuses any directory outside a scratch
  `HOME`, `lib.sh` refuses the real home, `run-all.sh` strips inherited
  overrides, and `test-isolation-guards.mjs` asserts all three (M2). That is
  exactly the failure mode M2 describes, encountered by the person fixing it.
- **Everything else in the production tree was left alone**: `settings.json`,
  `keybindings.json`, `models.json`, `auth.json`, the two extensions and
  `.tmux.conf` still have their pre-session mtimes. No credential was read, no
  package was installed or removed there, and no model configuration outside
  this one file was touched.

## Local commits

| Commit | Contents |
|---|---|
| `117ebf3` | transactional install (H1), EXIT/journal recovery (H2), classifier path + mirror (M1), isolation guards (M2), exact versions (M3), keybindings/tmux rollback (M4), atomic pin helper (M5), new tests |
| `ff2075f` | README/TESTED_VERSIONS/risk-review/maintenance docs, GitHub Actions CI |
| `82a2462` | fresh-machine rollback (remove a Pi the run created), writable-prefix preflight, fresh-install test |
| `93c0fff` | simplify the bin-entry restore |
| `e130bff` | this report (`docs/r3-closure-report.md`) |
| `a0bd9c0` | records `e130bff` in the table above |
| `30312ac` | lists the report commits (this table) |

HEAD is `30312ac`; the tree is clean and nothing was pushed, merged, tagged, or published. No pin was changed.

## Verdict

**READY_TO_MERGE for the code**, with the incident above requiring the user's
attention before the branch is used: H1, H2, M1–M5 are closed and each is backed
by a committed, reproducible test, including a real-CLI upgrade failure after
which the previous Pi 1.0.2 environment loads again. The one thing this branch
cannot fix is the workstation file a test of mine overwrote; restoring it needs
the user's knowledge of their intended classifier model and rules.
