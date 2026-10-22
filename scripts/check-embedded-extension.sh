#!/usr/bin/env bash
# The installer embeds extensions/classifier-model.ts so that `curl | bash`
# stays self-contained. This check keeps the two copies byte-identical.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/install.sh"
source_file="$repo_dir/extensions/classifier-model.ts"
embedded="$(mktemp)"
trap 'rm -f "$embedded"' EXIT

awk '
  /classifier-model\.ts.*<<.CLASSIFIER_MODEL_EXTENSION./ { inside = 1; next }
  inside && /^CLASSIFIER_MODEL_EXTENSION$/ { exit }
  inside { print }
' "$installer" >"$embedded"

if [[ ! -s "$embedded" ]]; then
	echo "could not extract the embedded classifier-model.ts from install.sh" >&2
	exit 1
fi

cmp -s "$source_file" "$embedded" || {
	echo "embedded classifier-model.ts differs from extensions/classifier-model.ts" >&2
	diff -u "$source_file" "$embedded" >&2 || true
	exit 1
}

# The extension must stay a single, unmodified heredoc body: a second heredoc
# with the same delimiter would silently change what the installer writes.
delimiters="$(grep -c "^CLASSIFIER_MODEL_EXTENSION$" "$installer" || true)"
[[ "$delimiters" == 1 ]] || {
	echo "expected exactly one CLASSIFIER_MODEL_EXTENSION delimiter in install.sh; found $delimiters" >&2
	exit 1
}

echo "embedded classifier-model.ts is in sync"
