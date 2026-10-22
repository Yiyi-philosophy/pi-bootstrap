#!/usr/bin/env bash
# F2/F3: end-to-end installer behavior on isolated, stubbed infrastructure.
#
# Covers: fresh install, idempotent repeat, upgrade from the 1.0.2-era matrix,
# pre-install source verification (wrong commit / tree / file content), tampered
# checkout detection, and bounded rollback that leaves no partial matrix.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

root="$(new_root)"
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"
install_stubs "$root"

agent="$PI_CODING_AGENT_DIR"
settings="$agent/settings.json"
source_repo="$root/upstream/pi-permission-modes"
mkdir -p "$root/upstream" "$agent/extensions"

fixture_revs=($(make_fixture_repo "$source_repo" "$root/manifest.txt"))
fixture_commit="${fixture_revs[0]}"
fixture_tree="${fixture_revs[1]}"
fixture_manifest="$(cat "$root/manifest.txt")"
fixture_count="$(wc -l <"$root/manifest.txt" | tr -d ' ')"
[[ -n "$fixture_commit" && -n "$fixture_tree" && "$fixture_count" -gt 0 ]] ||
	fail_test "fixture repository setup failed"

# minimal-mode stand-in served by the fake curl.
printf 'export default function minimalMode() {}\n' >"$root/minimal-mode.ts"
minimal_sha="$(sha256sum "$root/minimal-mode.ts" | cut -d' ' -f1)"
export FAKE_CURL_FILE="$root/minimal-mode.ts"

configure_installer() {
	# Point the pinned constants at the local fixture repository.
	PERMISSION_MODES_COMMIT="$fixture_commit"
	PERMISSION_MODES_TREE="$fixture_tree"
	PERMISSION_MODES_REPO="$source_repo"
	PERMISSION_MODES_SOURCE="git:github.com/GeorgeDing32/pi-permission-modes-fixture@${fixture_commit}"
	PERMISSION_MODES_PATH="GeorgeDing32/pi-permission-modes-fixture"
	PERMISSION_MODES_DIR="$agent/git/github.com/$PERMISSION_MODES_PATH"
	PERMISSION_MODES_MANIFEST="$fixture_manifest"
	PERMISSION_MODES_MANIFEST_COUNT="$fixture_count"
	MINIMAL_MODE_SHA256="$minimal_sha"
	export FAKE_PI_CLONE_DIR="$source_repo"
}

# Load the installer once in this shell so tests can read the pinned constants;
# run main() in a subshell so a fatal exit() cannot end the test run.
load_installer
configure_installer

run_installer() {
	( main ) >"$root/install.log" 2>&1
}

# --- 1. Fresh install -------------------------------------------------------
run_installer || fail_test "fresh install failed: $(tail -20 "$root/install.log")"
assert_eq "3" "$(package_count "$settings")" "three managed packages recorded"
sources="$(package_sources "$settings")"
assert_contains "$sources" "$PERMISSION_MODES_SOURCE" "permission-modes pinned source recorded"
assert_contains "$(cat "$root/install.log")" "Pre-install verification passed" "pre-install verification ran"
assert_contains "$(cat "$root/install.log")" "SHA256-verified; not an npm release" "source-built labeling"
assert_eq "$minimal_sha" "$(sha256sum "$agent/extensions/minimal-mode.ts" | cut -d' ' -f1)" "minimal-mode installed from verified bytes"
[[ -f "$agent/extensions/classifier-model.ts" ]] || fail_test "classifier extension not installed"
keybinding="$(node -e 'process.stdout.write(JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8"))["app.thinking.cycle"])' "$agent/keybindings.json")"
assert_eq "ctrl+shift+tab" "$keybinding" "keybinding merged"
pass "fresh install: pinned matrix, verified source, classifier and minimal-mode installed"

