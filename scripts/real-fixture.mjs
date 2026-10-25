import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { context, Transaction } from './bootstrap.mjs';
const c = context();
assert.ok(c.home.startsWith(path.dirname(process.env.TMPDIR) + '/'));
if (process.argv[2] === 'fail-upgrade') {
  const tx = new Transaction(c, { checkpoint: phase => { if (phase === 'after:cli') throw Error('acceptance: failed upgrade after real CLI replacement'); } });
  try { await tx.install(fs.readFileSync(new URL('../extensions/classifier-model.ts', import.meta.url), 'utf8')); }
  catch (error) { console.error(error); process.exitCode = 1; }
} else if (process.argv[2] === 'probe') {
  console.log(JSON.stringify(await new Transaction(c).probe()));
} else if (process.argv[2] === 'lifecycle') {
  const load = rel => import(pathToFileURL(path.join(c.cli, rel)));
  const { DefaultPackageManager } = await load('dist/core/package-manager.js');
  const { SettingsManager } = await load('dist/core/settings-manager.js');
  const source = process.argv[3], commit = process.argv[4], marker = path.join(c.home, 'lifecycle-marker');
  const manager = new DefaultPackageManager({ cwd: c.home, agentDir: c.agent, settingsManager: SettingsManager.create(c.home, c.agent) });
  for (const disabled of [false, true]) {
    process.env.npm_config_ignore_scripts = String(disabled); process.env.NPM_CONFIG_IGNORE_SCRIPTS = String(disabled);
    if (fs.existsSync(marker)) fs.unlinkSync(marker);
    await manager.installGit({ repo: 'file://' + source, host: 'fixture', path: 'lifecycle-' + disabled, ref: commit }, 'user');
    assert.equal(fs.existsSync(marker), !disabled);
  }
  console.log('PASS real Pi git lifecycle control executes; ignore-scripts suppresses marker');
} else throw Error('unknown fixture action');
