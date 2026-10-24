# R7 closure report — journal trust boundary (R6)

Baseline: `98b0b0acf39bce06bb96c742e83c40d7bef241a7` on `r3-closure`.
**No version pin changed**: Pi 1.4.0 / permission-modes 2.8.0 @ `cf77816` /
pi-btw 0.62.0 / pi-advisor-flow 0.14.2 / minimal-mode v1.4.0.

This report concerns repository code only. Nothing here claims that the
workstation's production Pi installation is restored or safe to use.

## R6 — root cause

`main()` called `recover_interrupted_run()` **before** `preflight()`, and
recovery read the journal with `. "$JOURNAL"` (bash `source`). Sourcing executes
the file. With an unsupported `AGENT_DIR` (e.g. any `PI_CODING_AGENT_DIR` that
is not `$HOME/.pi/agent`), a journal placed in that directory therefore ran
arbitrary shell code *before* `require_supported_agent_dir()` ever rejected the
directory.

Reproduced against the baseline (`git show 98b0b0a:install.sh`), same script,
two directories, journal containing one plain `touch` line:

```text
=== BASELINE 98b0b0a
A supported-dir journal: EXECUTED (marker created)
B unsupported-dir journal: EXECUTED (marker created) -> R6 reproducible
A exit=0  B exit=0

=== R7 worktree
A supported-dir journal: not executed
B unsupported-dir journal: not executed (R6 closed)
A exit=1  B exit=1
pi-bootstrap: error: …/custom-agent is UNSUPPORTED: … Nothing was changed.
```

(A in that probe used a hand-written journal that is not the current format, so
it is correctly refused rather than recovered; the point of the run is that no
line of either file was executed.)

## R6 — fix

Three independent changes, all in `install.sh`.

**1. The recovery target is admitted before its journal is touched.**
`main()` now runs `require_supported_agent_dir` *first* — before
`materialize_verify_stack`, before `recover_interrupted_run`, before preflight,
the settings check, the Git fetch and any npm work. That check is
side-effect-free (`physical_dir_path` only reads), so recovery for the supported
directory stays local-first: a damaged `settings.json`, an unreachable registry
and no network still cannot block it (see the H2 cases in
`test-rollback.sh`, unchanged and green). `recover_interrupted_run` repeats the
check as defence in depth.

**2. The journal is data, never code.** The `source` line is gone; nothing in
the installer sources or `eval`s the journal. There is a versioned format and a
strict reader (`journal_read`, `journal_read_v1`, `journal_decode`,
`journal_store`, `journal_validate`):

```
pi-bootstrap-journal 1
status=active
phase=activated-cli
agent_dir=/home/user/.pi/agent
global_pi_package=/prefix/lib/node_modules/@earendil-works/pi-coding-agent
global_pi_bin=/prefix/bin/pi
global_npm_prefix=/prefix
global_npm_root=/prefix/lib/node_modules
pid=12345
```

Values are percent-encoded over `A-Za-z0-9` plus `._/:@+,-`; the reader requires
the encoding to be canonical (re-encoding the decoded value must reproduce the
record byte for byte). Rejected: missing header, blank records, records without
`=`, unknown keys, duplicate keys, non-canonical escapes, encoded control bytes
(`%0A`, `%00`, `%7F`, …), raw control characters, NUL bytes anywhere, files over
4096 bytes, missing records, invalid `status`, invalid `phase`, a non-numeric
`pid`, a symlink (or a non-regular file) where the journal should be, and a
journal whose `agent_dir` does not resolve to the directory it was found in.

**3. Restore targets are managed paths, not journal paths.** Two validations,
both before the first destructive step:

* Global locations: the recorded prefix is the only anchor; package, bin and
  root must be exactly its Pi-shaped tails. Recovery then derives its write
  targets from the prefix instead of using the recorded strings, so it can only
  ever touch `<prefix>/bin/pi` and
  `<prefix>/lib/node_modules/@earendil-works/pi-coding-agent`. The prefix must
  also be confirmed on this machine by a local anchor: a matching
  `npm_config_prefix`, a `pi` on `PATH` that resolves into `<prefix>/bin`, or an
  existing Pi entry inside the prefix (`bin/pi` — possibly dangling, which is the
  real post-crash state — or `lib/node_modules/@earendil-works/pi-coding-agent`).
