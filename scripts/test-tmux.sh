#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node --test --test-name-pattern='tmux' "$repo_dir/scripts/test-offline.mjs"
