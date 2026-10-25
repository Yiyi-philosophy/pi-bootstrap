import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { context, physical, Transaction, inventory, settingsPlan, packageIdentity, tmuxText, rejectDuplicateKeys, encode } from './bootstrap.mjs';
import { scratch, command } from './test-support.mjs';
import { PINS } from './pins.mjs';

const sha = x => createHash('sha256').update(x).digest('hex');
const put = (file, data) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, data, { mode: 0o600 }); };
function fixture() {
  const s = scratch('offline'), c = context(s.env);
  put(c.slots.settings, '{"user":"preserve","packages":[]}\n');
  put(c.slots.keybindings, '{"custom":"ctrl+j"}\n');
  put(path.join(c.slots.extensions, 'old.ts'), 'old extension bytes\n');
  put(path.join(c.slots.npm, 'old/data'), 'old npm bytes');
  put(path.join(c.slots.git, 'old/data'), 'old git bytes');
  put(c.tmux, 'set -g mouse on\n');
  const tx = new Transaction(c); tx.lock();
  return { s, c, tx };
}
const snapshot = c => Object.fromEntries(Object.entries(c.slots).map(([slot, p]) => [slot, inventory(p, slot === 'bin', c)]));
function rewriteManifest(c, change) {
  const p = path.join(c.backup, 'manifest.json'), m = JSON.parse(fs.readFileSync(p)); change(m); fs.writeFileSync(p, encode(m));
  const j = JSON.parse(fs.readFileSync(c.journal)); j.manifest = sha(fs.readFileSync(p)); fs.writeFileSync(c.journal, encode(j));
}

