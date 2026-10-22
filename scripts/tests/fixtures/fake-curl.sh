#!/usr/bin/env bash
# Fake `curl` for the pi-bootstrap tests. Serves the fixture file named by
# FAKE_CURL_FILE instead of touching the network, and fails when FAKE_CURL_FAIL=1.
set -euo pipefail

if [[ "${FAKE_CURL_FAIL:-0}" == 1 ]]; then
	echo "fake-curl: simulated download failure" >&2
	exit 22
fi

out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
	case "${args[i]}" in
		-o) out="${args[i + 1]:-}" ;;
	esac
done

[[ -n "${FAKE_CURL_FILE:-}" ]] || {
	echo "fake-curl: FAKE_CURL_FILE must be set" >&2
	exit 2
}
[[ -n "$out" ]] || {
	cat "$FAKE_CURL_FILE"
	exit 0
}
cp "$FAKE_CURL_FILE" "$out"
