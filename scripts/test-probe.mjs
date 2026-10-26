import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { command, verifyScratchEnvironment } from './test-support.mjs';

// Reusable regression against an actual installed Pi, always in a new scratch
// environment. Markers are written at module evaluation, before registration.
export function probeAcceptance(s) {
  verifyScratchEnvironment(s.env);
  const agent = s.env.PI_CODING_AGENT_DIR;
  const put = (rel, bytes) => { const file = path.join(agent, rel); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bytes, { mode: 0o600 }); };
  const markers = ['disabled-package', 'filtered-package', 'autoload-package', 'disabled-local', 'mjs'];
  const disabled = marker => `import fs from 'node:fs'; fs.writeFileSync(${JSON.stringify(path.join(s.root, marker))},'executed'); export default pi=>pi.registerCommand('forbidden-${marker}',{handler:async()=>{}});\n`;
  const enabled = name => `export default pi=>pi.registerCommand('${name}',{handler:async()=>{}});\n`;
  const packages = [
    { source: 'npm:scratch-disabled@1.0.0', extensions: [] },
    { source: 'npm:scratch-filtered@1.0.0', extensions: ['*.ts', '!blocked.ts'] },
    { source: 'npm:scratch-autoload@1.0.0', autoload: false, extensions: ['+enabled.ts'] },
  ];
  for (const name of ['disabled', 'filtered', 'autoload']) put('npm/node_modules/scratch-' + name + '/package.json', JSON.stringify({ name: 'scratch-' + name, version: '1.0.0', pi: { extensions: ['*.ts'] } }));
  put('npm/node_modules/scratch-disabled/index.ts', disabled('disabled-package'));
  put('npm/node_modules/scratch-filtered/enabled.ts', enabled('filtered-enabled'));
  put('npm/node_modules/scratch-filtered/blocked.ts', disabled('filtered-package'));
  put('npm/node_modules/scratch-autoload/enabled.ts', enabled('autoload-enabled'));
  put('npm/node_modules/scratch-autoload/blocked.ts', disabled('autoload-package'));
  put('extensions/disabled-local.ts', disabled('disabled-local'));
  put('extensions/unsupported.mjs', disabled('mjs'));
  put('extensions/old-enabled.ts', enabled('old-enabled'));
  put('extensions/directory/index.js', enabled('directory-enabled'));
  const settings = path.join(agent, 'settings.json');
  const config = fs.existsSync(settings) ? JSON.parse(fs.readFileSync(settings, 'utf8')) : {};
  put('settings.json', JSON.stringify({ ...config, packages: [...(config.packages || []), ...packages], extensions: [...(config.extensions || []), '-extensions/disabled-local.ts'] }, null, 2) + '\n');
  const script = `import {context,Transaction} from ${JSON.stringify(new URL('bootstrap.mjs', import.meta.url).href)}; console.log(JSON.stringify(await new Transaction(context()).probe()));`;
  const result = JSON.parse(command(s, process.execPath, ['--input-type=module', '-e', script]));
  for (const marker of markers) assert.equal(fs.existsSync(path.join(s.root, marker)), false, 'probe executed ' + marker);
  for (const name of ['old-enabled', 'filtered-enabled', 'autoload-enabled', 'directory-enabled']) assert.ok(result.commands.includes(name), 'probe missed ' + name);
  assert.equal(result.commands.some(name => name.startsWith('forbidden-')), false);
  // Leave the exact original matrix/configuration intact for later acceptance.
  if (Object.keys(config).length) put('settings.json', JSON.stringify(config, null, 2) + '\n');
  else fs.unlinkSync(settings);
  for (const name of ['disabled', 'filtered', 'autoload']) fs.rmSync(path.join(agent, 'npm/node_modules/scratch-' + name), { recursive: true });
  for (const rel of ['disabled-local.ts', 'unsupported.mjs', 'old-enabled.ts', 'directory']) fs.rmSync(path.join(agent, 'extensions', rel), { recursive: true });
  return result;
}
