import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import { spawnSync, spawn } from 'node:child_process';

export function scratch(label = 'test') {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'pi-independent-' + label + '-')));
  for (const dir of ['home', 'tmp', 'prefix/bin', 'cache', 'work']) fs.mkdirSync(path.join(root, dir), { recursive: true, mode: 0o700 });
  for (const file of ['npmrc', 'global-npmrc']) fs.writeFileSync(path.join(root, file), '');
  const env = {
    PATH: path.join(root, 'prefix/bin') + ':' + path.dirname(process.execPath) + ':/usr/bin:/bin:/usr/sbin:/sbin',
    HOME: path.join(root, 'home'), TMPDIR: path.join(root, 'tmp'),
    npm_config_prefix: path.join(root, 'prefix'), NPM_CONFIG_PREFIX: path.join(root, 'prefix'),
    npm_config_cache: path.join(root, 'cache'), NPM_CONFIG_CACHE: path.join(root, 'cache'),
    npm_config_userconfig: path.join(root, 'npmrc'), NPM_CONFIG_USERCONFIG: path.join(root, 'npmrc'),
    npm_config_globalconfig: path.join(root, 'global-npmrc'), NPM_CONFIG_GLOBALCONFIG: path.join(root, 'global-npmrc'),
    npm_config_ignore_scripts: 'true', NPM_CONFIG_IGNORE_SCRIPTS: 'true',
    npm_config_update_notifier: 'false', npm_config_audit: 'false', npm_config_fund: 'false',
    PI_CODING_AGENT_DIR: path.join(root, 'home/.pi/agent'), TMUX_CONFIG_FILE: path.join(root, 'home/.tmux.conf'),
    XDG_CACHE_HOME: path.join(root, 'cache'), XDG_CONFIG_HOME: path.join(root, 'home/.config'),
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', PI_OFFLINE: '1', LANG: 'en_US.UTF-8', CI: '1',
  };
  return { root, env, cwd: path.join(root, 'work') };
}
export function command(s, cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { env: s.env, cwd: s.cwd, encoding: 'utf8', timeout: 240000, maxBuffer: 16 * 1024 * 1024, ...options });
  if (result.status !== 0) throw Error(cmd + ' ' + args.join(' ') + '\n' + result.stdout + '\n' + result.stderr, { cause: result.error });
  return result.stdout.trim();
}
export function verifyScratch(s) {
  for (const key of ['HOME', 'TMPDIR', 'npm_config_prefix', 'NPM_CONFIG_PREFIX', 'npm_config_cache', 'NPM_CONFIG_CACHE', 'npm_config_userconfig', 'NPM_CONFIG_USERCONFIG', 'npm_config_globalconfig', 'NPM_CONFIG_GLOBALCONFIG', 'PI_CODING_AGENT_DIR', 'TMUX_CONFIG_FILE']) assert.ok(s.env[key].startsWith(s.root + '/'), key);
  assert.equal(command(s, 'npm', ['prefix', '-g']), s.env.npm_config_prefix);
  assert.equal(command(s, 'npm', ['root', '-g']), path.join(s.env.npm_config_prefix, 'lib/node_modules'));
  assert.equal(s.env.PATH.split(':')[0], path.join(s.root, 'prefix/bin'));
  return s;
}
export async function asyncCommand(s, cmd, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { env: s.env, cwd: s.cwd, stdio: ['ignore', 'pipe', 'pipe'], ...options });
    let output = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), 240000);
    child.stdout.on('data', x => { output += x; }); child.stderr.on('data', x => { output += x; });
    child.on('error', reject);
    child.on('close', code => { clearTimeout(timer); code === 0 ? resolve(output) : reject(Error(cmd + ' failed: ' + output)); });
  });
}