* Backup manifests: every `files.tsv` target must be one of
  `extensions/classifier-model.ts`, `extensions/minimal-mode.ts`,
  `keybindings.json`, `settings.json`, `$TMUX_CONFIG` or `$HOME/.tmux.conf`; every
  stored blob name must be a plain `NNN-name` file name; every `created.list`
  entry must be one of those files or the `npm`/`git` trees. The CLI marker files
  must be regular files. `validate_backup_manifests` runs in
  `restore_from_backup` before any write, in both the trap path and the crash
  path, and an invalid manifest aborts with the manifests untouched.

**Fail closed.** `journal_refuse` is the single refusal path: it reports the
reason, states that nothing was changed or deleted, names the journal and the
backup directory, gives explicit instructions (restore by hand, or move both
aside and re-run), and exits non-zero. A normal installation never continues
while an unparseable transaction is present. The journal and backups are never
deleted by a refusal.

## Journal format and legacy compatibility

| Generation | Written by | Read by | Executed? |
|---|---|---|---|
| v1 (`pi-bootstrap-journal 1`, percent-encoded) | this change | `journal_read_v1` | never |
| legacy (`printf '%q'` assignments, `GLOBAL_PI_*`, R4–R6) | `8f58d91`…`98b0b0a` | `journal_read_legacy` | never |
| legacy pre-R4 (`global_package` / `global_bin`) | `117ebf3`…`93c0fff` | `journal_read_legacy` + prefix derivation | never |

`journal_decode_q` decodes `%q` output character by character (backslash
escapes, `''` for the empty string) and **refuses the `$'...'` form outright** —
no legitimate journal value here needs it, and refusing it keeps the parser
small enough to review. A legacy journal that cannot be decoded safely (e.g.
`agent_dir=$'…'`) is refused, not executed; a test asserts the refusal and that
the journal and backups survive.

Legacy journals that carry no `global_npm_prefix` get one derived from the
recorded package/bin and are validated exactly like a v1 prefix; if the backup
records CLI work and no anchor confirms that prefix, recovery refuses rather
than guessing.

## Regression tests

New: `scripts/tests/test-journal-recovery.sh` (18 PASS, wired into
`scripts/tests/run-all.sh` as *journal trust boundary (R6)*). Every case runs
the real entry point (`bash install.sh`, no `PI_BOOTSTRAP_TEST_ONLY`) in an
isolated `HOME`/agent dir/`TMPDIR`/npm prefix/cache/tmux config, and asserts on
the filesystem (markers, restored bytes, `sha256sum` of journal and backups,
`find` snapshots of directories), never on messages alone.

| # | Requirement | Case | Assertion |
|---|---|---|---|
| 1 | unsupported dir + malicious journal | `unsupported directory` | marker never created, `find`+hash of the directory identical, journal hash unchanged, no recovery message |
| 2 | malformed journal in the supported dir | 7 cases: executable-looking record, unknown key, duplicate key, invalid status, command substitution as a value, control character, symlink journal | run refused, no restore attempted, journal hash and backup tree identical, agent dir identical, no marker |
| 3 | valid journal recovery | `valid recovery` | damaged `settings.json` restored byte for byte, created files removed, journal and backups gone, `npm.log`/`curl.log` empty |
| 4 | journal path tampering | foreign `agent_dir`; crafted package path; `files.tsv` entry; `created.list` entry; unconfirmed prefix | each refused; journal, backups and every outside file byte-identical; the crashed classifier still in place (validation precedes the first write); crafted prefix untouched |
| 5 | legacy compatibility | valid `%q` journal (recovered); pre-R4 package/bin-only journal (recovered); `$'...'` journal, unknown record, duplicate alias (refused, evidence kept, nothing executed) | recovery restores bytes; refusals keep journal and backups |

Run:

```bash
scripts/tests/test-journal-recovery.sh                 # 18 PASS
scripts/tests/test-rollback.sh                         # recovery, SIGKILL matrix, offline cases
scripts/tests/run-all.sh                               # offline suite
PI_BOOTSTRAP_REAL_UPGRADE=1 PI_BOOTSTRAP_ALLOW_NETWORK=1 \
PI_BOOTSTRAP_AGENT_DIR=… PI_BOOTSTRAP_PM_280=… PI_BOOTSTRAP_PI_PACKAGE=… \
  scripts/tests/run-all.sh --fetch                     # real pinned matrix
```

