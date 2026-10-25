# Independent hardening audit — 2026-10-25

Baseline: `076f1c3df50f66e6d4b3fbb540e88028a6695d9c`.
Branch: `codex-independent-hardening`.
Worktree: `/Users/yiran/.codex/worktrees/codex-independent/pi-bootstrap`.
Final status: **READY_FOR_INDEPENDENT_REVIEW**. All critical acceptance gates passed before the local deliverable commit. The final commit SHA is reported in the chat (and is reproducible with `git rev-parse HEAD`).

This implementation used only the frozen checkout and necessary public upstream
artifacts. No later development branch/commit was inspected, fetched, compared,
reused or cherry-picked. No subagent was used. The original checkout and `main`
were not modified. No push, merge, tag or package publication was performed.

Deliverables (15 files): `install.sh`, `README.md`, `TESTED_VERSIONS.md`, this
report, and `scripts/bootstrap.mjs`, `scripts/pins.mjs`,
`scripts/build-installer.mjs`, `scripts/test-support.mjs`,
`scripts/test-offline.mjs`, `scripts/test-real.mjs`,
`scripts/test-classifier.mjs`, `scripts/real-fixture.mjs`,
`scripts/signal-fixture.mjs`, `scripts/check-embedded-extension.sh`,
`scripts/test-tmux.sh`. The repository classifier extension itself is unchanged.

## Design and security invariants

The former shell installer is generated from one Node transaction engine,
explicit version/manifest data, and the unchanged classifier extension. Both
local and curl-to-bash installs execute the same embedded engine. The generation
check compares the entire result, including pins and classifier bytes.

Package migration parses exact identities. It preserves string/object entries,
autoload/resource filters, unrelated package entries and settings. Duplicate
identities, duplicate JSON keys, malformed entries and alternate npm command
configuration fail closed. `pi remove` errors propagate into rollback.

Permission-modes retains version 2.8.0, commit
`cf77816f28e102409dddbf8e537e4cf57aa092f0`, tree
`480649739171c272f355850cf6b6228ffa823c0c`, and the baseline 69-file SHA256
manifest. A new staging checkout is verified before it can execute. It has no
runtime dependencies; the verified checkout is copied into Pi's git package
tree and the exact immutable source is persisted in settings. This avoids
Pi's initial git installation lifecycle entirely. npm installs explicitly
disable scripts through flags and both environment spellings.

