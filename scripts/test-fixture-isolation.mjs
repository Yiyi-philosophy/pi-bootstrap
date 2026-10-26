import test from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { scratch, verifyScratchEnvironment } from './test-support.mjs';

// Independent lstat oracle: never follow attack links while hashing evidence.
function snapshot(root) {
  const records = [];
  function visit(file) {
    const st = fs.lstatSync(file), rel = path.relative(root, file);
    if (st.isSymbolicLink()) records.push([rel, 'link', fs.readlinkSync(file)]);
    else if (st.isDirectory()) { records.push([rel, 'dir', st.mode]); for (const name of fs.readdirSync(file).sort()) visit(path.join(file, name)); }
    else records.push([rel, 'file', st.mode, createHash('sha256').update(fs.readFileSync(file)).digest('hex')]);
  }
  visit(root); return records;
}
const entry = new URL('real-fixture.mjs', import.meta.url).pathname;
test('fixture isolation independently verifies a fresh environment without caller preflight', () => {
  const s = scratch('guard-valid');
  assert.equal(verifyScratchEnvironment(s.env), s.root);
  const before = snapshot(s.root);
  const r = spawnSync(process.execPath, [entry, 'probe'], { env: s.env, cwd: s.cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr); assert.deepEqual(JSON.parse(r.stdout), { version: null, commands: [] });
  assert.deepEqual(snapshot(s.root), before);
});
const changes = {
  'missing root': (s, env) => { delete env.PI_BOOTSTRAP_SCRATCH_ROOT; },
  'HOME external': (s, env, out) => { env.HOME = out.root + '/home'; },
  'TMPDIR external': (s, env, out) => { env.TMPDIR = out.root + '/tmp'; },
  'prefix external': (s, env, out) => { env.npm_config_prefix = env.NPM_CONFIG_PREFIX = out.root + '/prefix'; },
  'prefix mismatch': (s, env, out) => { env.NPM_CONFIG_PREFIX = out.root + '/prefix'; },
  'cache external': (s, env, out) => { env.npm_config_cache = out.root + '/cache'; },
  'uppercase cache external': (s, env, out) => { env.NPM_CONFIG_CACHE = out.root + '/cache'; },
  'userconfig external': (s, env, out) => { env.npm_config_userconfig = out.root + '/npmrc'; },
  'uppercase userconfig external': (s, env, out) => { env.NPM_CONFIG_USERCONFIG = out.root + '/npmrc'; },
  'globalconfig external': (s, env, out) => { env.npm_config_globalconfig = out.root + '/global-npmrc'; },
  'uppercase globalconfig external': (s, env, out) => { env.NPM_CONFIG_GLOBALCONFIG = out.root + '/global-npmrc'; },
  'agent external': (s, env, out) => { env.PI_CODING_AGENT_DIR = out.root + '/home/.pi/agent'; },
  'PATH external first': (s, env, out) => { env.PATH = out.root + '/prefix/bin:' + env.PATH; },
  'PATH external suffix': (s, env, out) => { env.PATH += ':' + out.root + '/prefix/bin'; },
  'relative HOME': (s, env) => { env.HOME = 'home'; },
  'missing component ..': (s, env) => { env.HOME = s.root + '/missing/../home'; },
  'HOME symlink': (s, env, out) => { fs.renameSync(s.root + '/home', s.root + '/saved-home'); fs.symlinkSync(out.root + '/home', s.root + '/home'); },
  'cache dangling symlink': s => { fs.rmdirSync(s.root + '/cache'); fs.symlinkSync('missing', s.root + '/cache'); },
  'cache cyclic symlink': s => { fs.rmdirSync(s.root + '/cache'); fs.symlinkSync('cache', s.root + '/cache'); },
  'userconfig symlink': (s, env, out) => { fs.unlinkSync(s.root + '/npmrc'); fs.symlinkSync(out.root + '/npmrc', s.root + '/npmrc'); },
  'globalconfig hardlink': (s, env, out) => { fs.unlinkSync(s.root + '/global-npmrc'); fs.linkSync(out.root + '/global-npmrc', s.root + '/global-npmrc'); },
  'prefix parent symlink': (s, env, out) => { fs.renameSync(s.root + '/prefix', s.root + '/saved-prefix'); fs.symlinkSync(out.root + '/prefix', s.root + '/prefix'); },
  'npm root symlink': (s, env, out) => { fs.mkdirSync(s.root + '/prefix/lib'); fs.symlinkSync(out.root + '/prefix', s.root + '/prefix/lib/node_modules'); },
  'agent parent symlink': (s, env, out) => { fs.symlinkSync(out.root + '/home', s.root + '/home/.pi'); },
  'missing receipt': s => { fs.unlinkSync(s.root + '/.scratch.json'); },
  'root symlink': (s, env, out) => { fs.symlinkSync(s.root, out.root + '/pi-independent-alias'); env.PI_BOOTSTRAP_SCRATCH_ROOT = out.root + '/pi-independent-alias'; },
};
for (const [name, change] of Object.entries(changes)) test('fixture isolation refuses ' + name + ' before npm or mutation', () => {
  const s = scratch('guard-attack'), out = scratch('guard-external'), env = { ...s.env };
  const sentinel = path.join(out.root, 'host-global-pi'); fs.writeFileSync(sentinel, 'unchanged external sentinel');
  // Any npm invocation in a failing preflight would leave both a marker and an
  // external mutation. Real host npm/global state is never queried or read.
  const marker = path.join(out.root, 'NPM_EXECUTED');
  const shim = path.join(s.root, 'prefix/bin/npm');
  fs.writeFileSync(shim, '#!/bin/sh\n/bin/touch "' + marker + '"\nprintf changed > "' + sentinel + '"\nexit 93\n', { mode: 0o700 });
  change(s, env, out);
  const before = snapshot(s.root), outsideBefore = snapshot(out.root);
  const result = spawnSync(process.execPath, [entry, 'fail-upgrade'], { env, cwd: s.cwd, encoding: 'utf8', timeout: 10000 });
  assert.notEqual(result.status, 0); assert.match(result.stderr, /AssertionError|ENOENT|ELOOP/);
  assert.doesNotMatch(result.stderr, /shadowed scratch tool/, 'must reject the attacked boundary before the npm tripwire');
  assert.deepEqual(snapshot(s.root), before); assert.deepEqual(snapshot(out.root), outsideBefore);
  assert.equal(fs.existsSync(marker), false); assert.equal(fs.readFileSync(sentinel, 'utf8'), 'unchanged external sentinel');
});