## Verification results

Static gates (this host, `shellcheck` 0.11.0 obtained with `uvx`; the runner
itself reports SKIP when it is not on `PATH`, which is what happened in the
suite logs below):

| Gate | Result |
|---|---|
| `bash -n install.sh`, every `scripts/**/*.sh` | PASS |
| embedded `classifier-model.ts` / `verify-stack.mjs` in sync | PASS |
| version matrix (9 pins agree) | PASS |
| `shellcheck --severity=warning` over installer, scripts, tests, fixtures | PASS, no findings |
| `git diff --check` | PASS |

Offline suite — `scripts/tests/run-all.sh`, frozen code:

```text
summary: 24 passed, 8 skipped, 0 failed
skipped: shellcheck, git install lifecycle isolation (F2), permission gate,
         permission config source (R4-P0), classifier baseUrl regression,
         RPC smoke, default stack load, upgrade and rollback on the real CLI (H1)
```

The 8 SKIPs are the gates whose prerequisites are not present in a bare offline
run (no real Pi package, no `PI_BOOTSTRAP_*` fixtures, no shellcheck on `PATH`);
they all ran in the real-matrix run below.

Real pinned matrix — Pi 1.4.0 from npm, permission-modes 2.8.0 @ `cf77816`
(git tree `4806497…` verified), pi-btw 0.62.0, pi-advisor-flow 0.14.2,
minimal-mode v1.4.0 (SHA256 `040cbc7…`), all in a fresh scratch `HOME`,
`TMPDIR`, npm prefix/cache and agent directory:

```text
summary: 31 passed, 1 skipped, 0 failed
skipped: shellcheck            # not on PATH; run separately above (PASS)
```

This includes the real upgrade/rollback acceptance test (Pi 1.0.2 + the old
matrix from npm, fault injected after the new packages land, rollback proven
by loading every restored extension on the real 1.0.2 loader, then a clean run
that verifies 1.4.0 / 2.8.0 @ `cf77816`), and the unchanged SIGKILL matrix
(5 filesystem boundaries), the six journal-fault cases, and both offline
recovery cases in `test-rollback.sh`.

## Offline recovery evidence

`test-journal-recovery.sh` "valid recovery" and `test-rollback.sh` "offline
recovery" cases both make npm and curl fail while recording every invocation,
point the pinned source at an unreachable path, and damage `settings.json`.
Recovery succeeds, `npm.log`/`curl.log` stay empty, no fetch is attempted, and
the restored `settings.json` is byte-identical to the pre-crash file. The new
format needs no network: the journal carries the prefix, and the restore reads
only local files and moved backups.

## Limitations (stated, not implied)

- The prefix anchor accepts `npm_config_prefix`, a `pi` on `PATH` inside the
  prefix, or an existing Pi entry inside the prefix. A journal for a prefix that
  none of those confirm is refused rather than written to; recovery then needs
  manual action. That is intentional, but it is a fail-closed trade-off.
- A pre-R4 legacy journal (package/bin only) can only be recovered when some
  local anchor confirms the derived prefix.
- The `$'...'` form of `%q` is refused. `printf '%q'` only emits it for control
  characters, which no legitimate value in this journal has.
- A crash *during* the restore itself can still leave a partially restored tree;
  the journal and backups remain and the next run retries. Unchanged from R4.
- The backup manifests are validated but their *content* is trusted: a journal
  and a manifest written by the same compromised user are not distinguishable
  from a real interrupted run. The boundary defended here is "a journal cannot
  execute code and cannot redirect writes outside the managed roots".
- `AGENTS.md` and `backups/` are left exactly as they were found (untracked,
  unstaged).

## Git

* Branch: `r3-closure`; exactly one local commit for this fix, its tests, the
  README update and this report.
* The commit SHA is printed by `git log -1 --format=%H` on `r3-closure` and is
  quoted in the hand-off message. It is deliberately not written in this file:
  a file cannot contain the hash of the commit that contains it.
* Not pushed, not merged, not tagged; `main` untouched; no `git add -A`.
* Worktree after the commit: clean apart from the pre-existing untracked
  `AGENTS.md` and `backups/`, which were left exactly as found and are **not**
  staged.

**Verdict: `READY_FOR_INDEPENDENT_REVIEW`.**
