import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PINS } from './pins.mjs';

export const encode = value => JSON.stringify(value, (_key, item) =>
  plain(item) ? Object.fromEntries(Object.keys(item).sort().map(k => [k, item[k]])) : item) + '\n';
const hash = value => createHash('sha256').update(value).digest('hex');
const fail = message => { throw new Error(message); };
const exists = p => { try { return fs.lstatSync(p); } catch (e) { if (e.code !== 'ENOENT') throw e; } };
const within = (root, p) => p === root || p.startsWith(root + path.sep);
const plain = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const keys = (x, expected) => plain(x) && Object.keys(x).sort().join('|') === [...expected].sort().join('|');

// Resolve components in kernel order. In particular, never normalize away a
// missing component or a symlink before processing '..'. No filesystem writes.
export function physical(raw, allowMissing = true) {
  if (typeof raw !== 'string' || !raw || /[\x00-\x1f\x7f]/.test(raw)) fail('invalid path');
  let parts = (path.isAbsolute(raw) ? raw : process.cwd() + '/' + raw).split('/');
  let current = '/', links = 0, missing = false;
  while (parts.length) {
    const part = parts.shift();
    if (!part || part === '.') continue;
    if (part === '..') {
      if (missing) fail('missing path component before ..');
      current = path.dirname(current);
      continue;
    }
    current = path.join(current, part);
    const st = exists(current);
    if (!st) {
      if (!allowMissing) fail('missing path: ' + current);
      missing = true;
    } else if (st.isSymbolicLink()) {
      if (++links > 40) fail('cyclic path');
      const target = fs.readlinkSync(current);
      const base = path.dirname(current);
      current = target.startsWith('/') ? '/' : base;
      parts = [...target.split('/'), ...parts];
      // A link must itself have a resolvable destination; dangling links are
      // not equivalent to a directory that has yet to be created.
      fs.realpathSync(path.join(base, part));
    } else if (parts.some(p => p && p !== '.') && !st.isDirectory()) fail('non-directory parent');
  }
  return current;
}

function anchored(p, type, optional = false) {
  // Every component below the physical HOME/prefix is examined; lstat of just
  // the leaf would trust a journal in a redirected parent.
  if (physical(p) !== p) fail('redirected path: ' + p);
  const st = exists(p);
  if (!st) { if (optional) return; fail('missing ' + p); }
  if ((type === 'dir' && !st.isDirectory()) || (type === 'file' && !st.isFile())) fail('wrong file type: ' + p);
  if (st.uid !== process.getuid() || (st.mode & 0o022)) fail('untrusted ownership/mode: ' + p);
  if (st.isFile() && st.nlink !== 1) fail('hardlinked file: ' + p);
  return st;
}

export function context(env = process.env) {
  const home = fs.realpathSync(env.HOME || fail('HOME is required'));
  const agent = path.join(home, '.pi/agent');
  // This check precedes journal access, process execution, mkdir and network.
  for (const custom of [env.PI_CODING_AGENT_DIR, env.PI_AGENT_DIR]) {
    if (custom !== undefined && physical(custom) !== agent) fail('UNSUPPORTED custom agent directory');
  }
  if (physical(agent) !== agent) fail('UNSUPPORTED redirected default agent directory');
  const prefix = physical(env.npm_config_prefix || env.NPM_CONFIG_PREFIX || path.dirname(path.dirname(process.execPath)));
  if (env.npm_config_prefix && env.NPM_CONFIG_PREFIX && physical(env.NPM_CONFIG_PREFIX) !== prefix) fail('conflicting npm prefixes');
  const tmux = physical(env.TMUX_CONFIG_FILE || path.join(home, '.tmux.conf'));
  if (!within(home, tmux)) fail('tmux config must be within HOME');
  const state = path.join(agent, '.pi-bootstrap');
  const cli = path.join(prefix, 'lib/node_modules/@earendil-works/pi-coding-agent');
  const bin = path.join(prefix, 'bin/pi');
  const slots = {
    settings: path.join(agent, 'settings.json'), keybindings: path.join(agent, 'keybindings.json'),
    settingsTemp: path.join(agent, 'settings.json.new'), keybindingsTemp: path.join(agent, 'keybindings.json.new'),
    extensions: path.join(agent, 'extensions'), npm: path.join(agent, 'npm'), git: path.join(agent, 'git'),
    tmux, tmuxTemp: tmux + '.new', cli, bin, globalLock: path.join(prefix, 'lib/node_modules/.package-lock.json'),
  };
  return { home, agent, prefix, tmux, cli, bin, state, backup: path.join(state, 'backup'),
    journal: path.join(state, 'transaction.env'), slots, anchor: hash(encode(slots)), env };
}

