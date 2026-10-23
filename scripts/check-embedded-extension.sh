#!/usr/bin/env bash
# The installer embeds two source files so that `curl | bash` stays
# self-contained:
#
#   extensions/classifier-model.ts -> heredoc CLASSIFIER_MODEL_EXTENSION (written as the extension)
#   scripts/lib/verify-stack.mjs   -> heredoc VERIFY_STACK_JS_BODY   (run to verify the stack)
#
# This check keeps each pair byte-identical and refuses ambiguous heredocs, so a
# second heredoc with the same delimiter cannot silently change what the
# installer writes. `--write` regenerates the embedded copies from the sources;
# hand editing either copy is never correct.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/install.sh"
mode="${1:-check}"
[[ "$mode" == "check" || "$mode" == "--write" ]] || {
	echo "usage: $0 [--write]" >&2
	exit 2
}

# Line numbers of the opening (`... <<'DELIM'`) and closing (bare DELIM) lines of
# one heredoc, or a diagnostic when the shape is ambiguous.
bounds() {
	local delimiter="$1" kind="$2" open close
	open="$(grep -n "<<'${delimiter}'$" "$installer" | cut -d: -f1 || true)"
	[[ -n "$open" && "$(printf '%s\n' "$open" | wc -l | tr -d ' ')" == 1 ]] || {
		echo "expected exactly one heredoc start for ${delimiter} in install.sh" >&2
		return 1
	}
	close="$(awk -v start="$open" -v delim="$delimiter" 'NR > start && $0 == delim { print NR; exit }' "$installer")"
	[[ -n "$close" ]] || {
		echo "could not find the closing ${delimiter} line in install.sh" >&2
		return 1
	}
	if [[ "$kind" == "open" ]]; then printf '%s\n' "$open"; else printf '%s\n' "$close"; fi
}

extract() {
	local delimiter="$1" open close
	open="$(bounds "$delimiter" open)" || return 1
	close="$(bounds "$delimiter" close)" || return 1
	sed -n "$((open + 1)),$((close - 1))p" "$installer"
}

check_pair() {
	local source_file="$1" delimiter="$2" label="$3" embedded
	embedded="$(mktemp)"
	if ! extract "$delimiter" >"$embedded"; then
		rm -f "$embedded"
		return 1
	fi
	if [[ ! -s "$embedded" ]]; then
		echo "could not extract ${label} from install.sh" >&2
		rm -f "$embedded"
		return 1
	fi
	if ! cmp -s "$source_file" "$embedded"; then
		echo "embedded ${label} differs from ${source_file}" >&2
		diff -u "$source_file" "$embedded" >&2 || true
		rm -f "$embedded"
		return 1
	fi
	rm -f "$embedded"
	echo "embedded ${label} is in sync"
}

# Replace the body of one heredoc with the contents of SOURCE_FILE.
embed() {
	local source_file="$1" delimiter="$2" open close temporary
	open="$(bounds "$delimiter" open)" || return 1
	close="$(bounds "$delimiter" close)" || return 1
	temporary="$(mktemp)"
	{
		# Keep the heredoc opener line itself: it carries the redirection target.
		sed -n "1,${open}p" "$installer"
		cat "$source_file"
		sed -n "${close},\$p" "$installer"
	} >"$temporary"
	mv "$temporary" "$installer"
}

if [[ "$mode" == "--write" ]]; then
	embed "$repo_dir/extensions/classifier-model.ts" "CLASSIFIER_MODEL_EXTENSION"
	embed "$repo_dir/scripts/lib/verify-stack.mjs" "VERIFY_STACK_JS_BODY"
	bash -n "$installer" || {
		echo "--write produced an invalid install.sh" >&2
		exit 1
	}
	echo "re-embedded classifier-model.ts and verify-stack.mjs into install.sh"
fi

status=0
check_pair "$repo_dir/extensions/classifier-model.ts" "CLASSIFIER_MODEL_EXTENSION" "classifier-model.ts" || status=1
check_pair "$repo_dir/scripts/lib/verify-stack.mjs" "VERIFY_STACK_JS_BODY" "verify-stack.mjs" || status=1
exit "$status"