test('exact package identities, valid objects, filters and unrelated data preserved', () => {
  const entry = { source: 'npm:@georgedong32/permission-modes@2.7.0', autoload: false, extensions: ['index.ts'] };
  const unrelated = ['npm:permission-modes-helper@1.0.0', 'npm:@other/pi-btw@1.0.0', 'npm:pi-advisor-flow-tools@1.0.0'];
  const p = settingsPlan({ x: 4, packages: [entry, ...unrelated] });
  assert.deepEqual(p.remove, [entry.source]); assert.equal(p.config.x, 4);
  assert.deepEqual(p.config.packages.slice(0, 3), unrelated);
  assert.deepEqual(p.config.packages.at(-1).extensions, entry.extensions);
  assert.equal(p.config.packages.at(-1).autoload, false);
  for (const url of ['https://github.com/GeorgeDong32/pi-permission-modes.git@abc', 'git:https://github.com/GeorgeDong32/pi-permission-modes.git#abc', 'git:ssh://git@github.com/GeorgeDong32/pi-permission-modes@abc', 'git:github:GeorgeDong32/pi-permission-modes#abc']) assert.equal(packageIdentity(url), '@georgedong32/permission-modes');
  assert.deepEqual(settingsPlan(p.config).config, p.config);
});
test('malformed or ambiguous settings fail closed', () => {
  for (const x of [null, [], { packages: {} }, { packages: [null] }, { packages: [{ source: 1 }] },
    { packages: [{ source: 'npm:a@1', extensions: true }] }, { packages: [{ source: 'npm:a', surprise: 1 }] },
    { packages: ['npm:a@1', 'npm:a@2'] }, { packages: ['npm:a b'] }, { npmCommand: ['bash', '-c', 'touch pwn'] }]) assert.throws(() => settingsPlan(x));
  assert.throws(() => rejectDuplicateKeys('{"packages":[],"packag\\u0065s":[]}'));
});
test('supported agent aliases and component-order physical path checks', () => {
  const s = scratch('paths'), c = context(s.env); fs.mkdirSync(c.agent, { recursive: true });
  fs.symlinkSync(c.agent, path.join(s.root, 'alias'));
  for (const candidate of [c.agent, c.agent + '/', c.agent + '/.', c.agent + '/../agent', path.join(s.root, 'alias')]) assert.equal(context({ ...s.env, PI_CODING_AGENT_DIR: candidate }).agent, c.agent);
  assert.equal(context({ ...s.env, PI_CODING_AGENT_DIR: path.relative(process.cwd(), c.agent) }).agent, c.agent);
  fs.symlinkSync(c.agent, path.join(s.root, 'parent'));
  assert.equal(physical(path.join(s.root, 'parent') + '/../agent'), c.agent);
  assert.throws(() => physical(path.join(s.root, 'missing') + '/../alias'));
  fs.symlinkSync('no-such-target', path.join(s.root, 'dangling')); fs.symlinkSync('cycle', path.join(s.root, 'cycle'));
  for (const name of ['dangling', 'cycle']) assert.throws(() => physical(path.join(s.root, name)));
});
test('custom paths refuse before journal read, network, mkdir or marker changes', () => {
  const s = scratch('custom'), c = context(s.env), marker = path.join(s.root, 'marker'); put(marker, 'sentinel');
  fs.mkdirSync(path.dirname(c.agent), { recursive: true }); fs.symlinkSync(s.root, path.join(s.root, 'external-parent'));
  const before = fs.readdirSync(s.root).sort();
  for (const raw of [s.root, '.', '..', 'relative-agent', s.root + '/missing/../home/.pi/agent', s.root + '/external-parent/home/.pi/missing/../agent']) assert.throws(() => context({ ...s.env, PI_CODING_AGENT_DIR: raw }));
  assert.deepEqual(fs.readdirSync(s.root).sort(), before); assert.equal(fs.readFileSync(marker, 'utf8'), 'sentinel'); assert.equal(fs.existsSync(c.agent), false);
});
test('actual entrypoint rejects custom agent before invoking any command or journal payload', () => {
  const s = scratch('early'), c = context(s.env), network = path.join(s.root, 'NETWORK'), payload = path.join(s.root, 'EXECUTED');
  put(c.journal, 'STATUS=$(touch ' + payload + ')\n');
  for (const name of ['npm', 'curl', 'git']) { const p = path.join(s.root, 'prefix/bin', name); put(p, '#!/bin/sh\ntouch "' + network + '"\nexit 93\n'); fs.chmodSync(p, 0o755); }
  const before = inventory(s.root);
  assert.throws(() => command({ ...s, env: { ...s.env, PI_CODING_AGENT_DIR: s.root + '/custom' } }, process.execPath, [new URL('bootstrap.mjs', import.meta.url).pathname]));
  assert.deepEqual(inventory(s.root), before); assert.equal(fs.existsSync(network), false); assert.equal(fs.existsSync(payload), false);
});
for (const attack of ['shell', 'duplicate', 'unknown', 'control', 'oversized', 'pid', 'phase', 'encoding']) test('journal parser refuses ' + attack + ' without executing or changing targets', async () => {
  const { c, tx, s } = fixture(); await tx.backup(); const before = snapshot(c), j = JSON.parse(fs.readFileSync(c.journal)), marker = path.join(s.root, 'EXECUTED');
  const records = { shell: 'STATUS=$(touch ' + marker + ')\n', duplicate: encode(j).replace('"version":1', '"version":1,"version":1'), unknown: encode({ ...j, execute: 'touch ' + marker }), control: encode(j).replace('active', 'ac\u0000tive'), oversized: ' '.repeat(8193), pid: encode({ ...j, pid: -1 }), phase: encode({ ...j, phase: '$(touch ' + marker + ')' }), encoding: JSON.stringify(j, null, 2) + '\n' };
  fs.writeFileSync(c.journal, records[attack]); await assert.rejects(() => tx.recover());
  assert.deepEqual(snapshot(c), before); assert.equal(fs.existsSync(marker), false); assert.ok(fs.existsSync(c.backup)); tx.unlock();
});
for (const location of ['agent', 'state', 'backup', 'journal', 'manifest', 'slot']) test('symlink refusal at ' + location + ' preserves external directory and committed evidence', async () => {
  const { c, tx, s } = fixture(); await tx.backup(); tx.writeJournal('committed', 'validate'); tx.unlock();
  const ext = path.join(s.root, 'outside'); fs.mkdirSync(ext); put(path.join(ext, 'sentinel'), 'external bytes');
  const target = { agent: c.agent, state: c.state, backup: c.backup, journal: c.journal, manifest: path.join(c.backup, 'manifest.json'), slot: path.join(c.backup, 'extensions') }[location];
  const saved = path.join(ext, 'saved'); fs.renameSync(target, saved); fs.symlinkSync(saved, target);
  const before = inventory(ext), newTx = new Transaction(c); assert.throws(() => newTx.validate()); await assert.rejects(() => newTx.recover());
  assert.deepEqual(inventory(ext), before); assert.equal(fs.readFileSync(path.join(ext, 'sentinel'), 'utf8'), 'external bytes');
});
test('files.tsv and created.list are rejected as untrusted extra backup evidence', async () => {
  for (const name of ['files.tsv', 'created.list', 'trees', 'cli-link', 'files']) {
    const { c, tx, s } = fixture(); await tx.backup(); const before = snapshot(c); put(path.join(c.backup, name), path.join(s.root, 'outside') + '\ttarget\n');
    await assert.rejects(() => tx.recover()); assert.deepEqual(snapshot(c), before); tx.unlock();
  }
});
test('backup bytes and redirected HOME/.pi parent cannot influence recovery', async () => {
  const { c, tx, s } = fixture(); await tx.backup(); const before = snapshot(c);
  put(path.join(c.backup, 'settings'), 'tampered backup');
  await assert.rejects(() => tx.recover()); assert.deepEqual(snapshot(c), before); tx.unlock();
  const original = path.join(s.root, 'saved-pi'); fs.renameSync(path.join(c.home, '.pi'), original);
  fs.symlinkSync(original, path.join(c.home, '.pi'));
  const externalBefore = inventory(original);
  assert.throws(() => context(s.env)); assert.throws(() => new Transaction(c).validate());
  assert.deepEqual(inventory(original), externalBefore);
});
for (const kind of ['path', 'slot', 'hash', 'symlink', 'globalAnchor', 'lateRecord']) test('all manifests prevalidated before restore: ' + kind, async () => {
  const { c, tx, s } = fixture(); await tx.backup(); put(c.slots.settings, 'damaged'); const before = snapshot(c), outside = path.join(s.root, 'sentinel'); put(outside, 'keep');
  if (kind === 'globalAnchor') { const j = JSON.parse(fs.readFileSync(c.journal)); j.anchor = '0'.repeat(64); fs.writeFileSync(c.journal, encode(j)); }
  else rewriteManifest(c, m => {
    if (kind === 'path') m.slots.settings[0].p = '../../sentinel';
    if (kind === 'slot') { m.slots.outside = m.slots.settings; delete m.slots.settings; }
    if (kind === 'hash') m.slots.settings[0].sha = '0'.repeat(64);
    if (kind === 'symlink') m.slots.settings = [{ p: '', t: 'l', mode: 0o777, target: outside }];
    if (kind === 'lateRecord') m.slots.globalLock.push({ p: '../sentinel', t: 'f', mode: 0o600, sha: '0'.repeat(64) });
  });
  await assert.rejects(() => tx.recover()); assert.deepEqual(snapshot(c), before); assert.equal(fs.readFileSync(outside, 'utf8'), 'keep'); tx.unlock();
});
test('offline recovery restores actual files with broken settings and unavailable tools', async () => {
  const { c, tx, s } = fixture(), before = snapshot(c); await tx.backup(); tx.unlock();
  put(c.slots.settings, '{broken'); put(path.join(c.slots.extensions, 'new.ts'), 'delete me'); fs.rmSync(c.slots.npm, { recursive: true });
  for (const name of ['npm', 'curl', 'git']) { const p = path.join(s.root, 'prefix/bin', name); put(p, '#!/bin/sh\nexit 93\n'); fs.chmodSync(p, 0o755); }
  const output = command(s, process.execPath, [new URL('bootstrap.mjs', import.meta.url).pathname, '--recover']);
  assert.match(output, /UNVERIFIED/); assert.deepEqual(snapshot(c), before); assert.equal(JSON.parse(fs.readFileSync(c.journal)).status, 'rolledback');
});
test('journal rename failure prevents mutation; a pending journal is safely retryable', async () => {
  const { c, tx } = fixture(); await tx.backup(); const before = snapshot(c), original = fs.renameSync; let calls = 0;
  fs.renameSync = (a, b) => { if (b === c.journal && !calls++) throw Error('injected rename failure'); return original(a, b); };
  try { assert.throws(() => tx.writeJournal('active', 'cli')); } finally { fs.renameSync = original; }
  assert.deepEqual(snapshot(c), before); assert.ok(fs.existsSync(c.journal + '.new')); await tx.recover(); assert.deepEqual(snapshot(c), before); tx.unlock();
});
test('power-loss truncated journal temporary is preserved as inert evidence and recovery works', async () => {
  const { c, tx } = fixture(), before = snapshot(c); await tx.backup();
  put(c.slots.settings, 'broken'); put(c.journal + '.new', '{"status":"$(touch NEVER)');
  await tx.recover(); assert.deepEqual(snapshot(c), before);
  assert.equal(fs.readFileSync(path.join(c.state, 'journal-fragment'), 'utf8'), '{"status":"$(touch NEVER)'); tx.unlock();
});
test('partial restoration failure preserves backup and succeeds on retry', async () => {
  const { c, tx } = fixture(), before = snapshot(c); await tx.backup(); put(c.slots.settings, 'corrupt'); put(c.slots.keybindings, 'corrupt');
  tx.checkpoint = phase => { if (phase === 'restore:keybindings') throw Error('nested restore failure'); };
  await assert.rejects(() => tx.recover()); assert.ok(fs.existsSync(path.join(c.backup, 'manifest.json')));
  tx.checkpoint = () => {}; await tx.recover(); assert.deepEqual(snapshot(c), before); tx.unlock();
});
test('failed real-loader validation retains the journal and complete backup', async () => {
  const { c, tx } = fixture(); await tx.backup();
  tx.probe = async () => ({ version: null, commands: ['unexpected-command'] });
  await assert.rejects(() => tx.recover(), /loader restoration failed/);
  assert.equal(JSON.parse(fs.readFileSync(c.journal)).status, 'recovering');
  assert.ok(fs.existsSync(path.join(c.backup, 'manifest.json')));
  tx.probe = async () => ({ version: null, commands: [] }); await tx.recover(); tx.unlock();
});
test('unmanaged pi bin and tree symlinks refuse before backup or delete', () => {
  for (const which of ['bin', 'npm']) {
    const { c, tx, s } = fixture(), outside = path.join(s.root, 'outside'); put(outside, 'keep');
    if (which === 'bin') { fs.mkdirSync(path.dirname(c.bin), { recursive: true }); fs.symlinkSync(outside, c.bin); }
    else fs.symlinkSync(outside, path.join(c.slots.npm, 'escape'));
    assert.throws(() => tx.checkTarget(which)); assert.equal(fs.readFileSync(outside, 'utf8'), 'keep'); tx.unlock();
  }
});
test('ordinary, nested and pipeline child failures are observed and leave backup intact', async () => {
  const { c, tx } = fixture(); await tx.backup(); const before = snapshot(c);
  for (const script of ['exit 7', '(exit 8)', 'set -o pipefail; false | cat']) await assert.rejects(() => tx.run('/bin/bash', ['-c', script]));
  assert.deepEqual(snapshot(c), before); await tx.recover(); tx.unlock();
});
test('committed read-only probes never rewrite journal or backup evidence', async () => {
  const { c, tx } = fixture(); await tx.backup(); tx.writeJournal('committed', 'validate');
  const before = inventory(c.state);
  assert.equal(await tx.run('/bin/echo', ['read-only-probe']), 'read-only-probe');
  assert.deepEqual(inventory(c.state), before); tx.unlock();
});
test('read-only subprocess probes work before the state directory exists', async () => {
  const s = scratch('probe'), c = context(s.env), tx = new Transaction(c);
  assert.equal(await tx.run('/bin/echo', ['probe']), 'probe');
  assert.equal(fs.existsSync(c.state), false);
});
test('journal failure prevents a gated child from executing before durability', async () => {
  const { c, tx, s } = fixture(); await tx.backup(); const before = snapshot(c), marker = path.join(s.root, 'EXECUTED');
  tx.checkpoint = phase => { if (phase.startsWith('journal:')) throw Error('injected journal failure'); };
  await assert.rejects(() => tx.run('/bin/bash', ['-c', 'touch "$HOME/../EXECUTED"']));
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(fs.existsSync(marker), false); assert.deepEqual(snapshot(c), before);
  tx.checkpoint = () => {}; await tx.recover(); tx.unlock();
});
test('tmux 3.1/3.2/3.3a/3.4/3.5/3.5a/3.6 migration and idempotence', () => {
  for (const v of ['3.1', '3.2', '3.3a', '3.4', '3.5', '3.5a', '3.6']) {
    const text = tmuxText('set -g mouse on\nset -g extended-keys on\n', 'tmux ' + v);
    assert.match(text, /set -g mouse on/); assert.equal(tmuxText(text, v), text); assert.equal(text.includes('extended-keys on'), v !== '3.1'); assert.equal(text.includes('format csi-u'), ['3.5', '3.5a', '3.6'].includes(v));
  }
});
test('exact frozen pin matrix and 69-file manifest', () => {
  assert.equal(PINS.pi, '1.4.0'); assert.equal(PINS.btw, '0.62.0'); assert.equal(PINS.advisor, '0.14.2'); assert.equal(PINS.pmVersion, '2.8.0');
  assert.equal(PINS.pmCommit, 'cf77816f28e102409dddbf8e537e4cf57aa092f0'); assert.equal(PINS.pmTree, '480649739171c272f355850cf6b6228ffa823c0c'); assert.equal(Object.keys(PINS.pmManifest).length, 69);
  for (const value of Object.values(PINS.pmManifest)) assert.match(value, /^[0-9a-f]{64}$/);
  assert.ok(PINS.minimalUrl.includes('/v1.4.0/')); assert.equal(PINS.minimalSha256, '040cbc7619b2e903888c8626e2fa55ca5e3f820535dfd1aadcb2060e156a8770');
});
test('pi remove failure stops upgrade and restores every managed slot', async () => {
  const { c, tx, s } = fixture(); tx.unlock();
  put(c.slots.settings, '{"user":5,"packages":[{"source":"npm:pi-advisor-flow@0.11.0","extensions":["index.ts"]}]}');
  const before = snapshot(c); let removed = false, installedAfterRemove = false;
  tx.probe = async () => ({ version: null, commands: [] });
  tx.stage = async () => { const stage = path.join(c.state, 'stage'); fs.mkdirSync(stage); return { stage }; };
  tx.runner = async (cmd, args) => {
    if (cmd === 'npm' && args[0] === 'prefix') return c.prefix;
    if (cmd === 'npm' && args[0] === 'root') return path.join(c.prefix, 'lib/node_modules');
    if (cmd === 'npm' && args[0] === 'install') {
      put(path.join(c.cli, 'package.json'), JSON.stringify({ name: '@earendil-works/pi-coding-agent', version: '1.4.0', bin: { pi: 'dist/cli.js' } }));
      put(path.join(c.cli, 'dist/cli.js'), 'new broken cli');
      fs.symlinkSync('../lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js', c.bin); return '';
    }
    if (args.includes('remove')) { removed = true; put(path.join(c.slots.npm, 'partial'), 'partial'); throw Error('injected pi remove failure'); }
    installedAfterRemove = true; return '';
  };
  await assert.rejects(() => tx.install('classifier'), /remove failure/);
  assert.equal(removed, true); assert.equal(installedAfterRemove, false); assert.deepEqual(snapshot(c), before);
  assert.equal(fs.existsSync(path.join(s.root, 'late-mutation')), false);
});
for (const signal of ['SIGINT', 'SIGTERM', 'SIGKILL']) test('actual ' + signal + ' interrupts worker; offline recovery restores filesystem', async () => {
  const { c, tx, s } = fixture(), before = snapshot(c); await tx.backup(); tx.unlock();
  const child = spawn(process.execPath, [new URL('signal-fixture.mjs', import.meta.url).pathname], { env: s.env, cwd: s.cwd, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = ''; child.stdout.on('data', b => { output += b; }); child.stderr.on('data', b => { output += b; });
  const finished = new Promise(resolve => child.on('close', (code, sig) => resolve({ code, sig })));
  const started = Date.now();
  while (!fs.existsSync(path.join(s.env.HOME, 'ready'))) {
    if (Date.now() - started > 5000) { child.kill('SIGKILL'); throw Error('worker did not start: ' + output); }
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  child.kill(signal); await finished;
  if (signal === 'SIGKILL') {
    await new Promise(resolve => setTimeout(resolve, 100));
    command(s, process.execPath, [new URL('bootstrap.mjs', import.meta.url).pathname, '--recover']);
  }
  assert.deepEqual(snapshot(c), before, output);
  assert.equal(fs.existsSync(path.join(s.env.HOME, 'late-mutation')), false);
  assert.ok(fs.existsSync(path.join(c.backup, 'manifest.json')));
});
test('actual SIGKILL during restoration leaves a partial tree and next recovery completes it', async () => {
  const { c, tx, s } = fixture(), before = snapshot(c); await tx.backup(); tx.unlock();
  put(c.slots.settings, 'broken'); put(c.slots.keybindings, 'broken');
  const killed = spawnSync(process.execPath, [new URL('signal-fixture.mjs', import.meta.url).pathname, '--kill-restore'], { env: s.env, cwd: s.cwd });
  assert.equal(killed.signal, 'SIGKILL');
  assert.equal(fs.readFileSync(c.slots.settings, 'utf8'), '{"user":"preserve","packages":[]}\n');
  assert.equal(fs.readFileSync(c.slots.keybindings, 'utf8'), 'broken');
  assert.equal(JSON.parse(fs.readFileSync(c.journal)).status, 'recovering');
  command(s, process.execPath, [new URL('bootstrap.mjs', import.meta.url).pathname, '--recover']);
  assert.deepEqual(snapshot(c), before);
});
