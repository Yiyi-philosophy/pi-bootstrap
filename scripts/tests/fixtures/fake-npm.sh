#!/usr/bin/env bash
# Fake `npm` for the pi-bootstrap tests. Simulates `npm install -g` without a
# registry, records every invocation, and provides the global `pi` the
# installer expects to find afterwards.
set -euo pipefail

if [[ -n "${FAKE_NPM_LOG:-}" ]]; then
	printf '%s\n' "$*" >>"$FAKE_NPM_LOG"
fi

case "${1:-}" in
	prefix)
		printf '%s\n' "${npm_config_prefix:?npm_config_prefix must be set}"
		exit 0
		;;
	install)
		[[ "${FAKE_NPM_FAIL:-0}" == 1 ]] && {
			echo "fake-npm: simulated install failure" >&2
			exit 1
		}
		mkdir -p "${npm_config_prefix:?}/bin"
		cat >"${npm_config_prefix}/bin/pi" <<'PI'
#!/usr/bin/env bash
set -euo pipefail
exec node "${FAKE_PI_JS:?FAKE_PI_JS must be set}" "$@"
PI
		chmod +x "${npm_config_prefix}/bin/pi"
		exit 0
		;;
	view)
		printf '%s\n' '"1.4.0"'
		exit 0
		;;
esac

exit 0
