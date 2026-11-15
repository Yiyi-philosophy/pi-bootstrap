import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { context } from './bootstrap.mjs';
import { verifyScratchEnvironment } from './test-support.mjs';

// Real published extension entrypoints and Pi loader/runtime; a controlled UI
// selects models and closes dialogs. Fullscreen terminal forwarding is separate.
verifyScratchEnvironment();
const c = context();
fs.rmSync(path.join(c.agent, 'advisor.json'), { force: true });
const load = rel => import(pathToFileURL(path.join(c.cli, rel)));
const { loadExtensions, createExtensionRuntime } = await load('dist/core/extensions/loader.js');
const { ModelRuntime } = await load('dist/core/model-runtime.js');
const { ModelRegistry } = await load('dist/core/model-registry.js');
const api = await load('node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js');
const { TuiMainScreen } = await load('node_modules/@earendil-works/pi-tui/dist/index.js');
const { KeybindingsManager } = await load('dist/core/keybindings.js');
const themeModule = await load('dist/modes/interactive/theme/theme.js');
themeModule.initTheme('dark', false);
const record = name => console.log('PASS ' + name);
const configPath = path.join(c.agent, 'permission-modes.json');
const notifications = [];
let selection, reloads = 0;
const runtime = createExtensionRuntime();
let activeTools = ['read', 'bash', 'edit', 'write', 'ask_advisor'];
Object.assign(runtime, {
  getActiveTools: () => activeTools, setActiveTools: value => { activeTools = value; },
  getAllTools: () => [], getSettings: () => ({}), getThinkingLevel: () => 'off',
  setThinkingLevel() {}, appendEntry() {}, sendMessage() {}, setModel: async () => true,
});
const keybindings = new KeybindingsManager();
const terminal = { columns: 110, rows: 36, write() {}, start() {}, stop() {}, hideCursor() {}, showCursor() {} };
const tui = new TuiMainScreen(terminal);
let customKeys = [];
const ui = {
  notify: (message, level) => notifications.push({ message, level }),
  select: async (title, labels) => selection ? selection(title, labels) : labels[0],
  setStatus() {}, setWidget() {}, setEditorText() {}, getEditorText: () => '',
  custom: async factory => {
    const keys = customKeys.shift();
    return new Promise((resolve, reject) => {
      let component;
      const timer = setTimeout(() => { const name = component?.constructor.name; component?.dispose?.(); reject(Error('controlled UI timed out: ' + name)); }, 10000);
      const done = value => { clearTimeout(timer); queueMicrotask(() => { component?.dispose?.(); resolve(value); }); };
      Promise.resolve(factory(tui, themeModule.theme, keybindings, done)).then(value => {
        component = value;
        assert.ok(component.render(100).length);
        for (const key of keys || []) component.handleInput(key);
      }).catch(error => { clearTimeout(timer); component?.dispose?.(); reject(error); });
    });
  },
};
const sessionManager = {
  getSessionId: () => 'scratch-command-session', getBranch: () => [], getEntries: () => [],
  getLeafId: () => null, getSessionFile: () => undefined, getHeader: () => ({ cwd: c.home }),
  buildSessionContext: () => ({ messages: [], thinkingLevel: 'off', model: undefined }),
  buildContextEntries: () => [], getLabels: () => new Map(),
};
const ctx = {
  cwd: c.home, hasUI: true, mode: 'tui', ui, sessionManager,
  signal: new AbortController().signal, isProjectTrusted: () => false,
  isIdle: () => true, getSystemPrompt: () => '', getContextUsage: () => undefined,
  reload: async () => { reloads++; },
};
const classifier = await loadExtensions([path.join(c.agent, 'extensions/classifier-model.ts')], c.home, undefined, runtime);
assert.deepEqual(classifier.errors, []);
const chooseClassifier = classifier.extensions[0].commands.get('classifier-model').handler;
const model = { provider: 'fixture', id: 'advisor', name: 'fixture', api: 'openai-completions',
  reasoning: false, input: ['text'], contextWindow: 8192, maxTokens: 1024,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
ctx.modelRegistry = { refresh: async () => {}, getAvailable: () => [model] };
const readConfig = () => JSON.parse(fs.readFileSync(configPath));
fs.writeFileSync(configPath, JSON.stringify({ permissions: { deny: ['Bash(rm *)'] }, custom: 42,
  classifier: { enabled: true, model: 'old/model', timeoutMs: 1234, stage: 'tool' } }));
selection = (_title, labels) => labels[0];
await chooseClassifier('', ctx);
assert.deepEqual(readConfig(), { permissions: { deny: ['Bash(rm *)'] }, custom: 42,
  classifier: { enabled: true, model: 'fixture/advisor', timeoutMs: 1234, stage: 'tool' } });
selection = (_title, labels) => labels.at(-1);
await chooseClassifier('', ctx);
assert.equal(readConfig().classifier.enabled, false);
assert.equal(readConfig().classifier.model, 'fixture/advisor');
assert.equal(readConfig().classifier.timeoutMs, 1234);
assert.equal(reloads, 2);
record('classifier selector merges, disables, preserves timeout/rules and invokes reload');
for (const invalid of ['{broken', '[]', 'null']) {
  fs.writeFileSync(configPath, invalid); await chooseClassifier('', ctx);
  assert.equal(fs.readFileSync(configPath, 'utf8'), invalid);
}
fs.writeFileSync(configPath, '{}'); selection = (_title, labels) => labels[0];
await chooseClassifier('', ctx); assert.equal(readConfig().classifier.timeoutMs, 60000);
const before = fs.readFileSync(configPath);
const now = Date.now; Date.now = () => 123456789;
const blockedTemp = `${configPath}.tmp-${process.pid}-123456789`;
fs.mkdirSync(blockedTemp);
try { await chooseClassifier('', ctx); assert.ok(fs.readFileSync(configPath).equals(before)); }
finally { Date.now = now; fs.rmdirSync(blockedTemp); }
assert.ok(notifications.some(n => n.level === 'error' && n.message.includes('Could not write')));
record('classifier rejects invalid JSON, defaults timeout and preserves original on atomic-write failure');

const requests = [];
let authEnabled = true;
const server = http.createServer(async (req, res) => {
  let text = ''; for await (const chunk of req) text += chunk;
  requests.push({ route: req.url, headers: req.headers, body: JSON.parse(text) });
  assert.ok(req.url.startsWith('/resolved/'), 'catalog baseUrl must not receive requests');
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  const chunk = delta => 'data: ' + JSON.stringify({ id: 'fixture', object: 'chat.completion.chunk',
    model: 'advisor', choices: [{ index: 0, delta, finish_reason: null }] }) + '\n\n';
  res.write(chunk({ role: 'assistant', content: 'SCRATCH_ADVICE_OK' }));
  res.end('data: ' + JSON.stringify({ id: 'fixture', choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] }) + '\n\ndata: [DONE]\n\n');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  const base = 'http://127.0.0.1:' + server.address().port;
  model.baseUrl = base + '/catalog';
  const credentials = { read: async id => id === 'fixture' && authEnabled ? { type: 'api_key', key: 'scratch-only-key' } : undefined, list: async () => authEnabled ? [{ providerId: 'fixture', type: 'api_key' }] : [], modify: async (_id, fn) => fn(undefined), delete: async () => {} };
  const modelRuntime = await ModelRuntime.create({ credentials, modelsPath: null, refreshOnCreate: false, allowModelNetwork: false });
  modelRuntime.registerNativeProvider({ id: 'fixture', name: 'fixture', baseUrl: model.baseUrl,
    auth: { apiKey: { name: 'fixture', resolve: async () => authEnabled
      ? { auth: { apiKey: 'scratch-only-key', baseUrl: base + '/resolved' } } : undefined } },
    getModels: () => [model], stream: api.stream, streamSimple: api.streamSimple });
  await modelRuntime.refresh({ allowNetwork: false });
  await modelRuntime.getAvailable();
  assert.equal(modelRuntime.getAvailableSnapshot().length, 1);
  ctx.modelRegistry = new ModelRegistry(modelRuntime);
  ctx.model = { ...model, id: 'executor' };
  const advisor = await loadExtensions([path.join(c.agent, 'npm/node_modules/pi-advisor-flow/dist/index.js')], c.home, undefined, runtime);
  assert.deepEqual(advisor.errors, []);
  const extension = advisor.extensions[0];
  selection = (_title, labels) => labels[0];
  customKeys = [['\r'], ['fixture/advisor', '\r'], ['\r']];
  await extension.commands.get('advisor-models').handler('', ctx);
  const advisorPath = path.join(c.agent, 'advisor.json');
  assert.ok(fs.existsSync(advisorPath), JSON.stringify(notifications));
  assert.equal(JSON.parse(fs.readFileSync(advisorPath)).advisor, 'fixture/advisor');
  assert.equal(JSON.parse(fs.readFileSync(advisorPath)).executor, undefined);
  assert.equal(customKeys.length, 0);
  record('advisor-models renders real selectors and saves chosen Advisor with current-session Executor');
  const cfg = JSON.parse(fs.readFileSync(advisorPath));
  fs.writeFileSync(advisorPath, JSON.stringify({ ...cfg, simpleMode: true, advisorHerdrIntegration: false, advisorScoutEnabled: false }));
  await extension.commands.get('advisor').handler('', ctx);
  const ask = extension.tools.get('ask_advisor')?.definition;
  assert.ok(ask, 'ask_advisor registered');
  const result = await ask.execute('scratch-advice', { question: 'Check the scratch fixture only.' }, ctx.signal, () => {}, ctx);
  assert.match(JSON.stringify(result), /SCRATCH_ADVICE_OK/);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].headers.authorization, 'Bearer scratch-only-key');
  assert.equal(requests[0].body.model, 'advisor');
  record('advisor activation and ask_advisor complete through real registry and loopback HTTP');
  authEnabled = false;
  await assert.rejects(() => ask.execute('scratch-no-auth', { question: 'No credentials test.' }, ctx.signal, () => {}, ctx), /Provider is not configured: fixture/);
  assert.equal(requests.length, 1);
  authEnabled = true;
  record('advisor missing-credential error makes no HTTP request');

  // Keep the published command and request implementation; bypass only the
  // fullscreen terminal handoff, whose physical behavior is not certified.
  const bridge = path.join(c.home, 'btw-command-bridge.ts');
  fs.writeFileSync(bridge, `import btw from ${JSON.stringify(path.join(c.agent, 'npm/node_modules/@narumitw/pi-btw/dist/index.ts'))};\nexport default pi => btw(pi, { runFullscreen: (ctx, run) => run(ctx) });\n`);
  const btw = await loadExtensions([bridge], c.home, undefined, runtime);
  assert.deepEqual(btw.errors, []);
  // First dialog waits for the answer, second closes the retained side thread.
  customKeys = [[], ['\u0003']];
  await btw.extensions[0].commands.get('btw').handler('Reply with the scratch marker.', { ...ctx, model });
  assert.equal(customKeys.length, 0);
  assert.equal(requests.length, 2);
  assert.equal(requests[1].body.model, 'advisor');
  assert.ok(requests[1].body.messages.some(m => JSON.stringify(m.content).includes('scratch marker')));
  assert.equal(requests[1].body.tools, undefined);
  assert.ok(!notifications.some(n => n.level === 'error' && n.message.startsWith('Pi BTW:')));
  record('btw command renders answer/composer, completes a tools-free side request and closes');
  for (const handler of btw.extensions[0].handlers.get('session_shutdown') || []) await handler({ reason: 'quit' }, ctx);
  fs.mkdirSync(path.join(c.home, 'test-evidence'), { recursive: true });
  fs.writeFileSync(path.join(c.home, 'test-evidence/command-requests.json'), JSON.stringify(requests, null, 2) + '\n');
} finally {
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
  themeModule.stopThemeWatcher();
}
