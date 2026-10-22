#!/usr/bin/env bash
# Fake `pi` for the pi-bootstrap tests: a thin wrapper over fixtures/fake-pi.js.
set -euo pipefail
exec node "${PI_BOOTSTRAP_FIXTURES:?PI_BOOTSTRAP_FIXTURES must be set}/fake-pi.js" "$@"
