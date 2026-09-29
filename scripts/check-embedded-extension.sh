#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/install.sh"
source_file="$repo_dir/extensions/classifier-model.ts"
embedded="$(mktemp)"
trap 'rm -f "$embedded"' EXIT

awk '
  /cat > .*classifier-model\.ts.*CLASSIFIER_MODEL_EXTENSION/ { inside = 1; next }
  inside && /^CLASSIFIER_MODEL_EXTENSION$/ { exit }
  inside { print }
' "$installer" > "$embedded"

cmp -s "$source_file" "$embedded" || {
  echo "embedded classifier-model.ts differs from extensions/classifier-model.ts" >&2
  exit 1
}

echo "embedded classifier-model.ts is in sync"