The actual Pi 1.4.0 package-manager artifact was inspected: `installGit()` calls
`npm install --omit=dev --legacy-peer-deps` on a new checkout, without an
ignore-scripts argument. The committed lifecycle fixture calls that real
implementation against a local git repository: the positive control executes
postinstall/prepare and creates a marker, while the disabled case creates none.
Upstream references: [Pi v1.4.0 package manager](https://github.com/earendil-works/pi/blob/v1.4.0/packages/coding-agent/src/core/package-manager.ts),
[pinned permission-modes](https://github.com/GeorgeDong32/pi-permission-modes/tree/cf77816f28e102409dddbf8e537e4cf57aa092f0).

The state file keeps the name `transaction.env` but is bounded, versioned,
canonical JSON. It is never sourced/evaluated. Unknown/duplicate keys, invalid
encodings, statuses, phases and PIDs are rejected. Backup inventories use fixed
slot identifiers, validated relative names, entry types, modes, link targets
and SHA256 hashes. No record supplies a restore destination or executable
command. The prefix is independently derived from the current environment or
Node location; a hash binds all fixed destinations to that invocation.

Physical path validation walks symlinks and `..` in component order, rejecting
missing-component normalization tricks, dangling/cyclic links and unsupported
redirection. The default agent, state, backup, journal and manifests are checked
before reads/deletes. Managed trees reject escaping symlinks, hardlinked files,
foreign ownership and writable-by-other-user entries. The pi bin link may name
only the anchored CLI's supported entrypoints. CLI metadata is also allowlisted.
Custom agent roots are unsupported and rejected before journal access, mkdir,
commands or network. An alias proven to resolve to the exact default directory
is accepted; no configuration is mirrored into another HOME.

Complete CLI/bin, npm/git/extension trees, settings, keybindings, tmux and
installer temporary-file slots are snapshotted. Files and directories are
fsynced, then the manifest and journal are fsynced before replacement. Each
child waits behind an IPC gate until its worker PID is recorded durably. Parent
death terminates the child process group. Recovery waits rather than trusting
a stored PID as permission to kill an arbitrary process.

Recovery validates the complete journal, every manifest record, every backup
hash and all destinations before its first destructive operation. It works
before parsing damaged live settings and without npm/curl/git. Restored hashes,
CLI version and real loader commands must match the snapshot evidence. Errors
retain the backup and journal. SIGKILL during restoration can leave a partial
live tree; the committed test kills restoration after the first file and proves
that the next invocation completes it. A truncated journal temporary is stored
as inert `journal-fragment` evidence, never interpreted.

## Acceptance evidence

Environment: macOS arm64; Node 24.22.1; npm 11.19.1; ShellCheck 0.11.0 downloaded
to scratch from the official release (no host package installation).

All package operations used scratch HOME/TMPDIR, both npm prefixes, both caches,
both user/global npmrc settings, Pi directory, tmux file and scratch-first PATH.
The harness asserts `npm prefix -g` and `npm root -g` are inside that exact
scratch prefix before real global operations. It does not inspect production
Pi configuration, credentials or historical backups. This is evidence of
isolation for this run, not a claim that the workstation was restored.

| Gate | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Final offline suite | 44 | 0 | 0 |
| Final real matrix suite | 23 | 0 | 0 |
| Bash syntax, Node source syntax, generated Node syntax, embedded sync, ShellCheck, diff whitespace | 6 | 0 | 0 |
| Real-provider interactive conversations; physical tmux key forwarding | 0 | 0 | 2 |

The offline suite includes executable-looking journals, duplicate/unknown keys,
control bytes, encoding/size/PID attacks, symlinked agent/state/backup/journal/
manifest parents and descendants, valid-looking committed evidence, file hash
tampering and late invalid manifest records. External directory inventories
and sentinel hashes remain unchanged after refusal. Legacy `files.tsv`,
`created.list`, `trees` and `files` records cannot redirect recovery: unsupported
backup evidence is refused. Tests compare actual trees and bytes, not messages.

The real suite uses a fresh exact 1.4.0/2.8.0/0.62.0/0.14.2 matrix and actual
Pi 1.0.2 + permission-modes 2.7.0 + btw 0.61.1 + advisor 0.11.0 for recovery.
It checks bin links, hashes, all managed trees, preserved user files and real old
loader registration after an upgrade fails following CLI replacement. It also
performs actual offline old-loader recovery and successful object migration.
The loopback HTTP fixture loads the pinned extension through Pi's real loader
and uses real ModelRuntime/ModelRegistry: 2.7.0 misrouting is reproduced, 2.8.0
honors auth-resolved baseUrl, and allow/deny, malformed/empty/timeout/503 cases
are checked. Fault cases have one SDK request per attempt and at most three
extension attempts. Ask/Plan/Auto tests cover Bash, PowerShell mapping, embedded
commands and outside-cwd writes without enabling bypass.

Evidence (intentionally outside git):

- `/tmp/pi-independent-parent/run.GLOUPt/final-offline-3.log`
- `/tmp/pi-independent-parent/run.GLOUPt/final-real-3/results.json`
- `/tmp/pi-independent-parent/run.GLOUPt/final-real-3/failed-upgrade.log`
- `/tmp/pi-independent-parent/run.GLOUPt/final-real-3/classifier-requests.json`

## Efficiency and rework

Start: 2026-10-25 12:00:03 UTC (05:00:03 America/Los_Angeles).
Initial code freeze: 12:25:57 UTC; final freeze after rework: 12:32:30 UTC.
Acceptance completed: 12:41:27.734 UTC (05:41:27 America/Los_Angeles), 41m25s after task start. Documentation and Git closure followed; total wall time is approximately 42 minutes.

Activity time log (rounded manual attribution; implementation/tests/docs were interleaved, so these are not CPU timings): baseline/source inspection ~1m12s; implementation ~14m; targeted tests/debugging ~8m; documentation ~3m; final verification and its two rework cycles 15m31s (12:25:57–12:41:28). The exact start/freeze/acceptance timestamps above are the authoritative elapsed-time record.

There were 14 targeted test batches (including isolated runtime preparation,
classifier, installer, lifecycle, old-loader rollback and offline subsets),
three final offline suite runs, and three full network-suite invocations.
The first two network invocations stopped early at a failed gate; the final
one completed all 23 gates before commit. The first invocation had 1 PASS/1 FAIL and the second had 3 PASS/1 FAIL before stopping; these failed attempts are retained, not counted as final PASS. Static syntax checks are counted separately.
No unbounded fuzzing or subagents were used.

Two final-verification defects were corrected: a committed read-only probe
rewrote the journal's worker PID (fixed by limiting writes to active/recovering
transactions), and a pre-state-directory probe used a nonexistent cwd (fixed
with a HOME fallback). Both have regression tests. An earlier patch application
was rejected before changing files and was reapplied correctly. No acceptance
criterion or version pin was weakened.

## Remaining limits

- The same-UID attacker/concurrent Pi process is outside the cooperative lock
  model; stop Pi sessions during maintenance. No claim of race immunity against
  a hostile process that can rewrite private state is made.
- Durability depends on OS/filesystem fsync semantics. Cleanup interrupted by
  power loss or conflicting/truncated retained evidence may require manual
  review. Recovery deliberately refuses ambiguity rather than deleting it.
- CLI loader verification does not execute real provider conversations. The
  follow-up below corrects the original probe: it now uses the installed Pi
  package manager’s enabled-resource resolution and honors user filtering.
- npm transitive ranges remain upstream-controlled (notably pi-btw's tui-kit).
  The direct version/source pins are exact; this is not a fully vendored npm
  dependency closure. Unreferenced npm temporary artifacts may remain after a
  package-manager crash; the anchored working CLI/bin and package trees restore.
- Actual tmux terminal forwarding and PowerShell execution are not certified;
  all seven tmux transformations and PowerShell approval mapping are tested.
- Upstream classifier limitations recorded in the baseline remain, including
  Codex classifier temperature incompatibility. No bypass or permission
  weakening is introduced.


## Review follow-up — P0 probe / P1 fixture isolation

Starting HEAD: `94839c6f729fa68e962645c42de8d4df87d4b579`, on
`codex/independent-hardening-review`. This follow-up changes only the two
requested Findings and their regression/acceptance support; no version pin or
transaction architecture changes. Earlier results above are historical. No
GLM development branch was viewed or reused, and no subagent was started.

P0: `Transaction.probe()` now delegates resource selection to the **installed
Pi’s** `DefaultPackageManager.resolve()` with an in-memory SettingsManager,
project resources disabled, no builtin list and missing sources skipped. It
passes only `enabled` extension paths to the real loader. This preserves
package resource filters (including `extensions: []`), autoload deltas, global
extension overrides and automatic directory discovery. It no longer adds
`.mjs` files that Pi would not discover. The Pi 1.4.0 npm artifact’s
`resource-loader.js` / `package-manager.js` were inspected in a newly created
scratch directory; no later repository branch was consulted.

`scripts/test-probe.mjs` creates module-evaluation markers for a disabled npm
package, excluded package resources, an autoload-disabled resource, an excluded
local extension and an auto-discovered `.mjs` candidate. None may execute.
Enabled old/local, filtered, autoload and directory entrypoint commands must
still register. Targeted runs passed on actual Pi 1.4.0 and 1.0.2 in distinct
fresh scratch installations. The real matrix also includes this regression.

P1: `real-fixture.mjs` calls the standalone scratch environment guard **before
context/journal/CLI access**. The mutating fail-upgrade and lifecycle actions
independently check the receipt and ownership/types, canonical HOME/TMPDIR,
both npm prefix/cache/userconfig/globalconfig spellings, Pi agent directory,
tmux/XDG paths and each existing component. Symlinks and hardlinks are refused.
PATH contains only scratch `prefix/bin` and `tools/bin`; the latter holds
content-verified launchers for the selected runtime/system binaries. Mutation
entrypoints reject shadowed tools, then verify npm’s actual prefix, root,
cache and config paths before invoking Transaction.install(). The offline
probe action does not run npm preflight, so unavailable npm remains supported.
The launchers reference read-only runtime/system tools; no host global Pi
installation or production configuration is queried.

The isolation regressions invoke `real-fixture.mjs fail-upgrade` directly,
without caller-side `verifyScratch()`, against 26 malformed/escaping setups.
An npm tripwire would write a marker and mutate a simulated host-global Pi
sentinel in a separate fresh scratch directory. Every refusal must occur
before that tripwire, and both complete directory inventories/hashes must
remain identical. A valid environment is independently accepted as a positive
control. These tests are included in the full offline suite.

Follow-up validation (final acceptance passed):

| Gate | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Final offline suite (one run) | 71 | 0 | 0 |
| Final real matrix (one run) | 24 | 0 | 0 |
| Static verification groups | 6 | 0 | 0 |
| Real-provider conversations / physical tmux forwarding | 0 | 0 | 2 |

Time log: started 2026-10-25 13:43:49 UTC (06:43:49 America/Los_Angeles).
Code freeze / final verification start: 13:53:26 UTC (06:53:26 America/Los_Angeles), 9m37s after start. Acceptance completed: 14:03:21 UTC (07:03:21 America/Los_Angeles), elapsed 19m32s. Final verification took 9m55s; inspection/implementation/targeted testing took 9m37s. Documentation was interleaved, and local Git closure followed acceptance.
Five targeted batches ran before freeze: isolation (26 PASS / 1 FAIL, then
27 PASS / 0 FAIL), actual Pi 1.4.0 marker regression (PASS), actual Pi 1.0.2
marker regression (PASS), worker/recovery subset (8 PASS / 0 FAIL). The initial
positive-control test incorrectly compared an empty cache with the valid npm
preflight’s new scratch logs/compile cache; its snapshot was moved after the
allowed preflight. All negative-path full-inventory assertions were retained.
No full suite was used during iteration.

Fresh follow-up evidence is outside git under
`/tmp/pi-review-followup.rOG2vG/`; no earlier temporary evidence or historical
backups were reused. Final outcome: **READY_FOR_INDEPENDENT_REVIEW**. All critical gates passed before creating one local follow-up commit. Its SHA is reported in chat / `git rev-parse HEAD`.
One full offline suite and one full real matrix were run after freeze, with no final-suite failures or reruns. The two supplemental SKIPs remain real provider conversations and physical tmux key forwarding; neither is used as proof for these Findings. Evidence files include `final-offline.log`, `final-static.log`, `final-real.log` and `final-real/results.json` (plus failed-upgrade/classifier logs).

Remaining limits: this is a checked scratch harness, not an OS sandbox. It relies on trusted Node/npm/system binaries and does not protect against a hostile same-UID process racing filesystem changes after validation. Probe remains coupled to the installed pinned Pi’s resource-resolution API; actual 1.4.0 and 1.0.2 regressions and the full rollback matrix passed. The earlier general durability/dependency limits remain.

No push, merge, tag, main modification or production Pi operation is authorized
or performed in this follow-up.


## Final review follow-up — probe side effects before backup

Starting HEAD: `bd8ff652ef71251f92e39d569ea8991d277f3f01`, on
`codex/independent-hardening-review`. This section supersedes earlier acceptance
counts for the final snapshot-contamination Finding. No GLM development branch
was read or reused; no subagent or unbounded fuzzing was used.

The fix is confined to `probe()` and its generated installer copy. The existing
journal/manifest format, durable backup order, restoration logic, exact pins and
permission rules remain unchanged. Every probe (including pre-backup,
post-install, idempotence and recovery validation) now copies the anchored
managed slots into a private temporary HOME/agent/CLI prefix. The copy also
contains the permission/profile/advisor JSON needed by the pinned extensions.
It does not include the original journal, backups, auth.json or models.json.
Verification uses the copied CLI and copied enabled extension entrypoints.
Temporary copies are disposable verification inputs, not recovery evidence;
COPYFILE_FICLONE is requested as an optimization, never a hardlink to live data.

HOME, cwd, agent, tmux, npm prefix/cache/userconfig/globalconfig and XDG paths
point into the copy. Node preload/output-cache variables are cleared or rebased.
The subprocess has Node filesystem read/write permissions only for that private
copy; child processes, workers, native addons and WASI are not enabled. A failed
probe is never retried with broader permissions. An accidental absolute write
to the original managed file is refused. External local resource settings and
entrypoints resolving outside the copied agent are refused before module
loading. A managed-root TMPDIR or permission-wildcard path is refused before
creating the copy. Cleanup revalidates its physical parent/private root; a
killed process can leave an inert temporary copy for later manual cleanup.

The Node flags exist in the repository's minimum supported Node 22.19.0;
runtime acceptance here uses Node 24.22.1. This is additional protection for
accidental module-initialization effects, **not a hostile-code sandbox**. See
[the Node 22.19 permission-model contract and limits](https://nodejs.org/download/release/v22.19.0/docs/api/permissions.html).
A deliberately malicious extension or hostile same-UID process remains outside
this protection model. Custom extensions requiring external files, child
processes or native addons during loading are refused instead of being granted
access. Absolute local resource settings requiring the original location are
also refused; the default pinned matrix and relative managed resources remain
supported. Copying CLI/package trees adds temporary disk/copy overhead.

Regression evidence:

- Seven offline regression cases cover actual module evaluation in a small
  explicitly labeled loader test double: writes through HOME, module dirname,
  npm-tree and tmux paths; upgrade failure after CLI replacement; exact original
  bytes and backup bytes after rollback; absolute original-path write denial;
  initializer exceptions/cleanup; overlapping/wildcard TMPDIR; external-module
  refusal. The registered command proves the mutating initializer ran.
- The real matrix uses the same mutating extension with the actual old Pi
  1.0.2 loader. It captures inventories and exact settings/keybinding bytes
  **before the first probe**, then forces an actual upgrade failure, checks the
  original backup bytes and final restored bytes, and repeats real old-loader
  verification. This catches contamination both before backup and after restore.
- Separate scratch-only targeted probes on actual Pi 1.0.2 and 1.4.0 passed;
  the 1.4.0 run also repeated enabled-resource/filter/autoload regressions.
- All test package operations use fresh scratch roots and the independent
  environment guard. No production Pi, configuration, credentials or historical
  backup was read or modified. Evidence stays outside Git under
  `/tmp/pi-probe-snapshot-fix.1Zi6K6/`.

| Final gate (one run each after freeze) | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Offline suite | 78 | 0 | 0 |
| Real version/upgrade/rollback matrix | 25 | 0 | 0 |
| Syntax, generated-source sync, ShellCheck and whitespace groups | 6 | 0 | 0 |
| Real provider conversations / physical tmux forwarding | 0 | 0 | 2 |

Time log: started 2026-10-25 15:10:19 UTC (08:10:19 America/Los_Angeles).
Freeze/final verification: 15:20:48 UTC (08:20:48 America/Los_Angeles), 10m29s after start. Acceptance completed: 15:31:19 UTC (08:31:19 America/Los_Angeles), 21m00s after start. Final verification took 10m31s; inspection, implementation and targeted verification took 10m29s. Documentation was interleaved; local commit and push followed acceptance.
Six targeted batches ran before freeze: one actual 1.0.2 empty probe; offline
4/4 effects regressions; actual 1.0.2 mutating module; offline 6/6 including
path/cleanup cases; actual 1.4.0 filtering plus mutation; wildcard regression
1/1. All passed. No full network matrix was used for iteration.

Final outcome: **READY_FOR_INDEPENDENT_REVIEW**. All critical gates passed.
One full offline suite and one full real matrix ran after freeze with no final
failures or reruns. Supplemental SKIPs remain real provider conversations and
physical tmux forwarding, neither used as proof for this Finding. Evidence:
`final-offline.log`, `final-static.log`, `final-real/results.json`,
`final-real/failed-upgrade.log`, `final-real/classifier-requests.json`.

One local follow-up commit is created only after these checks, and the user
authorized pushing it exclusively to `origin/codex/independent-hardening-review`.
The commit SHA and verified remote result are reported in chat; this report is
inside that commit. No main push, merge, tag, publication or unrelated refactor.