function readData(file, limit) {
  const st = anchored(file, 'file');
  if (st.size > limit) fail('oversized record');
  const bytes = fs.readFileSync(file);
  const text = bytes.toString('utf8');
  let data;
  try { data = JSON.parse(text); } catch { fail('invalid data record'); }
  // Canonical serialization rejects duplicate keys, alternate encodings,
  // trailing records, invalid UTF-8 and literal control bytes without eval.
  if (!Buffer.from(encode(data)).equals(bytes)) fail('noncanonical record');
  return data;
}

function syncDir(p) {
  const fd = fs.openSync(p, 'r');
  try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
}
function durable(file, data, mode = 0o600) {
  anchored(path.dirname(file), 'dir');
  const previous = anchored(file, 'file', true);
  if (previous) mode = previous.mode & 0o777;
  const tmp = file + '.new';
  const fd = fs.openSync(tmp, 'wx', mode);
  try { fs.writeFileSync(fd, data); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, file);
  syncDir(path.dirname(file));
}
function mkdir(p) {
  if (!exists(p)) { mkdir(path.dirname(p)); fs.mkdirSync(p, { mode: 0o700 }); syncDir(path.dirname(p)); }
  anchored(p, 'dir');
}
function safeRelative(rel) {
  return typeof rel === 'string' && rel.length < 4096 && (rel === '' || rel.split('/').every(x => x && x !== '.' && x !== '..')) && !/[\x00-\x1f\x7f\\]/.test(rel);
}
function safeLink(rel, target) {
  return typeof target === 'string' && target.length < 4096 && !/[\x00-\x1f\x7f]/.test(target) && !path.isAbsolute(target) && within('/slot', path.resolve('/slot', path.dirname(rel), target));
}

// Inventories are both the backup manifest and the restore verification oracle.
// Symlinks are copied as links, never followed. All restored paths are derived
// from fixed slots plus validated relative names, never from stored targets.
export function inventory(root, bin = false, ctx) {
  const records = [];
  function visit(rel) {
    const p = rel ? path.join(root, rel) : root;
    const st = exists(p);
    if (!st) return;
    if (!safeRelative(rel)) fail('unsafe filename');
    const mode = st.mode & 0o777;
    if (st.isSymbolicLink()) {
      const target = fs.readlinkSync(p);
      if (bin) {
        const dest = path.resolve(path.dirname(ctx.bin), target);
        if (![path.join(ctx.cli, 'dist/cli.js'), path.join(ctx.cli, 'dist/bundle/cli.js')].includes(dest)) fail('unmanaged pi bin link');
      } else if (!rel || !safeLink(rel, target)) fail('external symlink: ' + p);
      records.push({ p: rel, t: 'l', mode, target });
    } else if (st.isDirectory()) {
      if (st.uid !== process.getuid() || (st.mode & 0o022)) fail('untrusted tree directory: ' + p);
      records.push({ p: rel, t: 'd', mode });
      for (const name of fs.readdirSync(p).sort()) visit(rel ? rel + '/' + name : name);
    } else if (st.isFile() && st.nlink === 1) {
      if (st.uid !== process.getuid() || (st.mode & 0o022)) fail('untrusted tree file: ' + p);
      records.push({ p: rel, t: 'f', mode, sha: hash(fs.readFileSync(p)) });
    } else fail('unsupported filesystem entry: ' + p);
  }
  visit('');
  return records;
}
function copyRecords(from, to, records) {
  for (const r of records) {
    const src = path.join(from, r.p), dest = path.join(to, r.p);
    if (r.t === 'd') fs.mkdirSync(dest, { mode: 0o700 });
    else if (r.t === 'l') fs.symlinkSync(r.target, dest);
    else {
      const fd = fs.openSync(dest, 'wx', r.mode);
      try { fs.writeFileSync(fd, fs.readFileSync(src)); fs.fchmodSync(fd, r.mode); fs.fsyncSync(fd); }
      finally { fs.closeSync(fd); }
    }
  }
  for (const r of [...records].reverse()) if (r.t === 'd') { fs.chmodSync(path.join(to, r.p), r.mode); syncDir(path.join(to, r.p)); }
  syncDir(path.dirname(to));
}

