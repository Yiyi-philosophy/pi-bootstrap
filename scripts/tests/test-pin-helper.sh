#!/usr/bin/env bash
# The permission-modes verification pins must be generated, never hand-edited.
#
# Exercises scripts/update-permission-modes-pin.sh against a throwaway copy of
# install.sh: a stale pin is detected, --write updates commit, tree, count, and
# the file list together, the result is accepted, and a dirty checkout is
# refused (the pins may only describe a clean commit).
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

root="$(new_root)"
trap 'rm -rf "$root"' EXIT
export_isolated_env "$root"

helper="$repo_dir/scripts/update-permission-modes-pin.sh"
installer="$root/install.sh"
cp "$repo_dir/install.sh" "$installer"
export PI_BOOTSTRAP_INSTALLER="$installer"

source_repo="$root/source"
mkdir -p "$source_repo"
make_fixture_repo "$source_repo" "$root/manifest.txt" >/dev/null
# A second commit so the fixture has a history to pin away from.
printf 'export const extra = 3;\n' >"$source_repo/extra.ts"
git -C "$source_repo" -c user.email=test@example.invalid -c user.name=test add -A
git -C "$source_repo" -c user.email=test@example.invalid -c user.name=test commit --quiet -m extra
expected_commit="$(git -C "$source_repo" rev-parse HEAD)"
expected_tree="$(git -C "$source_repo" rev-parse 'HEAD^{tree}')"
expected_count="$(git -C "$source_repo" ls-files | wc -l | tr -d ' ')"

# 1. The real pins do not describe this fixture, so check mode must fail.
if "$helper" "$source_repo" >"$root/check1.log" 2>&1; then
	fail_test "check mode accepted a checkout that does not match the pins"
fi
assert_contains "$(cat "$root/check1.log")" "commit:" "commit mismatch reported"
assert_contains "$(cat "$root/check1.log")" "--write" "remedy suggested"
pass "check mode: reports every mismatch against a foreign checkout"

# 2. --write rewrites commit, tree, count, and the file list together.
"$helper" "$source_repo" --write >"$root/write.log" 2>&1 || fail_test "--write failed: $(cat "$root/write.log")"
assert_eq "$expected_commit" "$(sed -n 's/^PERMISSION_MODES_COMMIT="\([^"]*\)"$/\1/p' "$installer")" "commit rewritten"
assert_eq "$expected_tree" "$(sed -n 's/^PERMISSION_MODES_TREE="\([^"]*\)"$/\1/p' "$installer")" "tree rewritten"
assert_eq "$expected_count" "$(sed -n 's/^PERMISSION_MODES_MANIFEST_COUNT=\([0-9]*\)$/\1/p' "$installer")" "count rewritten"
bash -n "$installer" || fail_test "--write produced a file with invalid syntax"
manifest_lines="$(awk '
	/^PERMISSION_MODES_MANIFEST="\$\(cat <<.PM_MANIFEST./ { inside = 1; next }
	inside && /^PM_MANIFEST$/ { exit }
	inside { print }
' "$installer" | grep -c '^[0-9a-f]\{64\}  ' || true)"
assert_eq "$expected_count" "$manifest_lines" "manifest line count matches the checkout"
pass "--write: commit, tree, count, and file list updated atomically"

# 3. Check mode now accepts the same checkout.
"$helper" "$source_repo" >"$root/check2.log" 2>&1 || fail_test "check mode rejected the freshly written pins: $(cat "$root/check2.log")"
assert_contains "$(cat "$root/check2.log")" "pins match" "success message"
pass "check mode: accepts the pins it just wrote"

# 4. A modified tracked file makes the checkout dirty, so the pins -- which
# describe a commit -- cannot be recomputed from it. Both modes refuse.
printf 'tampered\n' >>"$source_repo/extra.ts"
if "$helper" "$source_repo" >"$root/check3.log" 2>&1; then
	fail_test "check mode accepted a checkout with a modified file"
fi
assert_contains "$(cat "$root/check3.log")" "uncommitted changes" "modified file reported"
if "$helper" "$source_repo" --write >"$root/write-tampered.log" 2>&1; then
	fail_test "--write accepted a checkout with a modified file"
fi
assert_eq "$expected_commit" "$(sed -n 's/^PERMISSION_MODES_COMMIT="\([^"]*\)"$/\1/p' "$installer")" "refused write left the pins alone"
git -C "$source_repo" checkout -- extra.ts
pass "modified tracked file: both modes refuse rather than pinning a dirty tree"

# 5. A dirty checkout is refused outright: pins may only describe a commit.
printf 'uncommitted\n' >"$source_repo/dirty.ts"
if "$helper" "$source_repo" --write >"$root/dirty.log" 2>&1; then
	fail_test "--write accepted a dirty checkout"
fi
assert_contains "$(cat "$root/dirty.log")" "uncommitted changes" "dirty checkout refused"
rm -f "$source_repo/dirty.ts"
pass "--write: refuses a checkout with uncommitted changes"

# 6. An empty checkout cannot erase the manifest.
empty="$root/empty"
mkdir -p "$empty"
git -C "$empty" init --quiet
if "$helper" "$empty" --write >"$root/empty.log" 2>&1; then
	fail_test "--write accepted an empty checkout"
fi
assert_contains "$(cat "$root/empty.log")" "no commits" "empty checkout refused"
bash -n "$installer" || fail_test "refusal left install.sh broken"
pass "--write: refuses to write an empty manifest"

# 7. An interrupted/failing write never damages install.sh (M5). A successful
#    result is byte-identical to what the helper produced before, temp files are
#    cleaned up, and the file keeps its mode.
cp "$installer" "$root/install.before"
mode_before="$(stat -c '%a' "$installer")"
if ! "$helper" "$source_repo" --write >"$root/write2.log" 2>&1; then
	fail_test "second --write failed: $(cat "$root/write2.log")"
fi
cmp -s "$root/install.before" "$installer" || fail_test "a repeat --write was not byte-identical"
assert_eq "$mode_before" "$(stat -c '%a' "$installer")" "install.sh keeps its mode"
leftovers="$(find "$(dirname "$installer")" -maxdepth 1 -name '.install.sh.pin.*' | wc -l | tr -d ' ')"
assert_eq "0" "$leftovers" "no temporary candidate files remain"
pass "--write: repeat run is byte-identical, mode preserved, no temp files left"

# 8. A writer that fails midway leaves the original untouched.
cp "$installer" "$root/install.before"
cat >"$root/failing-node" <<'NODE'
#!/usr/bin/env bash
# Copy a partial file into the candidate, then fail: exactly the "interrupted
# write" shape the atomic rename must protect against.
for last; do :; done
printf 'half written\n' >"$last"
echo "simulated interruption" >&2
exit 1
NODE
chmod +x "$root/failing-node"
if PI_BOOTSTRAP_PIN_NODE="$root/failing-node" PI_BOOTSTRAP_INSTALLER="$installer" \
	"$helper" "$source_repo" --write >"$root/interrupted.log" 2>&1; then
	fail_test "--write succeeded although the writer failed"
fi
cmp -s "$root/install.before" "$installer" || fail_test "a failed write modified install.sh"
leftovers="$(find "$(dirname "$installer")" -maxdepth 1 -name '.install.sh.pin.*' | wc -l | tr -d ' ')"
assert_eq "0" "$leftovers" "a failed write leaves no temporary candidate file"
bash -n "$installer" || fail_test "install.sh is broken after a failed write"
pass "--write: a failing writer leaves install.sh byte-identical and no temp files"

echo "pin helper tests passed"