# npm must be called with --ignore-scripts for the Pi install, and the
# dependency install must inherit ignore-scripts for lifecycle scripts.
assert_contains "$(cat "$FAKE_NPM_LOG")" "--ignore-scripts" "Pi installed with --ignore-scripts"
grep -qx 'install npm:@narumitw/pi-btw@0.62.0' "$FAKE_PI_LOG" || fail_test "pi-btw not installed"
pass "installer uses --ignore-scripts and installs the pinned npm sources"

# --- 2. Repeat run is idempotent -------------------------------------------
cp "$settings" "$root/after-first.json"
cp "$agent/extensions/minimal-mode.ts" "$root/minimal-first.ts"
: >"$FAKE_PI_LOG"
run_installer || fail_test "repeat install failed: $(tail -20 "$root/install.log")"
cmp -s "$root/after-first.json" "$settings" || fail_test "repeat install changed settings.json"
cmp -s "$root/minimal-first.ts" "$agent/extensions/minimal-mode.ts" || fail_test "repeat install changed minimal-mode.ts"
assert_eq "0" "$(grep -c '^remove ' "$FAKE_PI_LOG" || true)" "repeat install removed nothing"
pass "repeat install: identical settings, no removals, no churn"

# --- 3. Upgrade from the 1.0.2-era matrix ----------------------------------
cat >"$settings" <<'JSON'
{
  "theme": "dark",
  "packages": [
    "npm:@georgedong32/permission-modes@2.7.0",
    "npm:@narumitw/pi-btw@0.61.1",
    "npm:pi-advisor-flow@0.11.0",
    "npm:user-extension@2.1.0"
  ]
}
JSON
rm -rf "$agent/git" "$agent/npm"
run_installer || fail_test "upgrade install failed: $(tail -20 "$root/install.log")"
assert_eq "4" "$(package_count "$settings")" "three managed packages plus the user extension"
sources="$(package_sources "$settings")"
assert_not_contains "$sources" "2.7.0" "old permission-modes entry gone"
assert_not_contains "$sources" "0.61.1" "old pi-btw entry gone"
assert_not_contains "$sources" "0.11.0" "old advisor entry gone"
assert_contains "$sources" "npm:user-extension@2.1.0" "unrelated package preserved"
assert_contains "$sources" "$PERMISSION_MODES_SOURCE" "new pinned source present"
theme="$(node -e 'process.stdout.write(JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8")).theme)' "$settings")"
assert_eq "dark" "$theme" "unrelated setting preserved"
pass "upgrade: 1.0.2 matrix replaced, unrelated package and settings kept"

# --- 4. Pre-install verification rejects a wrong commit --------------------
cat >"$settings" <<'JSON'
{ "packages": [] }
JSON
rm -rf "$agent/git"
: >"$FAKE_PI_LOG"
if (PERMISSION_MODES_COMMIT="1111111111111111111111111111111111111111"; PERMISSION_MODES_SOURCE="git:github.com/GeorgeDing32/pi-permission-modes-fixture@1111111111111111111111111111111111111111"; main) >"$root/badcommit.log" 2>&1; then
	fail_test "installer accepted an unresolvable pinned commit"
fi
assert_contains "$(cat "$root/badcommit.log")" "could not fetch" "fetch failure reported"
assert_eq "0" "$(grep -c '^install ' "$FAKE_PI_LOG" || true)" "no package installed after a failed pre-check"
assert_eq "0" "$(package_count "$settings")" "settings untouched after pre-install failure"
pass "wrong commit: rejected before any package install"

# --- 5. Pre-install verification rejects a tampered tree ------------------
cp -a "$source_repo" "$root/tampered"
printf 'malicious()\n' >>"$root/tampered/index.ts"
git -C "$root/tampered" -c user.email=t@example.invalid -c user.name=t commit -qam tamper
tampered_commit="$(git -C "$root/tampered" rev-parse HEAD)"
rm -rf "$agent/git"
: >"$FAKE_PI_LOG"
if (PERMISSION_MODES_REPO="$root/tampered"; PERMISSION_MODES_COMMIT="$tampered_commit"; main) >"$root/tampered.log" 2>&1; then
	fail_test "installer accepted a commit whose tree differs from the pin"
