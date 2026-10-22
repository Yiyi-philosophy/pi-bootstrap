#!/usr/bin/env bash
# F1: stale-package detection and removal must be identity-exact.
#
# Covers: string and object entries, npm -> git transition, version bumps,
# unrelated/custom packages, non-managed look-alikes, ambiguous or malformed
# settings (fail closed, no writes), and `pi remove` failure being fatal.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

root="$(new_root)"
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"
put_stub "$root" fake-pi pi
export PI_BIN="$root/bin/pi"

settings="$PI_CODING_AGENT_DIR/settings.json"
mkdir -p "$PI_CODING_AGENT_DIR"
load_installer

write_settings() {
	cat >"$settings"
}

# --- 1. Baseline upgrade: 1.0.2-era entries, version bumps, npm -> git --------
write_settings <<'JSON'
{
  "theme": "dark",
  "defaultProvider": "user-provider",
  "packages": [
    "npm:@georgedong32/permission-modes@2.7.0",
    "npm:@narumitw/pi-btw@0.61.1",
    "npm:pi-advisor-flow@0.11.0",
    "npm:left-pad@1.3.0",
    "/home/user/my-local-extension",
    "npm:@example/pi-permission-modes-helper@2.0.0"
  ]
}
JSON

migrate_managed_packages >"$root/migrate.log" 2>&1 || fail_test "migration failed: $(cat "$root/migrate.log")"

sources="$(package_sources "$settings" | sort | tr '\n' '|')"
assert_contains "$sources" "npm:left-pad@1.3.0" "unrelated npm package kept"
assert_contains "$sources" "/home/user/my-local-extension" "local package kept"
assert_contains "$sources" "npm:@example/pi-permission-modes-helper@2.0.0" "name look-alike kept"
assert_not_contains "$sources" "2.7.0" "old permission-modes removed"
assert_not_contains "$sources" "0.61.1" "old pi-btw removed"
assert_not_contains "$sources" "0.11.0" "old advisor removed"
assert_eq "3" "$(package_count "$settings")" "entry count after migration"

theme="$(node -e 'process.stdout.write(JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8")).theme)' "$settings")"
assert_eq "dark" "$theme" "unrelated settings preserved"
pass "string entries: managed versions removed, unrelated and look-alike packages kept"

# --- 2. Object entries: removable when only the source key is present --------
write_settings <<'JSON'
{
  "packages": [
    { "source": "npm:@narumitw/pi-btw@0.61.1" },
    { "source": "npm:pi-advisor-flow@0.11.0", "skills": [] }
  ]
}
JSON
out="$(migrate_managed_packages 2>&1)" && fail_test "filtered object entry must fail closed"
assert_contains "$out" "extra keys" "conflict explains the filtered entry"
assert_contains "$out" "refusing to modify" "conflict fails closed"
sources="$(package_sources "$settings")"
assert_contains "$sources" "0.61.1" "failing closed leaves settings untouched"
pass "object entries with resource filters: conflict reported, nothing changed"

# --- 3. Object entry without extra keys is removed ---------------------------
write_settings <<'JSON'
{ "packages": [ { "source": "npm:@narumitw/pi-btw@0.61.1" }, "npm:unrelated@1.0.0" ] }
JSON
migrate_managed_packages >/dev/null || fail_test "plain object entry should be removable"
assert_eq "1" "$(package_count "$settings")" "only the unrelated entry remains"
assert_eq "npm:unrelated@1.0.0" "$(package_sources "$settings")" "kept entry is the unrelated one"
pass "object entry without filters: removed cleanly"

