#!/usr/bin/env bash
# Static wrapper: the matrix check lives in test-version-matrix.mjs.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$here/test-version-matrix.mjs"
