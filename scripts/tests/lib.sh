#!/usr/bin/env bash
# Shared helpers for the pi-bootstrap test suite.
#
# Every test runs in an isolated HOME with stubbed external commands. Nothing
# here reads or writes the developer's real ~/.pi, and no test needs a
# credential: fixtures use empty or absent auth.json files and loopback mock
# servers only.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tests_dir="$repo_dir/scripts/tests"
fixtures_dir="$tests_dir/fixtures"

# Create a scratch root: bin/ (stubs), home/ (isolated HOME), work/ (cwd).
new_root() {
	local root
	root="$(mktemp -d "${TMPDIR:-/tmp}/pi-bootstrap-test.XXXXXX")"
	mkdir -p "$root/bin" "$root/home" "$root/work" "$root/npm-prefix" "$root/npm-cache"
	printf '%s\n' "$root"
}

# Refuse to run anything that writes with the developer's real HOME. This is the
# last-resort guard against the failure mode M2 describes: a test handed the
# user's real agent directory must stop, not "just write there".
#
# The rule is deliberately about identity, not location: HOME must not be the
# account's real home (or a parent of it), and PI_CODING_AGENT_DIR must be
# inside HOME. A scratch HOME anywhere is accepted, so CI and power users can
# put it wherever they like.
real_home() {
	local entry
	entry="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
	[[ -n "$entry" ]] || entry="${HOME_FALLBACK:-}"
	printf '%s\n' "${entry%/}"
}

# Print the physical path of DIR: symlinks resolved for the part that exists,
# the rest appended lexically. A symlink to the real home therefore resolves to
# the real home and is caught by the guards below instead of passing a textual
# "it is under TMPDIR" check.
physical_path() {
	local target="$1" suffix=""
	target="${target%/}"
	[[ -n "$target" ]] || target="/"
	while [[ ! -e "$target" && "$target" != "/" ]]; do
		suffix="/$(basename "$target")$suffix"
		target="$(dirname "$target")"
	done
	printf '%s%s\n' "$(cd -P "$target" 2>/dev/null && pwd)" "$suffix"
}