export function packageIdentity(source) {
  if (typeof source !== 'string' || !source || source.trim() !== source || /[\x00-\x1f\x7f]/.test(source)) fail('invalid package source');
  if (source.startsWith('npm:')) {
    const match = /^npm:((?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*)(?:@([a-zA-Z0-9*^~<>=][a-zA-Z0-9.*+^~<>=| -]*))?$/.exec(source);
    if (!match) fail('ambiguous npm source');
    return match[1];
  }
  const git = /^(?:git:)?(?:(?:git\+)?(?:https?|ssh|git):\/\/(?:git@)?github\.com\/|git@github\.com:|github\.com\/|github:)([^/#@]+\/[^/#@]+?)(?:\.git)?(?:[@#].+)?$/i.exec(source);
  if (git) {
    const repo = git[1].toLowerCase();
    if (repo === 'georgedong32/pi-permission-modes') return '@georgedong32/permission-modes';
    return 'git:github.com/' + repo;
  }
  return source;
}
const desired = () => [
  'npm:@narumitw/pi-btw@' + PINS.btw,
  'npm:pi-advisor-flow@' + PINS.advisor,
  'git:github.com/GeorgeDong32/pi-permission-modes@' + PINS.pmCommit,
];
export function settingsPlan(config) {
  if (!plain(config) || (config.packages !== undefined && !Array.isArray(config.packages))) fail('settings conflict');
  if (config.npmCommand !== undefined && encode(config.npmCommand) !== encode(['npm'])) fail('UNSUPPORTED npmCommand');
  const seen = new Set(), remove = [], result = [], originals = new Map();
  const ids = new Map(desired().map(s => [packageIdentity(s), s]));
  for (const entry of config.packages || []) {
    if (typeof entry !== 'string' && (!plain(entry) || !Object.keys(entry).every(k => ['source', 'autoload', 'extensions', 'skills', 'prompts', 'themes'].includes(k)) ||
        Object.entries(entry).some(([k, v]) => k === 'autoload' ? typeof v !== 'boolean' : k !== 'source' && (!Array.isArray(v) || v.some(x => typeof x !== 'string'))))) fail('malformed package object');
    const source = typeof entry === 'string' ? entry : entry.source;
    const id = packageIdentity(source);
    if (seen.has(id)) fail('duplicate/ambiguous package identity: ' + id);
    seen.add(id);
    if (ids.has(id)) {
      originals.set(id, entry);
      if (source !== ids.get(id)) remove.push(source);
    } else result.push(entry);
  }
  for (const [id, source] of ids) {
    const old = originals.get(id);
    result.push(plain(old) ? { ...old, source } : source);
  }
  return { remove, config: { ...config, packages: result } };
}
function readObject(file) {
  anchored(file, 'file', true);
  if (!exists(file)) return {};
  const text = fs.readFileSync(file, 'utf8');
  // Reject duplicate JSON keys at any depth using a lexical token walk.
  rejectDuplicateKeys(text);
  const value = JSON.parse(text);
  if (!plain(value)) fail('JSON object required: ' + file);
  return value;
}
function cliMetadata(c) {
  const pkg = JSON.parse(fs.readFileSync(path.join(c.cli, 'package.json')));
  if (pkg.name !== '@earendil-works/pi-coding-agent' || !/^\d+\.\d+\.\d+$/.test(pkg.version) ||
      !['dist/cli.js', 'dist/bundle/cli.js'].includes(pkg.bin?.pi)) fail('unsupported CLI metadata');
  const entry = path.join(c.cli, pkg.bin.pi);
  anchored(entry, 'file');
  return { version: pkg.version, entry };
}
export function rejectDuplicateKeys(text) {
  const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]|[^\s{}\[\]:,]+/g) || [];
  const stack = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token === '{') stack.push(new Set());
    else if (token === '[') stack.push(null);
    else if (token === '}' || token === ']') stack.pop();
    else if (tokens[i + 1] === ':' && stack.at(-1) instanceof Set) {
      const key = JSON.parse(token);
      if (stack.at(-1).has(key)) fail('duplicate JSON key');
      stack.at(-1).add(key);
    }
  }
}

export function tmuxText(text, version) {
  const m = /^(?:tmux )?(\d+)\.(\d+)[a-z]?$/.exec(version);
  if (!m) return text;
  let skip = false;
  const lines = text.split('\n').filter(line => {
    if (line === '# >>> pi-bootstrap >>>') { if (skip) fail('nested tmux block'); skip = true; return false; }
    if (line === '# <<< pi-bootstrap <<<') { if (!skip) fail('unbalanced tmux block'); skip = false; return false; }
    return !skip && line !== 'set -g extended-keys on';
  });
  if (skip) fail('unterminated tmux block');
  const base = lines.join('\n').replace(/\n+$/, '');
  const major = +m[1], minor = +m[2];
  if (major < 3 || (major === 3 && minor < 2)) return base ? base + '\n' : '';
  return (base ? base + '\n\n' : '') + '# >>> pi-bootstrap >>>\nset -g extended-keys on\n' +
    (major > 3 || minor >= 5 ? 'set -g extended-keys-format csi-u\n' : '') + '# <<< pi-bootstrap <<<\n';
}

