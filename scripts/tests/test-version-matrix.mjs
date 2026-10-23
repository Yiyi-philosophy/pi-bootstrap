#!/usr/bin/env node
// The harness and lib-pi.mjs must agree with install.sh on every pin (M3).
//
// Three copies of the matrix exist by design - install.sh (self-contained),
// scripts/tests/lib-pi.mjs (Node tests) and this suite's expectations - so a
// bump that misses one is caught here rather than by a test silently skipping.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as pins from "./lib-pi.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const installer = fs.readFileSync(path.join(repo, "install.sh"), "utf8");

function shellValue(name) {
	const match = installer.match(new RegExp(`^${name}="([^"]*)"$`, "m"));
	assert.ok(match, `install.sh defines ${name}`);
	return match[1];
}

const checks = [
	["PI_VERSION", pins.PI_VERSION],
	["PI_BTW_VERSION", pins.PI_BTW_VERSION],
	["PI_ADVISOR_FLOW_VERSION", pins.PI_ADVISOR_FLOW_VERSION],
	["PERMISSION_MODES_VERSION", pins.PERMISSION_MODES_VERSION],
	["PERMISSION_MODES_COMMIT", pins.PERMISSION_MODES_COMMIT],
	["MINIMAL_MODE_SHA256", pins.MINIMAL_MODE_SHA256],
];
for (const [name, expected] of checks) {
	assert.equal(shellValue(name), expected, `lib-pi.mjs ${name} matches install.sh`);
}
// Derive the sources exactly as the installer does: interpolate the host/path
// constants into the template install.sh uses, then compare with lib-pi.mjs.
function expand(template) {
	return template.replace(/\$\{([A-Z0-9_]+)\}/g, (_match, name) => shellValue(name));
}
assert.equal(
	expand(shellValue("PERMISSION_MODES_SOURCE")),
	`git:github.com/GeorgeDong32/pi-permission-modes@${pins.PERMISSION_MODES_COMMIT}`,
	"permission-modes source is the pinned commit",
);
assert.equal(expand(shellValue("PI_BTW_SOURCE")), `npm:@narumitw/pi-btw@${pins.PI_BTW_VERSION}`, "pi-btw source");
assert.equal(
	expand(shellValue("PI_ADVISOR_FLOW_SOURCE")),
	`npm:pi-advisor-flow@${pins.PI_ADVISOR_FLOW_VERSION}`,
	"advisor source",
);
// The minimal-mode URL must point at the pinned Pi tag, not a floating branch.
assert.match(
	expand(shellValue("MINIMAL_MODE_URL")),
	new RegExp(`/v${pins.PI_VERSION.replace(/\./g, "\\.")}/`),
	"minimal-mode URL is pinned to the Pi tag",
);

// The embedded verifier must be the same file the tests read.
const embedded = installer.slice(installer.indexOf("cat >\"$VERIFY_STACK_JS\" <<'VERIFY_STACK_JS_BODY'\n"));
const body = embedded.slice(embedded.indexOf("\n") + 1, embedded.indexOf("\nVERIFY_STACK_JS_BODY\n"));
// The heredoc body ends at the newline before the delimiter, so it lacks the
// file's final newline; everything else must be byte-identical.
assert.equal(
	body,
	fs.readFileSync(path.join(repo, "scripts/lib/verify-stack.mjs"), "utf8").replace(/\n$/, ""),
	"the embedded verify-stack.mjs matches scripts/lib/verify-stack.mjs",
);

console.log(`version matrix: ${checks.length + 3} pins agree between install.sh and lib-pi.mjs`);
