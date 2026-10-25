import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

// Run in a verified scratch child, with real Pi's loader and ModelRuntime.
export async function classifierAcceptance(c, oldPM, record) {
  assert.ok(c.home.startsWith(path.dirname(process.env.TMPDIR) + '/'));
  const load = rel => import(pathToFileURL(path.join(c.cli, rel)));
  const { loadExtensions, createExtensionRuntime } = await load('dist/core/extensions/loader.js');
  const { ModelRuntime } = await load('dist/core/model-runtime.js');
  const { ModelRegistry } = await load('dist/core/model-registry.js');
  const api = await load('node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js');
  const requests = []; let response = 'allow';
  const server = http.createServer(async (req, res) => {
    let body = ''; for await (const b of req) body += b;
    requests.push({ route: req.url, auth: req.headers.authorization, body: JSON.parse(body) });
    if (req.url.startsWith('/catalog/')) { res.writeHead(400); res.end('catalog tripwire'); return; }
    if (response === 'timeout') return;
    if (response === 'http-error') { res.writeHead(503); res.end('fixture unavailable'); return; }
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    if (response === 'malformed') { res.end('data: {broken\n\ndata: [DONE]\n\n'); return; }
    if (response === 'empty') { res.end('data: [DONE]\n\n'); return; }
    const delta = { tool_calls: [{ index: 0, id: 'call_fixture', type: 'function', function: { name: 'classify_result', arguments: JSON.stringify({ thinking: 'fixture', shouldBlock: response === 'deny', reason: 'fixture ' + response }) } }] };
    res.write('data: ' + JSON.stringify({ id: 'fixture', object: 'chat.completion.chunk', choices: [{ index: 0, delta, finish_reason: null }] }) + '\n\n');
    res.end('data: ' + JSON.stringify({ id: 'fixture', choices: [{ index: 0, delta: {}, finish_reason: 'tool_calls' }] }) + '\n\ndata: [DONE]\n\n');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + server.address().port;
  const model = { id: 'classifier', name: 'fixture', provider: 'fixture', api: 'openai-completions', baseUrl: base + '/catalog',
    reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 8192, maxTokens: 1024 };
  const credentials = { read: async () => undefined, list: async () => [], modify: async (_id, fn) => fn(undefined), delete: async () => {} };
  const runtime = await ModelRuntime.create({ credentials, modelsPath: null, refreshOnCreate: false, allowModelNetwork: false });
  runtime.registerNativeProvider({ id: 'fixture', name: 'fixture', baseUrl: model.baseUrl,
    auth: { apiKey: { name: 'fixture auth', resolve: async () => ({ auth: { apiKey: 'scratch-only-key', baseUrl: base + '/resolved' } }) } },
    getModels: () => [model], stream: api.stream, streamSimple: api.streamSimple });
  const registry = new ModelRegistry(runtime);
  const pm = path.join(c.agent, 'git/github.com/GeorgeDong32/pi-permission-modes');
  const evidence = path.join(c.home, 'test-evidence'); fs.mkdirSync(evidence, { recursive: true });
  const bridge = async (source, label) => {
    const file = path.join(evidence, 'bridge-' + label + '.ts');
    fs.writeFileSync(file, `import * as client from ${JSON.stringify(path.join(source, 'classifier-client.ts'))};\nexport default pi=>pi.registerCommand('probe',{handler:async opts=>opts==='invalidate'?client.invalidateClassifierVerdictCache?.():client.classifyToolCall(opts)});\n`);
    const result = await loadExtensions([file], c.agent);
    assert.deepEqual(result.errors, []);
    return result.extensions[0].commands.get('probe').handler;
  };
  const current = await bridge(pm, 'current'), old = await bridge(oldPM, 'old');
  let nonce = 0;
  const options = () => ({ modelRef: 'fixture/classifier', registry, timeoutMs: 200, stage: 'tool',
    session: { cwd: c.agent, mode: 'auto', branch: [], agentsMd: null }, pendingTool: { name: 'bash', input: { command: 'curl https://example.invalid/' + (++nonce) } } });
  try {
    assert.equal(registry.find('fixture', 'classifier').baseUrl, base + '/catalog');
    assert.equal((await registry.getApiKeyAndHeaders(model)).baseUrl, base + '/resolved');
    await assert.rejects(() => old(options())); assert.ok(requests.at(-1).route.startsWith('/catalog/'));
    record('permission-modes 2.7.0 resolved-baseUrl regression reproduced');
    for (const value of ['allow', 'deny']) {
      response = value; const before = requests.length, result = await current(options());
      assert.equal(result.allow, value === 'allow'); assert.equal(requests.length - before, 1);
      assert.ok(requests.at(-1).route.startsWith('/resolved/')); assert.equal(requests.at(-1).auth, 'Bearer scratch-only-key');
      assert.equal(requests.at(-1).body.tool_choice.function.name, 'classify_result');
      record('2.8.0 real registry custom-baseUrl ' + value);
    }
    for (const value of ['malformed', 'empty', 'timeout', 'http-error']) {
      response = value; const before = requests.length, start = Date.now();
      await assert.rejects(() => current(options()));
      assert.equal(requests.length - before, 1); assert.ok(Date.now() - start < 3000);
      record('classifier ' + value + ' fails closed without SDK retries');
    }
    fs.writeFileSync(path.join(c.agent, 'permission-modes.json'), JSON.stringify({ classifier: { enabled: true, model: 'fixture/classifier', timeoutMs: 200, stage: 'tool' } }));
    const extensionRuntime = createExtensionRuntime();
    let tools = ['read', 'bash', 'edit', 'write'];
    Object.assign(extensionRuntime, { appendEntry() {}, getActiveTools: () => tools, getAllTools: () => [], setActiveTools: value => { tools = value; }, getSettings: () => ({}), sendMessage() {}, getThinkingLevel: () => 'off' });
    const loaded = await loadExtensions([path.join(pm, 'index.ts')], c.agent, undefined, extensionRuntime);
    assert.deepEqual(loaded.errors, []); const extension = loaded.extensions[0];
    const ctx = { cwd: c.agent, hasUI: false, modelRegistry: registry, signal: new AbortController().signal,
      sessionManager: { getBranch: () => [], getEntries: () => [], getSessionId: () => 'fixture' }, ui: { notify() {} } };
    const mode = value => extension.commands.get('mode').handler(value, ctx);
    const call = async (name, input) => {
      for (const handler of extension.handlers.get('tool_call') || []) {
        const result = await handler({ toolName: name, toolCallId: 'fixture-' + (++nonce), input }, ctx);
        if (result?.block) return result;
      }
      return undefined;
    };
    await mode('auto');
    for (const value of ['allow', 'deny', 'malformed', 'empty', 'timeout', 'http-error']) {
      response = value; await current('invalidate');
      const before = requests.length;
      const result = await call('bash', { command: 'curl https://example.invalid/gate-' + (++nonce) });
      assert.equal(Boolean(result?.block), value !== 'allow');
      assert.equal(requests.length - before, ['allow', 'deny'].includes(value) ? 1 : 3);
      record('real loaded Auto gate ' + value + ' and bounded attempts');
    }
    const marker = path.join(c.home, 'SHOULD_NOT_EXIST');
    for (const value of ['ask', 'plan', 'auto']) {
      await mode(value);
      for (const [name, input] of [
        ['bash', { command: 'rm -rf /; touch ' + marker }],
        ['powershell', { command: 'Remove-Item -Recurse -Force C:\\; touch ' + marker }],
        ['fusion', { then_run: 'rm -rf /; touch ' + marker }],
        ['write', { path: path.join(c.home, 'outside-cwd'), content: 'blocked' }],
      ]) {
        const result = await call(name, input);
        if (!result?.block) {
          // Observe an actual filesystem effect if the gate accidentally grants.
          fs.writeFileSync(marker, 'unsafe grant');
          if (name === 'write') fs.writeFileSync(input.path, input.content);
        }
        assert.equal(fs.existsSync(marker), false, value + '/' + name);
        assert.equal(fs.existsSync(path.join(c.home, 'outside-cwd')), false);
      }
      record('real ' + value + ' dangerous Bash/PowerShell/embedded/outside-cwd write gates');
    }
    await mode('ask'); assert.equal((await call('read', { path: path.join(c.agent, 'safe.txt') }))?.block, undefined);
    record('Ask read-only action remains available');
    fs.writeFileSync(path.join(evidence, 'classifier-requests.json'), JSON.stringify(requests, null, 2) + '\n');
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}

if (process.argv[2] === '--run') {
  const { context } = await import('./bootstrap.mjs');
  await classifierAcceptance(context(), process.argv[3], name => console.log('PASS ' + name));
}