# --- 4. git -> git ref change is recognized as the same package -------------
write_settings <<'JSON'
{
  "packages": [
    "git:github.com/GeorgeDong32/pi-permission-modes@deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  ]
}
JSON
migrate_managed_packages >/dev/null || fail_test "git ref change should be removable"
assert_eq "0" "$(package_count "$settings")" "old pinned commit removed"
pass "git entries: stale pinned commit removed (identity ignores the ref)"

# --- 5. Desired state is a no-op --------------------------------------------
write_settings <<JSON
{
  "packages": [
    "$PI_BTW_SOURCE",
    "$PI_ADVISOR_FLOW_SOURCE",
    "$PERMISSION_MODES_SOURCE"
  ]
}
JSON
cp "$settings" "$root/before.json"
: >"$FAKE_PI_LOG"
migrate_managed_packages >"$root/noop.log" 2>&1 || fail_test "no-op migration failed: $(cat "$root/noop.log")"
cmp -s "$root/before.json" "$settings" || fail_test "no-op migration rewrote settings.json"
assert_eq "" "$(cat "$FAKE_PI_LOG")" "no pi remove was invoked"
pass "already-current settings: no removals, file untouched"

# --- 6. Malformed settings fail closed --------------------------------------
: >"$FAKE_PI_LOG"
for invalid in '{broken' '[]' 'null' '{"packages": "npm:x@1.0.0"}' '{"packages": [null]}' '{"packages": [{"filters": []}]}'; do
	printf '%s' "$invalid" >"$settings"
	cp "$settings" "$root/before.json"
	# A subshell keeps the installer's fatal exit() from ending this test.
	if (migrate_managed_packages) >"$root/invalid.log" 2>&1; then
		fail_test "malformed settings accepted: $invalid"
	fi
	cmp -s "$root/before.json" "$settings" || fail_test "malformed settings were rewritten: $invalid"
done
assert_eq "" "$(cat "$FAKE_PI_LOG")" "no pi remove ran for malformed settings"
pass "malformed or ambiguous settings: explicit error, fail closed, file untouched"

# --- 7. Missing settings file is fine ---------------------------------------
rm -f "$settings"
migrate_managed_packages >/dev/null || fail_test "missing settings.json must not fail"
pass "missing settings.json: nothing to migrate"

# --- 8. `pi remove` failure is fatal, never swallowed -----------------------
write_settings <<'JSON'
{ "packages": ["npm:@narumitw/pi-btw@0.61.1"] }
JSON
cp "$settings" "$root/before.json"
if (FAKE_PI_FAIL_REMOVE=1 migrate_managed_packages) >"$root/remove-fail.log" 2>&1; then
	fail_test "pi remove failure was ignored"
fi
assert_contains "$(cat "$root/remove-fail.log")" "pi remove failed" "failure is reported"
cmp -s "$root/before.json" "$settings" || fail_test "failed removal rewrote settings.json"
pass "pi remove failure: fatal, reported, settings unchanged"

# --- 9. A "successful" remove that changes nothing is caught --------------
write_settings <<'JSON'
{ "packages": ["npm:@narumitw/pi-btw@0.61.1"] }
JSON
if (FAKE_PI_REMOVE_NOOP=1 migrate_managed_packages) >"$root/noop-remove.log" 2>&1; then
	fail_test "a remove that changed nothing was reported as success"
fi
assert_contains "$(cat "$root/noop-remove.log")" "still stale after removal" "post-removal verification names the entry"
assert_contains "$(package_sources "$settings")" "0.61.1" "settings untouched by the no-op"
pass "remove that silently does nothing: detected by the post-removal check"

# --- 10. verify mode reports a missing or stale matrix ---------------------
write_settings <<'JSON'
{ "packages": ["npm:@narumitw/pi-btw@0.62.0"] }
JSON
if (check_settings verify) >"$root/verify.log" 2>&1; then
	fail_test "verify accepted an incomplete matrix"
fi
assert_contains "$(cat "$root/verify.log")" "missing or stale" "verify names the problem"
write_settings <<JSON
{ "packages": ["$PI_BTW_SOURCE", "$PI_ADVISOR_FLOW_SOURCE", "$PERMISSION_MODES_SOURCE"] }
JSON
check_settings verify >"$root/verify-ok.log" 2>&1 || fail_test "verify rejected a complete matrix: $(cat "$root/verify-ok.log")"
pass "verify mode: detects an incomplete matrix and accepts the pinned one"

echo "install-settings tests passed"