export class Transaction {
  constructor(ctx, { runner, checkpoint = () => {} } = {}) {
    this.c = ctx; this.runner = runner; this.checkpoint = checkpoint;
    this.child = null; this.signal = null; this.restoring = false;
  }
  async run(command, args, options = {}) {
    if (this.signal && !this.restoring) fail('interrupted: ' + this.signal);
    if (this.runner) return this.runner(command, args, options);
    const env = { ...this.c.env, HOME: this.c.home, PI_CODING_AGENT_DIR: this.c.agent,
      npm_config_prefix: this.c.prefix, NPM_CONFIG_PREFIX: this.c.prefix,
      npm_config_ignore_scripts: 'true', NPM_CONFIG_IGNORE_SCRIPTS: 'true',
      GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.hooksPath', GIT_CONFIG_VALUE_0: '/dev/null',
      PI_OFFLINE: '1', ...options.env };
    return new Promise((resolve, reject) => {
      // A detached worker waits for a durable journal record before executing.
      // IPC disconnect kills its complete process group if the installer dies.
      const worker = `const {spawn}=require('node:child_process');
        process.on('disconnect',()=>{try{process.kill(-process.pid,'SIGKILL')}catch{process.exit(1)}});
        process.once('message',()=>{const c=spawn(process.argv[1],process.argv.slice(2),{stdio:['ignore','inherit','inherit']});
          c.on('error',e=>{console.error(e);process.exit(1)});c.on('close',n=>process.exit(n??1));});`;
      const child = spawn(process.execPath, ['-e', worker, command, ...args], { cwd: options.cwd || (exists(this.c.state) ? this.c.state : this.c.home), env, detached: true, stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
      this.child = child;
      let out = '', err = '', timedOut = false;
      const kill = () => { try { process.kill(-child.pid, 'SIGKILL'); } catch {} };
      const timer = setTimeout(() => { timedOut = true; kill(); }, options.timeout || 180_000);
      child.stdout.on('data', b => { out += b; if (out.length > 8 * 1024 * 1024) kill(); });
      child.stderr.on('data', b => { err = (err + b).slice(-16000); });
      child.on('error', reject);
      child.on('close', code => {
        clearTimeout(timer); this.child = null;
        if (code === 0 && !timedOut) resolve(out.trim());
        else reject(new Error(command + ' failed (' + code + (timedOut ? ', timeout' : '') + '): ' + err));
      });
      try {
        if (this.j && ['active', 'recovering'].includes(this.j.status)) { this.worker = child.pid; this.writeJournal(this.j.status, this.j.phase); }
        child.send('start');
      } catch (error) { kill(); reject(error); }
    });
  }
  boundary() {
    const c = this.c;
    if (physical(c.agent) !== c.agent) fail('agent redirected');
    for (const p of [c.home, path.join(c.home, '.pi'), c.agent]) anchored(p, 'dir', true);
    anchored(c.state, 'dir', true);
    if (exists(c.state)) {
      for (const name of fs.readdirSync(c.state)) {
        if (!['backup', 'transaction.env', 'transaction.env.new', 'journal-fragment', 'lock', 'stage'].includes(name)) fail('unknown state evidence: ' + name);
        if (name !== 'backup') anchored(path.join(c.state, name), name === 'stage' ? 'dir' : 'file');
      }
    }
    anchored(c.backup, 'dir', true);
  }
  lock() {
    this.boundary(); mkdir(this.c.state);
    const p = path.join(this.c.state, 'lock');
    if (exists(p)) {
      const old = readData(p, 256);
      if (!keys(old, ['version', 'pid']) || old.version !== 1 || !Number.isSafeInteger(old.pid) || old.pid <= 0) fail('invalid lock');
      try { process.kill(old.pid, 0); fail('another installer may be running'); }
      catch (e) { if (e.code !== 'ESRCH') throw e; }
      fs.unlinkSync(p); syncDir(this.c.state);
    }
    const fd = fs.openSync(p, 'wx', 0o600);
    try { fs.writeFileSync(fd, encode({ version: 1, pid: process.pid })); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
    syncDir(this.c.state); this.locked = true;
  }
  unlock() {
    if (this.locked) { this.boundary(); fs.unlinkSync(path.join(this.c.state, 'lock')); syncDir(this.c.state); this.locked = false; }
  }
  writeJournal(status, phase) {
    this.boundary();
    this.checkpoint('journal:' + status + ':' + phase);
    const j = { version: 1, status, phase, pid: process.pid, worker: this.worker || 0, anchor: this.c.anchor, manifest: this.manifestHash };
    durable(this.c.journal, encode(j));
    this.j = j;
  }
  validate() {
    this.boundary();
    const j = readData(this.c.journal, 8192);
    const validJournal = j => keys(j, ['version', 'status', 'phase', 'pid', 'worker', 'anchor', 'manifest']) && j.version === 1 &&
        ['active', 'recovering', 'rolledback', 'committed'].includes(j.status) &&
        ['prepared', 'cli', 'packages', 'files', 'validate', 'restore'].includes(j.phase) &&
        Number.isSafeInteger(j.pid) && j.pid >= 1 && Number.isSafeInteger(j.worker) && j.worker >= 0 && j.anchor === this.c.anchor && /^[0-9a-f]{64}$/.test(j.manifest);
    if (!validJournal(j)) fail('invalid journal');
    if (exists(this.c.journal + '.new')) {
      if (anchored(this.c.journal + '.new', 'file').size > 8192) fail('oversized pending journal');
    }
    const manifestFile = path.join(this.c.backup, 'manifest.json');
    const manifest = readData(manifestFile, 32 * 1024 * 1024);
    if (hash(fs.readFileSync(manifestFile)) !== j.manifest || !keys(manifest, ['version', 'slots', 'probe']) || manifest.version !== 1 ||
        !keys(manifest.slots, Object.keys(this.c.slots))) fail('invalid backup manifest');
    if (!keys(manifest.probe, ['version', 'commands']) || !(manifest.probe.version === null || /^\d+\.\d+\.\d+$/.test(manifest.probe.version)) ||
        !Array.isArray(manifest.probe.commands) || manifest.probe.commands.some(x => typeof x !== 'string' || !/^[a-zA-Z0-9_:/.-]{1,100}$/.test(x))) fail('invalid loader evidence');
    const allowed = ['manifest.json', ...Object.keys(this.c.slots)];
    if (fs.readdirSync(this.c.backup).some(n => !allowed.includes(n))) fail('unknown backup evidence');
    for (const [slot, records] of Object.entries(manifest.slots)) {
      if (!Array.isArray(records)) fail('invalid inventory');
      const directorySlot = ['extensions', 'npm', 'git', 'cli'].includes(slot);
      if (records.length && (records[0]?.p !== '' || (slot === 'bin' ? !['f', 'l'].includes(records[0]?.t) : records[0]?.t !== (directorySlot ? 'd' : 'f')))) fail('wrong snapshot root type');
      const seen = new Map();
      for (const r of records) {
        if (!keys(r, r.t === 'f' ? ['p', 't', 'mode', 'sha'] : r.t === 'l' ? ['p', 't', 'mode', 'target'] : ['p', 't', 'mode']) ||
            !safeRelative(r.p) || seen.has(r.p) || !Number.isInteger(r.mode) || r.mode < 0 || r.mode > 0o777 ||
            !['d', 'f', 'l'].includes(r.t) || (r.t === 'f' && !/^[0-9a-f]{64}$/.test(r.sha)) ||
            (r.p !== '' && seen.get(path.posix.dirname(r.p) === '.' ? '' : path.posix.dirname(r.p)) !== 'd')) fail('invalid inventory entry');
        if (r.t === 'l' && !(slot === 'bin' && r.p === '') && (!r.p || !safeLink(r.p, r.target))) fail('unsafe manifest link');
        seen.set(r.p, r.t);
      }
      const backupRoot = path.join(this.c.backup, slot);
      // inventory does not follow even the bin link; it validates its target.
      if (encode(inventory(backupRoot, slot === 'bin', this.c)) !== encode(records)) fail('backup integrity failure: ' + slot);
      this.checkTarget(slot);
    }
    const cliRecords = manifest.slots.cli;
    if (Boolean(cliRecords.length) !== Boolean(manifest.probe.version)) fail('CLI snapshot/evidence conflict');
    if (cliRecords.length && cliMetadata({ ...this.c, cli: path.join(this.c.backup, 'cli') }).version !== manifest.probe.version) fail('backup CLI metadata mismatch');
    this.j = j; this.manifest = manifest; this.manifestHash = j.manifest;
    return j;
  }
  checkTarget(slot) {
    const target = this.c.slots[slot];
    if (physical(path.dirname(target)) !== path.dirname(target)) fail('redirected restore parent');
    if (slot !== 'bin') {
      if (physical(target) !== target) fail('redirected restore target');
      inventory(target, false, this.c);
    } else inventory(target, true, this.c);
  }
  async probe() {
    const c = this.c;
    if (!exists(c.cli)) return { version: null, commands: [] };
    const { version, entry } = cliMetadata(c);
    const script = `
      import fs from 'node:fs'; import path from 'node:path'; import {pathToFileURL} from 'node:url';
      const [cli,agent] = process.argv.slice(1);
      const {loadExtensions} = await import(pathToFileURL(path.join(cli,'dist/core/extensions/loader.js')));
      const config=fs.existsSync(path.join(agent,'settings.json'))?JSON.parse(fs.readFileSync(path.join(agent,'settings.json'),'utf8')):{};
      const paths=[];
      for(const e of config.packages||[]) {
        const s=typeof e==='string'?e:e.source;
        if(s.startsWith('npm:')) {
          const name=s.slice(4).replace(/@[^@/]+$/,'');
          const root=path.join(agent,'npm/node_modules',name), p=path.join(root,'package.json');
          if(fs.existsSync(p)) for(const f of JSON.parse(fs.readFileSync(p)).pi?.extensions||[]) paths.push(path.join(root,f));
        } else if(s.startsWith('git:github.com/')) {
          const root=path.join(agent,'git/github.com',s.slice(15).split('@')[0]);
          const p=path.join(root,'package.json');
          if(fs.existsSync(p)) for(const f of JSON.parse(fs.readFileSync(p)).pi?.extensions||[]) paths.push(path.join(root,f));
        }
      }
      const ext=path.join(agent,'extensions');
      if(fs.existsSync(ext)) for(const f of fs.readdirSync(ext)) if(/\\.(ts|js|mjs)$/.test(f)) paths.push(path.join(ext,f));
      const result=await loadExtensions(paths,agent);
      if(result.errors.length) throw Error(JSON.stringify(result.errors));
      console.log(JSON.stringify([...new Set(result.extensions.flatMap(e=>[...e.commands.keys()]))].sort()));
    `;
    const output = await this.run(process.execPath, ['--input-type=module', '-e', script, c.cli, c.agent], { timeout: 45000 });
    const commands = JSON.parse(output.split('\n').at(-1));
    const actual = await this.run(process.execPath, [entry, '--version']);
    if (actual !== version) fail('CLI version probe failed');
    return { version, commands };
  }
  async backup() {
    const c = this.c;
    this.boundary();
    if (exists(c.backup) || exists(c.journal) || exists(c.journal + '.new')) fail('unresolved transaction evidence');
    const probe = await this.probe();
    for (const slot of Object.keys(c.slots)) this.checkTarget(slot);
    mkdir(c.backup);
    const slots = {};
    for (const [slot, target] of Object.entries(c.slots)) {
      slots[slot] = inventory(target, slot === 'bin', c);
      if (slots[slot].length) copyRecords(target, path.join(c.backup, slot), slots[slot]);
    }
    this.manifest = { version: 1, slots, probe };
    const data = encode(this.manifest);
    durable(path.join(c.backup, 'manifest.json'), data);
    this.manifestHash = hash(data);
    this.writeJournal('active', 'prepared');
    this.validate();
  }
  async recover() {
    // Validation of EVERY field, record, backup object and destination happens
    // before the first destructive restore. A failed validation keeps evidence.
    this.validate();
    if (this.j.worker) {
      try { process.kill(this.j.worker, 0); fail('recorded worker may still be running; retry after it exits'); }
      catch (e) { if (e.code !== 'ESRCH') throw e; }
    }
    this.restoring = true;
    try {
      if (exists(this.c.journal + '.new')) {
        // A killed write may leave a truncated temporary record. It is never
        // interpreted; retain its bytes, after validating the official journal
        // and every backup/destination, before replacing the temporary file.
        const fragment = path.join(this.c.state, 'journal-fragment');
        const bytes = fs.readFileSync(this.c.journal + '.new');
        if (exists(fragment)) {
          if (!fs.readFileSync(fragment).equals(bytes)) fail('multiple pending journal fragments; preserve evidence');
        } else durable(fragment, bytes);
        fs.unlinkSync(this.c.journal + '.new'); syncDir(this.c.state);
      }
      this.writeJournal('recovering', 'restore');
      for (const [slot, target] of Object.entries(this.c.slots)) {
        this.boundary(); this.checkTarget(slot);
        this.checkpoint('restore:' + slot);
        fs.rmSync(target, { recursive: true, force: true });
        mkdir(path.dirname(target));
        const records = this.manifest.slots[slot];
        if (records.length) copyRecords(path.join(this.c.backup, slot), target, records);
        syncDir(path.dirname(target));
      }
      for (const [slot, target] of Object.entries(this.c.slots)) {
        if (encode(inventory(target, slot === 'bin', this.c)) !== encode(this.manifest.slots[slot])) fail('restoration mismatch: ' + slot);
      }
      const actual = await this.probe();
      if (encode(actual) !== encode(this.manifest.probe)) fail('old Pi loader restoration failed');
      console.log(actual.version ? 'Rollback real CLI/loader verified: ' + actual.version : 'Rollback loader UNVERIFIED (no previous CLI)');
      this.writeJournal('rolledback', 'restore');
    } finally { this.restoring = false; }
  }
  clearPrevious() {
    this.validate();
    if (!['committed', 'rolledback'].includes(this.j.status)) fail('recovery required');
    const stage = path.join(this.c.state, 'stage');
    if (exists(stage)) { inventory(stage); fs.rmSync(stage, { recursive: true }); syncDir(this.c.state); }
    if (exists(path.join(this.c.state, 'journal-fragment'))) fail('retained journal fragment requires review before a new install');
    // No best-effort deletion: on any failure, stop and retain the remaining
    // evidence. A crash during cleanup may require manual review.
    fs.rmSync(this.c.backup, { recursive: true }); syncDir(this.c.state);
    fs.unlinkSync(this.c.journal); syncDir(this.c.state);
    this.j = null;
  }
  async verifySource(dir) {
    if (await this.run('git', ['-C', dir, 'rev-parse', 'HEAD']) !== PINS.pmCommit ||
        await this.run('git', ['-C', dir, 'rev-parse', 'HEAD^{tree}']) !== PINS.pmTree ||
        await this.run('git', ['-C', dir, 'status', '--porcelain'])) fail('permission source commit/tree/cleanliness mismatch');
    const files = (await this.run('git', ['-C', dir, 'ls-files'])).split('\n').sort();
    if (encode(files) !== encode(Object.keys(PINS.pmManifest).sort())) fail('permission source file set mismatch');
    for (const [rel, sha] of Object.entries(PINS.pmManifest)) {
      const p = path.join(dir, rel);
      if (!exists(p)?.isFile() || physical(p) !== p || hash(fs.readFileSync(p)) !== sha) fail('permission source checksum: ' + rel);
    }
  }
  async stage() {
    const stage = path.join(this.c.state, 'stage');
    if (exists(stage)) fail('unresolved staging evidence');
    mkdir(stage);
    const pm = path.join(stage, 'pm');
    await this.run('git', ['init', pm]);
    await this.run('git', ['-C', pm, 'remote', 'add', 'origin', 'https://github.com/GeorgeDong32/pi-permission-modes.git']);
    await this.run('git', ['-C', pm, 'fetch', '--depth=1', 'origin', PINS.pmCommit]);
    await this.run('git', ['-C', pm, 'checkout', '--detach', PINS.pmCommit]);
    await this.verifySource(pm);
    const minimal = path.join(stage, 'minimal-mode.ts');
    await this.run('curl', ['--fail', '--silent', '--show-error', '--location', '--proto', '=https', '--max-time', '60', PINS.minimalUrl, '-o', minimal]);
    if (hash(fs.readFileSync(minimal)) !== PINS.minimalSha256) fail('minimal-mode checksum mismatch');
    return { stage, pm, minimal };
  }
  async install(classifier) {
    const c = this.c;
    this.boundary();
    // Parse all settings and destinations before the first write or network.
    const plan = settingsPlan(readObject(c.slots.settings));
    const bindings = readObject(c.slots.keybindings);
    for (const p of [c.slots.settingsTemp, c.slots.keybindingsTemp, c.slots.tmuxTemp]) if (exists(p)) fail('unresolved atomic-write evidence: ' + p);
    for (const slot of Object.keys(c.slots)) this.checkTarget(slot);
    const prefix = physical(await this.run('npm', ['prefix', '-g'], { cwd: c.home }));
    const root = physical(await this.run('npm', ['root', '-g'], { cwd: c.home }));
    if (prefix !== c.prefix || root !== path.join(c.prefix, 'lib/node_modules')) fail('npm global paths differ from anchored prefix');
    this.lock();
    try {
      if (exists(c.journal)) {
        const j = this.validate();
        if (['active', 'recovering'].includes(j.status)) { await this.recover(); fail('Interrupted run restored; rerun installation explicitly'); }
        if (j.status === 'committed' && await this.isCurrent(classifier)) { console.log('Pinned matrix already installed; no changes.'); return; }
        this.clearPrevious();
      } else if (exists(c.backup)) fail('backup without journal; preserve evidence');
      const prepared = await this.stage();
      await this.backup();
      try {
        this.writeJournal('active', 'cli');
        await this.run('npm', ['install', '-g', '--ignore-scripts', '--no-audit', '--no-fund', '@earendil-works/pi-coding-agent@' + PINS.pi]);
        this.checkpoint('after:cli');
        const cliEntry = cliMetadata(c).entry;
        this.writeJournal('active', 'packages');
        for (const source of plan.remove) await this.run(process.execPath, [cliEntry, 'remove', source]);
        for (const source of desired().slice(0, 2)) await this.run(process.execPath, [cliEntry, 'install', source]);
        // Pi's git installer executes npm install on a new checkout. Instead,
        // publish only the already SHA256-verified snapshot (no runtime deps)
        // and persist its exact source alongside Pi's npm-installed entries.
        const pmTarget = path.join(c.agent, 'git/github.com/GeorgeDong32/pi-permission-modes');
        mkdir(path.dirname(pmTarget));
        fs.rmSync(pmTarget, { recursive: true, force: true });
        copyRecords(prepared.pm, pmTarget, inventory(prepared.pm));
        await this.verifySource(pmTarget);
        this.writeJournal('active', 'files');
        durable(c.slots.settings, JSON.stringify(plan.config, null, 2) + '\n');
        mkdir(c.slots.extensions);
        durable(path.join(c.slots.extensions, 'classifier-model.ts'), classifier, 0o644);
        durable(path.join(c.slots.extensions, 'minimal-mode.ts'), fs.readFileSync(prepared.minimal), 0o644);
        durable(c.slots.keybindings, JSON.stringify({ ...bindings, 'app.thinking.cycle': 'ctrl+shift+tab' }, null, 2) + '\n');
        let tmuxVersion;
        try { tmuxVersion = await this.run('tmux', ['-V']); } catch (e) { if (!e.message.includes('ENOENT')) throw e; }
        if (tmuxVersion) {
          const old = exists(c.tmux) ? fs.readFileSync(c.tmux, 'utf8') : '';
          mkdir(path.dirname(c.tmux));
          durable(c.tmux, tmuxText(old, tmuxVersion));
        }
        this.writeJournal('active', 'validate');
        const probe = await this.probe();
        const required = ['mode', 'btw', 'advisor', 'advisor-models', 'classifier-model'];
        if (probe.version !== PINS.pi || required.some(name => !probe.commands.includes(name))) fail('installed CLI/extension verification failed');
        this.writeJournal('committed', 'validate');
        console.log('Pinned matrix installed and real loader verified. Backup retained.');
      } catch (error) {
        try { await this.recover(); } catch (recoveryError) { throw new AggregateError([error, recoveryError], 'Installation failed; recovery failed; evidence retained'); }
        throw error;
      }
    } finally { this.unlock(); }
  }
  async isCurrent(classifier) {
    const c = this.c;
    const settings = readObject(c.slots.settings);
    const plan = settingsPlan(settings);
    if (plan.remove.length || !desired().every(s => (settings.packages || []).some(e => (typeof e === 'string' ? e : e.source) === s))) return false;
    for (const [name, version] of [['@narumitw/pi-btw', PINS.btw], ['pi-advisor-flow', PINS.advisor]]) {
      const p = path.join(c.agent, 'npm/node_modules', name, 'package.json');
      if (!exists(p) || JSON.parse(fs.readFileSync(p)).version !== version) return false;
    }
    for (const [name, sha] of [['classifier-model.ts', hash(classifier)], ['minimal-mode.ts', PINS.minimalSha256]]) {
      const p = path.join(c.slots.extensions, name);
      if (!exists(p) || hash(fs.readFileSync(p)) !== sha) return false;
    }
    if (readObject(c.slots.keybindings)['app.thinking.cycle'] !== 'ctrl+shift+tab') return false;
    await this.verifySource(path.join(c.agent, 'git/github.com/GeorgeDong32/pi-permission-modes'));
    const probe = await this.probe();
    return probe.version === PINS.pi && ['mode', 'btw', 'advisor', 'advisor-models', 'classifier-model'].every(x => probe.commands.includes(x));
  }
}

export async function main(classifier, args = process.argv.slice(2)) {
  const c = context();
  const tx = new Transaction(c);
  const detachSignals = attachSignals(tx);
  try {
    tx.boundary();
    // Recovery needs neither npm, curl, GitHub nor parseable live settings.
    if (exists(c.journal)) {
      const j = tx.validate();
      if (['active', 'recovering'].includes(j.status) || args.includes('--recover')) {
        tx.lock();
        try { if (j.status !== 'committed') await tx.recover(); }
        finally { tx.unlock(); }
        console.log('Recovery complete; installation was not resumed.'); return;
      }
    } else if (args.includes('--recover')) fail('no recovery journal');
    if (args.length) fail('usage: install.sh [--recover]');
    const [major, minor] = process.versions.node.split('.').map(Number);
    if (major < 22 || (major === 22 && minor < 19)) fail('Node >=22.19.0 required');
    await tx.install(classifier);
  } finally { detachSignals(); }
}
export function attachSignals(tx) {
  const signals = new Map(['SIGINT', 'SIGTERM'].map(signal => [signal, () => {
    tx.signal = signal;
    // Kill the whole child group, then await its close before restoring. A
    // second signal during restoration leaves the backup available for retry.
    if (tx.child) { try { process.kill(-tx.child.pid, 'SIGKILL'); } catch {} }
  }]));
  for (const [signal, handler] of signals) process.on(signal, handler);
  return () => { for (const [signal, handler] of signals) process.off(signal, handler); };
}

// The generated self-contained installer supplies the classifier source.
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main(fs.readFileSync(new URL('../extensions/classifier-model.ts', import.meta.url), 'utf8')).catch(error => {
    console.error(error); process.exitCode = 1;
  });
}