fi
assert_contains "$(cat "$root/tampered.log")" "does not match the pinned tree" "tree mismatch reported"
assert_eq "0" "$(package_count "$settings")" "settings untouched after a tree mismatch"
pass "tampered commit: tree hash mismatch rejected before install"

# --- 6. Post-install tamper detection (a file changed in the checkout) ----
run_installer >/dev/null 2>&1 || fail_test "baseline install failed"
printf 'tampered\n' >>"$PERMISSION_MODES_DIR/index.ts"
if (verify_permission_modes "$PERMISSION_MODES_DIR") >"$root/tamper-check.log" 2>&1; then
	fail_test "verification accepted a modified checkout"
fi
assert_contains "$(cat "$root/tamper-check.log")" "local modifications" "modified checkout detected"
git -C "$PERMISSION_MODES_DIR" checkout -- index.ts
(verify_permission_modes "$PERMISSION_MODES_DIR" ) >/dev/null 2>&1 ||
	fail_test "verification failed after restoring the file"
pass "post-install verification: detects and then re-accepts a restored checkout"

# --- 7. A missing manifest file is reported -------------------------------
rm -f "$PERMISSION_MODES_DIR/sub/helper.ts"
if (verify_permission_modes "$PERMISSION_MODES_DIR") >"$root/missing.log" 2>&1; then
	fail_test "verification accepted a missing file"
fi
assert_contains "$(cat "$root/missing.log")" "sub/helper.ts" "missing file named"
git -C "$PERMISSION_MODES_DIR" checkout -- sub/helper.ts
pass "verification: names the missing file"

# --- 8. Failure after mutation rolls back to the previous activation -----
cat >"$settings" <<'JSON'
{
  "theme": "dark",
  "packages": ["npm:@narumitw/pi-btw@0.61.1", "npm:user-extension@2.1.0"]
}
JSON
cp "$settings" "$root/pre-rollback.json"
cp "$agent/extensions/minimal-mode.ts" "$root/pre-rollback-minimal.ts"
rm -rf "$agent/git" "$agent/npm"
if FAKE_CURL_FAIL=1 run_installer; then
	fail_test "installer succeeded although the minimal-mode download failed"
fi
assert_contains "$(cat "$root/install.log")" "rolling back" "rollback announced"
cmp -s "$root/pre-rollback.json" "$settings" || fail_test "rollback did not restore settings.json: $(cat "$settings")"
cmp -s "$root/pre-rollback-minimal.ts" "$agent/extensions/minimal-mode.ts" || fail_test "rollback did not restore minimal-mode.ts"
sources="$(package_sources "$settings")"
assert_contains "$sources" "0.61.1" "previous activation restored (old pi-btw back in settings)"
pass "late failure: settings and extensions restored, no partial matrix active"

# --- 9. The restored settings still describe a usable state --------------
run_installer || fail_test "recovery install failed: $(tail -20 "$root/install.log")"
assert_eq "4" "$(package_count "$settings")" "recovery run converges on the pinned matrix plus the preserved user package"
assert_contains "$(package_sources "$settings")" "npm:user-extension@2.1.0" "user package survives the rollback and re-run"
pass "post-rollback re-run converges on the pinned matrix"

# --- 10. No install runs when settings are malformed ---------------------
printf '{broken' >"$settings"
cp "$settings" "$root/broken.json"
if run_installer; then
	fail_test "installer proceeded with malformed settings.json"
fi
assert_contains "$(cat "$root/install.log")" "is not valid JSON" "malformed settings reported"
cmp -s "$root/broken.json" "$settings" || fail_test "malformed settings were rewritten"
pass "malformed settings: preflight refuses before any package change"

echo "install-run tests passed"
