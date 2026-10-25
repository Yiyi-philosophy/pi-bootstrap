import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import { spawnSync, spawn } from 'node:child_process';

const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
function tools() {
  const commands = { node: [process.execPath], npm: [process.execPath, fs.realpathSync(path.join(path.dirname(process.execPath), 'npm'))] };
  for (const name of ['bash', 'sh', 'git', 'curl', 'tar', 'cat', 'sleep', 'touch', 'env', 'uname']) {
    const file = ['/usr/bin', '/bin'].map(dir => path.join(dir, name)).find(p => fs.existsSync(p));
    assert.ok(file, 'missing test prerequisite: ' + name); commands[name] = [file];
  }
  return Object.fromEntries(Object.entries(commands).map(([name, argv]) => [name, '#!/bin/sh\nexec ' + argv.map(quote).join(' ') + ' "$@"\n']));
}
function privatePath(file, directory = false) {
  const st = fs.lstatSync(file);
  assert.ok(directory ? st.isDirectory() : st.isFile() && st.nlink === 1, 'scratch file type: ' + file);
  assert.equal(st.uid, process.getuid(), 'scratch owner: ' + file);
  assert.equal(st.mode & 0o022, 0, 'scratch permissions: ' + file);
}

// Standalone entrypoint guard: no caller-side verification is assumed. All
// lexical checks happen before filesystem access outside the declared root;
// all physical checks happen before executing even a read-only npm query.
export function verifyScratchEnvironment(env = process.env, { npm = true } = {}) {
  const root = env.PI_BOOTSTRAP_SCRATCH_ROOT;
  assert.ok(typeof root === 'string' && path.isAbsolute(root) && path.normalize(root) === root &&
    /^pi-independent-[a-zA-Z0-9_-]+$/.test(path.basename(root)), 'dedicated scratch root required');
  const expected = {
    HOME: path.join(root, 'home'), TMPDIR: path.join(root, 'tmp'),
    npm_config_prefix: path.join(root, 'prefix'), NPM_CONFIG_PREFIX: path.join(root, 'prefix'),
    npm_config_cache: path.join(root, 'cache'), NPM_CONFIG_CACHE: path.join(root, 'cache'),
    npm_config_userconfig: path.join(root, 'npmrc'), NPM_CONFIG_USERCONFIG: path.join(root, 'npmrc'),
    npm_config_globalconfig: path.join(root, 'global-npmrc'), NPM_CONFIG_GLOBALCONFIG: path.join(root, 'global-npmrc'),
    PI_CODING_AGENT_DIR: path.join(root, 'home/.pi/agent'), TMUX_CONFIG_FILE: path.join(root, 'home/.tmux.conf'),
    XDG_CACHE_HOME: path.join(root, 'cache'), XDG_CONFIG_HOME: path.join(root, 'home/.config'),
    PATH: path.join(root, 'prefix/bin') + ':' + path.join(root, 'tools/bin'),
  };
  for (const [key, value] of Object.entries(expected)) assert.equal(env[key], value, 'scratch environment: ' + key);
  if (env.PI_AGENT_DIR !== undefined) assert.equal(env.PI_AGENT_DIR, expected.PI_CODING_AGENT_DIR);
  for (const key of ['NODE_OPTIONS', 'NODE_PATH', 'npm_config_script_shell', 'NPM_CONFIG_SCRIPT_SHELL', 'npm_config_npmrc', 'NPM_CONFIG_NPMRC']) assert.ok(!env[key], 'unsupported fixture environment: ' + key);
  assert.equal(fs.realpathSync(root), root, 'redirected scratch root'); privatePath(root, true);
  const receipt = path.join(root, '.scratch.json'); privatePath(receipt);
  assert.equal(fs.readFileSync(receipt, 'utf8'), JSON.stringify({ version: 1, root, uid: process.getuid() }) + '\n', 'invalid scratch receipt');
  // Walk every existing component below root, rejecting symlinks (including
  // dangling ones). Missing agent components are allowed, never created here.
  for (const value of [...Object.values(expected).filter(v => v !== expected.PATH), path.join(root, 'tools/bin'), path.join(root, 'prefix/lib/node_modules')]) {
    let current = root;
    for (const part of path.relative(root, value).split('/')) {
      current = path.join(current, part);
      let st;
      try { st = fs.lstatSync(current); } catch (e) { if (e.code === 'ENOENT') break; throw e; }
      assert.ok(!st.isSymbolicLink(), 'redirected scratch component: ' + current);
      privatePath(current, st.isDirectory());
    }
  }
  for (const dir of ['home', 'tmp', 'prefix', 'prefix/bin', 'cache', 'tools', 'tools/bin']) privatePath(path.join(root, dir), true);
  for (const name of ['npmrc', 'global-npmrc']) privatePath(path.join(root, name));
  for (const [name, source] of Object.entries(tools())) {
    const file = path.join(root, 'tools/bin', name); privatePath(file);
    assert.equal(fs.readFileSync(file, 'utf8'), source, 'untrusted scratch tool: ' + name);
  }
  // A writable prefix/bin must never shadow the validated npm/node wrappers.
  if (npm) for (const name of Object.keys(tools())) {
    let st;
    try { st = fs.lstatSync(path.join(root, 'prefix/bin', name)); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    assert.equal(st, undefined, 'shadowed scratch tool: ' + name);
  }
  if (npm) {
    const s = { env, cwd: expected.HOME };
    for (const [args, value] of [
      [['prefix', '-g'], expected.npm_config_prefix], [['root', '-g'], path.join(root, 'prefix/lib/node_modules')],
      [['config', 'get', 'cache'], expected.npm_config_cache], [['config', 'get', 'userconfig'], expected.npm_config_userconfig],
      [['config', 'get', 'globalconfig'], expected.npm_config_globalconfig],
    ]) {
      const actual = command(s, path.join(root, 'tools/bin/npm'), args);
      assert.equal(actual, value, 'effective npm scratch path: ' + args.join(' '));
      // root -g may not exist yet, but none of its existing parents may escape.
      let current = root;
      for (const part of path.relative(root, actual).split('/')) {
        current = path.join(current, part);
        try { assert.ok(!fs.lstatSync(current).isSymbolicLink(), 'redirected npm root'); }
        catch (e) { if (e.code === 'ENOENT') break; throw e; }
      }
    }
  }
  return root;
}

export function scratch(label = 'test') {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'pi-independent-' + label + '-')));
  for (const dir of ['home', 'tmp', 'prefix/bin', 'cache', 'work', 'tools/bin']) fs.mkdirSync(path.join(root, dir), { recursive: true, mode: 0o700 });
  for (const file of ['npmrc', 'global-npmrc']) fs.writeFileSync(path.join(root, file), '');
  fs.writeFileSync(path.join(root, '.scratch.json'), JSON.stringify({ version: 1, root, uid: process.getuid() }) + '\n', { mode: 0o600 });
  for (const [name, source] of Object.entries(tools())) fs.writeFileSync(path.join(root, 'tools/bin', name), source, { mode: 0o700 });
  const env = {
    PI_BOOTSTRAP_SCRATCH_ROOT: root,
    PATH: path.join(root, 'prefix/bin') + ':' + path.join(root, 'tools/bin'),
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
  assert.equal(verifyScratchEnvironment(s.env), s.root);
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
