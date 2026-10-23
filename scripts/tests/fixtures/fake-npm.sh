#!/usr/bin/env bash
# Fake `npm` for the pi-bootstrap tests. Simulates `npm install -g` without a
# registry, records every invocation, and materialises a `pi` package whose
# layout matches the real npm global tree (package directory, bin symlink, and
# a CLI entry point that runs fixtures/fake-pi.js).
#
# Honours `--prefix <dir>` exactly like npm does, so the installer's staged
# install (install into a throwaway prefix, activate by moving) is exercised
# with the same file layout a real npm produces.
set -euo pipefail

if [[ -n "${FAKE_NPM_LOG:-}" ]]; then
	printf '%s\n' "$*" >>"$FAKE_NPM_LOG"
fi

prefix="${npm_config_prefix:?npm_config_prefix must be set}"
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
	case "${args[i]}" in
		--prefix)
			prefix="${args[i + 1]:-}"
			;;
		--prefix=*)
			prefix="${args[i]#--prefix=}"
			;;
	esac
done

case "${1:-}" in
	prefix)
		printf '%s\n' "$prefix"
		exit 0
		;;
	root)
		printf '%s\n' "$prefix/lib/node_modules"
		exit 0
		;;
	install)
		if [[ "${FAKE_NPM_FAIL:-0}" == 1 ]]; then
			echo "fake-npm: simulated install failure" >&2
			exit 1
		fi
		FAKE_NPM_STAGE_PREFIX="$prefix" node "${FAKE_PI_JS:?FAKE_PI_JS must be set}" --fake-npm-install
		exit $?
		;;
	view)
		printf '%s\n' '"1.4.0"'
		exit 0
		;;
esac

exit 0
