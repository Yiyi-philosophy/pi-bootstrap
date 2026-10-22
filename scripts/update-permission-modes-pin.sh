#!/usr/bin/env bash
# Regenerate the permission-modes verification pins in install.sh from a
# verified checkout. This is the only supported way to change the manifest, so
# the embedded data is never hand-edited.
#
#   scripts/update-permission-modes-pin.sh <path-to-checkout> [--write]
#
# Without --write it prints the new block and exits non-zero if install.sh
# disagrees, which makes it usable as a CI/PR check.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the test suite can exercise --write against a copy.
installer="${PI_BOOTSTRAP_INSTALLER:-$repo_dir/install.sh}"

checkout="${1:-}"
write="${2:-}"
[[ -n "$checkout" ]] || {
	echo "usage: $0 <permission-modes checkout> [--write]" >&2
	exit 2
}
[[ -d "$checkout/.git" ]] || {
	echo "$checkout is not a git checkout" >&2
	exit 1
}
if ! git -C "$checkout" rev-parse --verify HEAD >/dev/null 2>&1; then
	echo "$checkout has no commits; nothing to pin" >&2
	exit 1
fi

commit="$(git -C "$checkout" rev-parse HEAD)"
tree="$(git -C "$checkout" rev-parse 'HEAD^{tree}')"
status="$(git -C "$checkout" status --porcelain)"
[[ -z "$status" ]] || {
	echo "$checkout has uncommitted changes; verification pins must describe a clean commit" >&2
	exit 1
}

manifest="$(mktemp)"
trap 'rm -f "$manifest"' EXIT
(
	cd "$checkout"
	git ls-files -z | LC_ALL=C sort -z |
		while IFS= read -r -d '' rel; do
			printf '%s  %s\n' "$(sha256sum "$rel" | cut -d' ' -f1)" "$rel"
		done
) >"$manifest"
count="$(wc -l <"$manifest" | tr -d ' ')"
[[ "$count" -gt 0 ]] || {
	echo "refusing to write an empty manifest" >&2
	exit 1
}

if [[ "$write" == "--write" ]]; then
	node - "$installer" "$commit" "$tree" "$count" "$manifest" <<'NODE'
const fs = require("node:fs");
const [file, commit, tree, count, manifestPath] = process.argv.slice(2);
let text = fs.readFileSync(file, "utf8");
const manifest = fs.readFileSync(manifestPath, "utf8").replace(/\n$/, "");

function replaceOnce(pattern, replacement, label) {
	const regex = new RegExp(pattern, "gm");
	const matches = text.match(regex) ?? [];
	if (matches.length !== 1) throw new Error(`expected exactly one match for ${label}, found ${matches.length}`);
	text = text.replace(regex, replacement);
}

replaceOnce('^PERMISSION_MODES_COMMIT="[^"]*"$', `PERMISSION_MODES_COMMIT="${commit}"`, "PERMISSION_MODES_COMMIT");
replaceOnce('^PERMISSION_MODES_TREE="[^"]*"$', `PERMISSION_MODES_TREE="${tree}"`, "PERMISSION_MODES_TREE");
replaceOnce('^PERMISSION_MODES_MANIFEST_COUNT=[0-9]+$', `PERMISSION_MODES_MANIFEST_COUNT=${count}`, "PERMISSION_MODES_MANIFEST_COUNT");
replaceOnce(
	'PERMISSION_MODES_MANIFEST="\\$\\(cat <<\'PM_MANIFEST\'\\n[\\s\\S]*?\\nPM_MANIFEST\\n\\)"',
	`PERMISSION_MODES_MANIFEST="$(cat <<'PM_MANIFEST'\n${manifest}\nPM_MANIFEST\n)"`,
	"PERMISSION_MODES_MANIFEST",
);
fs.writeFileSync(file, text);
NODE
	echo "updated $installer: commit ${commit:0:12}, tree ${tree:0:12}, ${count} files"
	exit 0
fi

# Check mode: compare what install.sh embeds with the checkout.
current_commit="$(sed -n 's/^PERMISSION_MODES_COMMIT="\([^"]*\)"$/\1/p' "$installer")"
current_tree="$(sed -n 's/^PERMISSION_MODES_TREE="\([^"]*\)"$/\1/p' "$installer")"
current_count="$(sed -n 's/^PERMISSION_MODES_MANIFEST_COUNT=\([0-9]*\)$/\1/p' "$installer")"
current_manifest="$(awk '/^PERMISSION_MODES_MANIFEST="\$\(cat <<.PM_MANIFEST.$/ { inside = 1; next } inside && /^PM_MANIFEST$/ { exit } inside { print }' "$installer")"

problems=0
[[ "$current_commit" == "$commit" ]] || {
	echo "commit: install.sh has ${current_commit:-missing}, checkout has $commit" >&2
	problems=$((problems + 1))
}
[[ "$current_tree" == "$tree" ]] || {
	echo "tree: install.sh has ${current_tree:-missing}, checkout has $tree" >&2
	problems=$((problems + 1))
}
[[ "$current_count" == "$count" ]] || {
	echo "count: install.sh has ${current_count:-missing}, checkout has $count" >&2
	problems=$((problems + 1))
}
if [[ "$current_manifest" != "$(cat "$manifest")" ]]; then
	echo "manifest: install.sh differs from the checkout file list" >&2
	diff <(printf '%s\n' "$current_manifest") "$manifest" >&2 || true
	problems=$((problems + 1))
fi

if ((problems > 0)); then
	echo "run '$0 $checkout --write' to update install.sh" >&2
	exit 1
fi
echo "install.sh pins match $checkout (commit ${commit:0:12}, ${count} files)"