require_scratch_home() {
	local home="${HOME:-}" real home_physical
	[[ -n "$home" ]] || fail_test "HOME is not set"
	case "$home" in
		/*) ;;
		*) fail_test "refusing to run with a relative HOME: $home" ;;
	esac
	home="${home%/}"
	real="$(real_home)"
	real="$(physical_path "$real")"
	home_physical="$(physical_path "$home")"
	if [[ -n "$real" ]]; then
		# Both spellings are checked: a lexical match catches a plain path, and
		# the physical one catches `HOME=/tmp/x` where /tmp/x is a symlink to the
		# real home (or to a directory containing it).
		for candidate in "$home" "$home_physical"; do
			case "$real" in
				"$candidate" | "$candidate"/*)
					fail_test "refusing to run with HOME=$home (resolves to $home_physical): it is (or contains) the real home $real; this suite writes Pi configuration"
					;;
			esac
		done
	fi
	case "$home" in
		/ | /root) fail_test "refusing to run with HOME=$home" ;;
	esac
	if [[ -n "${PI_CODING_AGENT_DIR:-}" ]]; then
		local agent agent_physical
		agent="${PI_CODING_AGENT_DIR%/}"
		case "$agent" in
			/*) ;;
			*) agent="$PWD/$agent" ;;
		esac
		agent_physical="$(physical_path "$agent")"
		for candidate in "$agent" "$agent_physical"; do
			case "$candidate" in
				"$home" | "$home"/* | "$home_physical" | "$home_physical"/*) ;;
				*) fail_test "refusing to run: PI_CODING_AGENT_DIR=$agent (resolves to $agent_physical) is outside HOME=$home (resolves to $home_physical)" ;;
			esac
		done
	fi
}

# export_isolated_env ROOT -- point everything the installer and Pi honor at ROOT.
export_isolated_env() {
	local root="$1"
	HOME="$root/home"
	require_scratch_home
	export HOME="$root/home"
	export PI_CODING_AGENT_DIR="$root/home/.pi/agent"
	unset PI_AGENT_DIR PI_BOOTSTRAP_SOURCE_DIR PI_BIN TMUX || true
	export TMUX_CONFIG_FILE="$root/home/.tmux.conf"
	export npm_config_prefix="$root/npm-prefix"
	export npm_config_cache="$root/npm-cache"
	export FAKE_NPM_LOG="$root/npm.log"
	export FAKE_PI_LOG="$root/pi.log"
	export FAKE_PI_JS="$fixtures_dir/fake-pi.js"
	export PATH="$root/bin:$PATH"
	mkdir -p "$PI_CODING_AGENT_DIR"
	: >"$FAKE_NPM_LOG"
	: >"$FAKE_PI_LOG"
}

fail_test() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

pass() {
	printf 'PASS: %s\n' "$*"
}

assert_eq() {
	local expected="$1" actual="$2" label="${3:-value}"
	[[ "$expected" == "$actual" ]] || fail_test "$label: expected [$expected], got [$actual]"
}

assert_contains() {
	local haystack="$1" needle="$2" label="${3:-output}"
	case "$haystack" in
		*"$needle"*) ;;
		*) fail_test "$label: expected to contain [$needle]; got [$haystack]" ;;
	esac
}

assert_not_contains() {
	local haystack="$1" needle="$2" label="${3:-output}"
	case "$haystack" in
		*"$needle"*) fail_test "$label: expected NOT to contain [$needle]; got [$haystack]" ;;
		*) ;;
	esac
}

# Source the installer's functions without running main().
load_installer() {
	PI_BOOTSTRAP_TEST_ONLY=1 source "$repo_dir/install.sh"
}

# Install a shell fixture stub under a different command name. The copy keeps
# the fixture directory baked in, so moving it out of the way is safe.
put_stub_as() {
	local root="$1" fixture="$2" name="$3"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'PI_BOOTSTRAP_FIXTURES=%q\n' "$fixtures_dir"
		printf 'export PI_BOOTSTRAP_FIXTURES\n'
		tail -n +2 "$fixtures_dir/$fixture.sh"
	} >"$root/bin/$name"
	chmod +x "$root/bin/$name"
}

# put_stub ROOT NAME -- install fixtures/<NAME>.sh as ROOT/bin/<NAME>.
put_stub() {
	local root="$1" name="$2"
	local target="${3:-$name}"
	put_stub_as "$root" "$name" "$target"
}

# Install the fake `pi`, `npm`, `curl`, and `tmux` used by installer tests.
install_stubs() {
	local root="$1"
	{
		printf '#!/usr/bin/env bash\nset -euo pipefail\n'
		printf 'exec node %q "$@"\n' "$fixtures_dir/fake-pi.js"
	} >"$root/bin/pi"
	chmod +x "$root/bin/pi"
	put_stub "$root" fake-npm npm
	put_stub "$root" fake-curl curl
	put_stub "$root" fake-tmux tmux
}

# Create a small git repository to stand in for the pinned upstream source.
# Prints the commit, then the tree hash, and writes the manifest to $2.
make_fixture_repo() {
	local dir="$1" manifest_out="$2" version="${3:-1.0.0}"
	mkdir -p "$dir/sub"
	printf 'export const index = 1;\n' >"$dir/index.ts"
	printf 'export const helper = 2;\n' >"$dir/sub/helper.ts"
	printf '{"name":"fixture-package","version":"%s"}\n' "$version" >"$dir/package.json"
	git -C "$dir" init --quiet
	git -C "$dir" -c user.email=test@example.invalid -c user.name=test add -A
	git -C "$dir" -c user.email=test@example.invalid -c user.name=test commit --quiet -m fixture
	manifest_of "$dir" >"$manifest_out"
	git -C "$dir" rev-parse HEAD
	git -C "$dir" rev-parse 'HEAD^{tree}'
}

# Print "<sha256>  <relative path>" lines for a git directory, sorted by path.
manifest_of() {
	local dir="$1" rel
	(
		cd "$dir"
		git ls-files -z | LC_ALL=C sort -z |
			while IFS= read -r -d '' rel; do
				printf '%s  %s\n' "$(sha256sum "$rel" | cut -d' ' -f1)" "$rel"
			done
	)
}

# Print the `packages` array of settings.json as one source string per line.
package_sources() {
	local file="$1"
	node - "$file" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
if (!fs.existsSync(file)) process.exit(0);
const config = JSON.parse(fs.readFileSync(file, "utf8"));
for (const entry of config.packages ?? []) {
	console.log(typeof entry === "string" ? entry : JSON.stringify(entry));
}
NODE
}

# Count package entries in settings.json.
package_count() {
	local file="$1"
	node - "$file" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
if (!fs.existsSync(file)) { console.log(0); process.exit(0); }
const config = JSON.parse(fs.readFileSync(file, "utf8"));
console.log(Array.isArray(config.packages) ? config.packages.length : 0);
NODE
}
