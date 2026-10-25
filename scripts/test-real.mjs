import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { context, inventory, Transaction } from './bootstrap.mjs';
import { PINS } from './pins.mjs';
import { scratch, verifyScratch, command } from './test-support.mjs';
import { probeAcceptance } from './test-probe.mjs';
const repo = new URL('../', import.meta.url).pathname;
const report = { started: new Date().toISOString(), gates: [], scratch: [] };
const evidence = process.argv[2] || scratch('evidence').root;
fs.mkdirSync(evidence, { recursive: true });
function save() { fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(report, null, 2) + '\n'); }
function pass(name) { report.gates.push({ name, status: 'PASS' }); console.log('PASS ' + name); save(); }
const put = (p, value) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, value, { mode: 0o600 }); };
const snapshot = c => Object.fromEntries(Object.entries(c.slots).map(([slot, p]) => [slot, inventory(p, slot === 'bin', c)]));
function fresh(label) { const s = verifyScratch(scratch(label)); report.scratch.push(s.root); save(); return s; }
function installer(s) {
  verifyScratch(s); const out = command(s, '/bin/bash', [path.join(repo, 'install.sh')]); console.log(out);
  fs.writeFileSync(path.join(evidence, path.basename(s.root) + '-install.log'), out + '\n');
}
function cli(s, ...args) {
  const c = context(s.env), pkg = JSON.parse(fs.readFileSync(path.join(c.cli, 'package.json')));
  return command(s, process.execPath, [path.join(c.cli, pkg.bin.pi), ...args]);
}
function probe(s) { return JSON.parse(command(s, process.execPath, [path.join(repo, 'scripts/real-fixture.mjs'), 'probe'])); }
function exact(c) {
  assert.equal(JSON.parse(fs.readFileSync(path.join(c.cli, 'package.json'))).version, PINS.pi);
  for (const [name, v] of [['@narumitw/pi-btw', PINS.btw], ['pi-advisor-flow', PINS.advisor]]) assert.equal(JSON.parse(fs.readFileSync(path.join(c.agent, 'npm/node_modules', name, 'package.json'))).version, v);
  const cfg = JSON.parse(fs.readFileSync(c.slots.settings));
  const sources = cfg.packages.map(e => typeof e === 'string' ? e : e.source);
  for (const spec of ['npm:@narumitw/pi-btw@' + PINS.btw, 'npm:pi-advisor-flow@' + PINS.advisor, 'git:github.com/GeorgeDong32/pi-permission-modes@' + PINS.pmCommit]) assert.equal(sources.filter(x => x === spec).length, 1);
  const pm = path.join(c.agent, 'git/github.com/GeorgeDong32/pi-permission-modes');
  const tx = new Transaction(c); tx.runner = (cmd, args) => command({ env: c.env, cwd: c.home }, cmd, args);
  return tx.verifySource(pm);
}
try {
  // A genuinely fresh scratch matrix, not the development prefix/cache.
  const clean = fresh('real-clean'), c = context(clean.env);
  installer(clean); await exact(c); assert.equal(probe(clean).version, PINS.pi);
  for (const name of ['auth.json', 'models.json', 'permission-modes.json', 'advisor.json']) assert.equal(fs.existsSync(path.join(c.agent, name)), false);
  pass('fresh exact pinned matrix and five real loaded extensions');
  const initial = snapshot(c), stateBefore = inventory(c.state);
  installer(clean); assert.deepEqual(snapshot(c), initial); assert.deepEqual(inventory(c.state), stateBefore);
  pass('repeat installer has byte-identical managed trees and retained evidence');
  probeAcceptance(clean);
  pass('probe honors disabled/filter/autoload resources, excludes auto-discovered mjs and verifies enabled old commands');

  const source = path.join(clean.root, 'lifecycle-source'); fs.mkdirSync(source);
  put(path.join(source, 'package.json'), JSON.stringify({ name: 'scratch-lifecycle', version: '1.0.0', scripts: { postinstall: 'node marker.cjs', prepare: 'node marker.cjs' } }));
  put(path.join(source, 'marker.cjs'), "require('node:fs').writeFileSync(process.env.HOME+'/lifecycle-marker','executed');\n");
  command(clean, 'git', ['init', source]); command(clean, 'git', ['-C', source, 'add', 'package.json', 'marker.cjs']);
  command(clean, 'git', ['-C', source, '-c', 'user.name=Scratch Test', '-c', 'user.email=scratch@example.invalid', 'commit', '-m', 'scratch fixture']);
  const commit = command(clean, 'git', ['-C', source, 'rev-parse', 'HEAD']);
  console.log(command(clean, process.execPath, [path.join(repo, 'scripts/real-fixture.mjs'), 'lifecycle', source, commit]));
  pass('real Pi package-manager lifecycle suppression proven with positive control');

  // Restore an actually working older CLI and old extensions after replacing it.
  const upgrade = fresh('real-upgrade'), u = context(upgrade.env);
  verifyScratch(upgrade);
  command(upgrade, 'npm', ['install', '-g', '--ignore-scripts', '--no-audit', '--no-fund', '@earendil-works/pi-coding-agent@1.0.2']);
  for (const spec of ['npm:@georgedong32/permission-modes@2.7.0', 'npm:@narumitw/pi-btw@0.61.1', 'npm:pi-advisor-flow@0.11.0']) cli(upgrade, 'install', spec);
  const cfg = JSON.parse(fs.readFileSync(u.slots.settings));
  cfg.packages[0] = { source: cfg.packages[0], extensions: ['index.ts'] };
  cfg.packages.push('npm:permission-modes-helper@1.0.0'); cfg.userSetting = { keep: true };
  put(u.slots.settings, JSON.stringify(cfg, null, 2) + '\n');
  put(u.slots.keybindings, '{"custom":"ctrl+j"}\n'); put(u.tmux, 'set -g mouse on\n');
  put(path.join(u.slots.extensions, 'old-probe.ts'), 'export default pi=>pi.registerCommand("old-fixture",{handler:async()=>{}});\n');
  for (const [name, value] of [['auth.json', { fixture: { type: 'api_key', key: 'scratch-only' } }], ['models.json', { providers: {} }], ['permission-modes.json', { classifier: { enabled: false }, custom: 'preserved' }]]) put(path.join(u.agent, name), JSON.stringify(value) + '\n');
  const immutable = Object.fromEntries(['auth.json', 'models.json', 'permission-modes.json'].map(name => [name, fs.readFileSync(path.join(u.agent, name), 'utf8')]));
  const oldProbe = probe(upgrade); assert.equal(oldProbe.version, '1.0.2'); assert.ok(oldProbe.commands.includes('old-fixture'));
  const before = snapshot(u);
  const failed = spawnSync(process.execPath, [path.join(repo, 'scripts/real-fixture.mjs'), 'fail-upgrade'], { env: upgrade.env, cwd: upgrade.cwd, encoding: 'utf8', timeout: 240000, maxBuffer: 16 * 1024 * 1024 });
  fs.writeFileSync(path.join(evidence, 'failed-upgrade.log'), failed.stdout + failed.stderr);
  assert.equal(failed.status, 1); assert.match(failed.stderr, /failed upgrade after real CLI replacement/);
  assert.deepEqual(snapshot(u), before); assert.deepEqual(probe(upgrade), oldProbe);
  for (const [name, bytes] of Object.entries(immutable)) assert.equal(fs.readFileSync(path.join(u.agent, name), 'utf8'), bytes);
  pass('failed upgrade restores old 1.0.2 CLI, bin, all trees and real old loader commands');

  // A killed process and damaged settings recover without npm/curl/git/network.
  const tx = new Transaction(u); tx.lock(); tx.validate(); tx.clearPrevious();
  // Use the real old loader through a scratch child, not this host process.
  tx.probe = async () => probe(upgrade); await tx.backup(); tx.unlock();
  put(u.slots.settings, '{damaged'); fs.rmSync(u.slots.extensions, { recursive: true });
  for (const name of ['npm', 'curl', 'git']) { const p = path.join(upgrade.root, 'prefix/bin', name); put(p, '#!/bin/sh\nexit 93\n'); fs.chmodSync(p, 0o755); }
  const output = command(upgrade, '/bin/bash', [path.join(repo, 'install.sh'), '--recover']);
  assert.match(output, /real CLI\/loader verified: 1.0.2/); assert.deepEqual(snapshot(u), before); assert.deepEqual(probe(upgrade), oldProbe);
  for (const name of ['npm', 'curl', 'git']) fs.unlinkSync(path.join(upgrade.root, 'prefix/bin', name));
  pass('real old CLI offline recovery with invalid settings and unavailable package/network tools');

  installer(upgrade); await exact(u);
  const migrated = JSON.parse(fs.readFileSync(u.slots.settings));
  assert.ok(migrated.packages.includes('npm:permission-modes-helper@1.0.0')); assert.deepEqual(migrated.userSetting, { keep: true });
  assert.deepEqual(migrated.packages.at(-1).extensions, ['index.ts']);
  for (const [name, bytes] of Object.entries(immutable)) assert.equal(fs.readFileSync(path.join(u.agent, name), 'utf8'), bytes);
  assert.ok(probe(upgrade).commands.includes('old-fixture'));
  pass('real npm-to-source object migration preserves unrelated packages/config/credentials');

  command(clean, 'npm', ['pack', '--ignore-scripts', '--silent', '@georgedong32/permission-modes@2.7.0', '--pack-destination', clean.root]);
  const oldPM = path.join(clean.root, 'old-pm'); fs.mkdirSync(oldPM);
  command(clean, 'tar', ['-xzf', path.join(clean.root, 'georgedong32-permission-modes-2.7.0.tgz'), '-C', oldPM]);
  const classifierOutput = command(clean, process.execPath, [path.join(repo, 'scripts/test-classifier.mjs'), '--run', path.join(oldPM, 'package')]);
  fs.writeFileSync(path.join(evidence, 'classifier.log'), classifierOutput + '\n');
  for (const line of classifierOutput.split('\n')) if (line.startsWith('PASS ')) pass(line.slice(5));
  fs.copyFileSync(path.join(c.home, 'test-evidence/classifier-requests.json'), path.join(evidence, 'classifier-requests.json'));
  report.finished = new Date().toISOString(); save(); console.log('Evidence: ' + evidence);
} catch (error) {
  report.gates.push({ name: 'acceptance stopped', status: 'FAIL', error: String(error) }); report.finished = new Date().toISOString(); save(); console.error(error); console.error('Evidence: ' + evidence); process.exitCode = 1;
}
