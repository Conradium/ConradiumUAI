'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const childProcess = require('node:child_process');
const { createClaudeCode, findBinary, official, promptFor, toolDefinitions, childEnv } = require('../claudecode');
const { createInference } = require('../inference');
const { startBridge, sleep } = require('./helpers/bridge');

const fixture = path.join(__dirname, 'fixtures', 'claude-cli.js');
const url = 'https://claude-code.invalid/v1/chat/completions';
const local = { local: true };
const tools = [{ type: 'function', function: { name: 'lookup', description: 'Look up a Roblox value',
  parameters: { type: 'object', properties: { value: { type: 'string' } } } } }];
const body = (text, extra = {}) => JSON.stringify({ model: 'sonnet', messages: [{ role: 'system', content: 'Host rules.' },
  { role: 'user', content: text }], ...extra });

function claude(t, extra = {}, options = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-claude-fixture-'));
  const log = path.join(directory, 'events.jsonl');
  const env = { ...process.env, UAI_CLAUDE_FIXTURE_LOG: log, ANTHROPIC_BASE_URL: 'https://stray.invalid', anthropic_custom_headers: 'x-stray: 1', ...extra };
  const backend = createClaudeCode({ env, binary: { command: process.execPath, prefixArgs: [fixture] }, ...options });
  t.after(async () => { await backend.close(); fs.rmSync(directory, { recursive: true, force: true }); });
  const events = () => fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
  return { backend, events };
}
const until = async (check, ms = 5000) => {
  for (let waited = 0; waited < ms; waited += 10) { const value = check(); if (value) return value; await sleep(10); }
  throw Error('Timed out waiting for the fixture');
};
const running = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
function raw(target, { method = 'POST', headers = {}, payload } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(target, { method, headers: { 'content-type': 'application/json', ...headers } }, res => {
      let text = ''; res.on('data', chunk => text += chunk); res.on('end', () => resolve({ status: res.statusCode, text }));
    });
    req.on('error', reject); req.end(payload === undefined ? undefined : JSON.stringify(payload));
  });
}
const flagValue = (args, flag) => args[args.indexOf(flag) + 1];

test('discovery honours overrides, prefers native binaries and resolves npm shims without a shell', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-claude-discovery-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const win = process.platform === 'win32', exe = win ? 'claude.exe' : 'claude';
  const nativeCopy = target => { fs.mkdirSync(path.dirname(target), { recursive: true }); try { fs.linkSync(process.execPath, target); } catch { fs.copyFileSync(process.execPath, target); } };
  assert.equal(findBinary({ UAI_CLAUDE_DISABLED: '1', UAI_CLAUDE_BINARY: process.execPath }), null);
  assert.deepEqual(findBinary({ UAI_CLAUDE_BINARY: process.execPath }), { command: fs.realpathSync(process.execPath), prefixArgs: [] });
  assert.equal(findBinary({ UAI_CLAUDE_BINARY: 'relative' + exe }), null);
  assert.equal(findBinary({ UAI_CLAUDE_BINARY: path.join(root, 'missing', exe) }), null);
  assert.equal(findBinary({ PATH: path.join(root, 'nothing'), USERPROFILE: path.join(root, 'nobody'), HOME: path.join(root, 'nobody') }), null);

  // An npm shim is never run. Only its package's entry is.
  const npm = path.join(root, 'npm');
  fs.mkdirSync(npm);
  if (win) { fs.writeFileSync(path.join(npm, 'claude.cmd'), '@node "%~dp0\\node_modules\\@anthropic-ai\\claude-code\\cli.js" %*\r\n'); fs.writeFileSync(path.join(npm, 'claude.ps1'), '# shim\n'); }
  else { fs.writeFileSync(path.join(npm, 'claude'), '#!/bin/sh\nexec node cli.js "$@"\n', { mode: 0o755 }); }
  const isolated = { PATH: npm, USERPROFILE: path.join(root, 'nobody'), HOME: path.join(root, 'nobody') };
  assert.equal(findBinary(isolated), null, 'a shim without its package is refused');
  assert.equal(findBinary({ UAI_CLAUDE_BINARY: path.join(npm, win ? 'claude.cmd' : 'claude') }), null, 'a shim override is refused');
  const pkg = path.join(npm, 'node_modules', '@anthropic-ai', 'claude-code');
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({ name: '@anthropic-ai/claude-code', bin: { claude: 'cli.js' } }));
  fs.writeFileSync(path.join(pkg, 'cli.js'), '// fixture entry\n');
  assert.deepEqual(findBinary(isolated), { command: process.execPath, prefixArgs: [fs.realpathSync(path.join(pkg, 'cli.js'))] });
  fs.writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({ name: '@anthropic-ai/claude-code', bin: { claude: 'bin/' + exe } }));
  nativeCopy(path.join(pkg, 'bin', exe));
  assert.deepEqual(findBinary(isolated), { command: fs.realpathSync(path.join(pkg, 'bin', exe)), prefixArgs: [] }, 'a shipped native binary wins');
  fs.writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({ name: 'not-claude-code', bin: { claude: 'cli.js' } }));
  fs.rmSync(path.join(pkg, 'bin'), { recursive: true, force: true });
  assert.equal(findBinary(isolated), null, 'only the official package name qualifies');

  // The native installer location comes first.
  const home = path.join(root, 'home');
  nativeCopy(path.join(home, '.local', 'bin', exe));
  assert.deepEqual(findBinary({ PATH: npm, USERPROFILE: home, HOME: home }), { command: fs.realpathSync(path.join(home, '.local', 'bin', exe)), prefixArgs: [] });

  // Every process the adapter starts is spawned directly.
  const calls = [], original = childProcess.spawn;
  childProcess.spawn = (...args) => { calls.push(args); return original.apply(childProcess, args); };
  t.after(() => { childProcess.spawn = original; });
  const { backend } = claude(t);
  await backend.request({ body: body('SCENARIO:text'), url, source: local });
  childProcess.spawn = original;
  assert.equal(calls.length, 4, '--version, --help, auth status and one run');
  for (const [command, , options] of calls) {
    assert.equal(options.shell, false); assert.equal(options.windowsHide, true);
    assert.doesNotMatch(command, /\.(?:cmd|bat|ps1)$/i);
  }
});

test('a signed-out CLI is reported, never accepted and never run', async t => {
  const { backend, events } = claude(t, { UAI_CLAUDE_FIXTURE_AUTH: 'out' });
  assert.equal(backend.capability().state, 'starting');
  await backend.start();
  const capability = backend.capability();
  assert.equal(capability.state, 'signed-out'); assert.equal(capability.available, true);
  assert.match(capability.message, /Run `claude` in a terminal and sign in, then restart Cowork\./);
  assert.equal(backend.accepts(url, body('hello'), local), false);
  assert.deepEqual(backend.refusal(url, body('hello'), local).status, 409);
  await assert.rejects(backend.request({ body: body('hello'), url, source: local }), /sign in, then restart Cowork/);
  await assert.rejects(backend.models(), /sign in/);
  assert.equal(events().filter(event => event.type === 'run').length, 0);
});

test('signed-in startup keeps only display labels and checks the installed flags', async t => {
  const { backend } = claude(t);
  await backend.start();
  const capability = backend.capability();
  assert.deepEqual(capability, { schema: 1, available: true, state: 'ready', models: '/api/claudecode/models',
    aliases: ['sonnet', 'opus', 'haiku', 'fable'], version: '2.1.301', authMethod: 'claude.ai', apiProvider: 'firstParty' });
  assert.doesNotMatch(JSON.stringify(capability), /fixture@example|Fixture org|org-fixture|max/);
  const models = await backend.models();
  assert.deepEqual(models.data.map(row => [row.id, row.owned_by]), [['sonnet', 'claude-code'], ['opus', 'claude-code'], ['haiku', 'claude-code'], ['fable', 'claude-code']]);
  assert.equal(backend.accepts(url, body('x'), local), true);
  assert.equal(backend.accepts(url, JSON.stringify({ model: 'claude-opus-5-5', messages: [] }), local), true, 'full model IDs are accepted');
  assert.equal(backend.accepts(url, JSON.stringify({ model: '--bare', messages: [] }), local), false);
  assert.equal(backend.accepts(url, body('x'), {}), false);

  // A CLI that prints its help but is slow to exit still answered.
  const slow = claude(t, { UAI_CLAUDE_FIXTURE_SLOW_EXIT: '9000' }, { probeMs: 4000 }).backend;
  await slow.start();
  assert.equal(slow.capability().state, 'ready');

  // A startup that failed once is retried without restarting the bridge.
  const marker = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'uai-claude-retry-')), 'help-failed');
  t.after(() => fs.rmSync(path.dirname(marker), { recursive: true, force: true }));
  const flaky = claude(t, { UAI_CLAUDE_FIXTURE_HELP_FAILS_ONCE: marker }, { retryMs: 50 }).backend;
  await flaky.start();
  assert.equal(flaky.capability().state, 'failed');
  assert.match(flaky.capability().message, /did not answer --help in time\. It retries shortly/);
  await sleep(60);
  assert.equal(flaky.capability().state, 'starting', 'reading the capability retries a due failure');
  await flaky.start();
  assert.equal(flaky.capability().state, 'ready');

  const outdated = claude(t, { UAI_CLAUDE_FIXTURE_OMIT_FLAG: '--include-partial-messages' }).backend;
  await outdated.start();
  assert.equal(outdated.capability().state, 'failed');
  assert.match(outdated.capability().message, /lacks --include-partial-messages\. Update Claude Code/);
  assert.equal(outdated.accepts(url, body('x'), local), false);
});

test('each run uses the verified flags, an empty working folder and the user own environment', async t => {
  const { backend, events } = claude(t);
  const opened = [], spied = ['openSync', 'readFileSync', 'readFile', 'createReadStream', 'copyFileSync', 'renameSync', 'cpSync'];
  const originals = Object.fromEntries(spied.map(name => [name, fs[name]]));
  const originalPromises = { readFile: fs.promises.readFile, open: fs.promises.open };
  for (const name of spied) fs[name] = function (target, ...rest) { opened.push(String(target)); return originals[name].call(this, target, ...rest); };
  fs.promises.readFile = (target, ...rest) => { opened.push(String(target)); return originalPromises.readFile(target, ...rest); };
  fs.promises.open = (target, ...rest) => { opened.push(String(target)); return originalPromises.open(target, ...rest); };
  const restore = () => { Object.assign(fs, originals); Object.assign(fs.promises, originalPromises); };
  t.after(restore);
  await backend.request({ body: body('SCENARIO:text', { reasoning_effort: 'high', tools }), url, source: local });
  restore();
  const userClaude = path.join(os.homedir(), '.claude').toLowerCase();
  assert.ok(opened.every(item => !item.toLowerCase().startsWith(userClaude) && !/credentials\.json/i.test(item)), 'no file under ~/.claude is opened');

  const run = events().find(event => event.type === 'run'), args = run.args;
  for (const flag of ['-p', '--verbose', '--include-partial-messages', '--strict-mcp-config', '--disable-slash-commands', '--no-session-persistence']) assert.ok(args.includes(flag), flag);
  assert.equal(flagValue(args, '--input-format'), 'stream-json'); assert.equal(flagValue(args, '--output-format'), 'stream-json');
  assert.equal(flagValue(args, '--tools'), '');
  assert.equal(flagValue(args, '--allowedTools'), 'mcp__uai__*');
  assert.equal(flagValue(args, '--permission-mode'), 'dontAsk'); assert.equal(flagValue(args, '--permission-prompts'), 'none');
  assert.deepEqual(JSON.parse(flagValue(args, '--settings')), { disableAllHooks: true });
  assert.equal(flagValue(args, '--model'), 'sonnet'); assert.equal(flagValue(args, '--effort'), 'high');
  assert.ok(args.includes('--system-prompt-file') && args.includes('--mcp-config'));
  assert.ok(!args.includes('--bare'), 'never --bare: it ignores subscription sign-in');
  assert.doesNotMatch(JSON.stringify(args), /Bearer|[a-f0-9]{64}/, 'the MCP secret stays out of the command line');

  assert.deepEqual(run.cwdEntries, []);
  assert.match(path.basename(path.dirname(path.dirname(run.cwd))), /^project-uai-claude-/);
  assert.equal(fs.existsSync(run.cwd), false, 'the job folder is removed');
  assert.equal(run.env.HOME, process.env.HOME); assert.equal(run.env.USERPROFILE, process.env.USERPROFILE); assert.equal(run.env.APPDATA, process.env.APPDATA);
  assert.equal(run.env.baseUrl, undefined); assert.equal(run.env.customHeaders, undefined);
  assert.equal(run.mcp.type, 'http'); assert.match(run.mcp.url, /^http:\/\/127\.0\.0\.1:\d+\/mcp\/[a-f0-9]{32}$/);
  assert.match(run.mcp.authorization, /^Bearer [a-f0-9]{64}$/);

  assert.match(run.system, /^Host rules\.\n\nYou are Project UAI, acting in Roblox through the uai tools only\./);
  assert.match(run.system, /Never invent results\./);
  const text = run.user.message.content[0].text;
  assert.equal(run.user.type, 'user'); assert.equal(run.user.message.role, 'user');
  assert.ok(text.startsWith('Conversation to continue:\n'));
  assert.deepEqual(JSON.parse(text.slice('Conversation to continue:\n'.length)), [{ role: 'user', content: 'SCENARIO:text' }]);
});

test('the MCP server admits only its own job and holds tool calls', async t => {
  const { backend, events } = claude(t);
  const controller = new AbortController();
  const pending = backend.request({ body: body('SCENARIO:hang', { tools }), url, signal: controller.signal, source: local });
  const stopped = assert.rejects(pending, /^Error: Stopped$/);
  const run = await until(() => events().find(event => event.type === 'run'));
  assert.equal(run.protocol, '2025-06-18'); assert.equal(run.notificationStatus, 202);
  assert.deepEqual(run.tools, [{ name: 'lookup', description: 'Look up a Roblox value', inputSchema: { type: 'object', properties: { value: { type: 'string' } } } }]);
  const auth = { authorization: run.mcp.authorization };
  const list = { jsonrpc: '2.0', id: 1, method: 'tools/list' };
  assert.equal((await raw(run.mcp.url, { headers: { authorization: 'Bearer ' + '0'.repeat(64) }, payload: list })).status, 403);
  assert.equal((await raw(run.mcp.url, { headers: { ...auth, origin: 'http://127.0.0.1' }, payload: list })).status, 403);
  assert.equal((await raw(run.mcp.url.replace(/[a-f0-9]{32}$/, '0'.repeat(32)), { headers: auth, payload: list })).status, 403);
  assert.equal((await raw(run.mcp.url, { method: 'GET', headers: auth })).status, 405);
  assert.equal((await raw(run.mcp.url, { method: 'DELETE', headers: auth })).status, 405);
  assert.deepEqual(JSON.parse((await raw(run.mcp.url, { headers: auth, payload: list })).text).result.tools, run.tools);
  const version = async asked => JSON.parse((await raw(run.mcp.url, { headers: auth, payload: { jsonrpc: '2.0', id: 2, method: 'initialize', params: { protocolVersion: asked } } })).text).result.protocolVersion;
  assert.equal(await version('2025-03-26'), '2025-03-26'); assert.equal(await version('2099-01-01'), '2025-06-18');
  let answered = false;
  const held = raw(run.mcp.url, { headers: auth, payload: { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'lookup', arguments: { value: 'x' } } } })
    .then(() => { answered = true; }, error => error);
  await sleep(200);
  assert.equal(answered, false, 'the tool result is left to Roblox');
  controller.abort();
  await stopped;
  assert.ok((await held) instanceof Error, 'the held call is destroyed, never answered');
  assert.equal(running(run.pid), false);
});

test('text and thinking stream as deltas and finish in the Chat Completions shape', async t => {
  const { backend } = claude(t);
  const frames = [];
  const reply = await backend.request({ body: body('SCENARIO:thinking'), url, source: local, onFrame: frame => frames.push(frame) });
  assert.equal(reply.status, 200); assert.equal(reply.headers['content-type'], 'application/json');
  const deltas = frames.map(frame => frame.choices[0].delta);
  assert.equal(deltas.map(delta => delta.content || '').join(''), 'PONG');
  assert.equal(deltas.map(delta => delta.reasoning_content || '').join(''), 'Checked.');
  const response = JSON.parse(reply.body);
  assert.equal(response.object, 'chat.completion'); assert.equal(response.model, 'sonnet');
  assert.deepEqual(response.choices[0], { index: 0, message: { role: 'assistant', content: 'PONG', reasoning_content: 'Checked.' }, finish_reason: 'stop' });
  assert.deepEqual(response.usage, { prompt_tokens: 115, completion_tokens: 7, total_tokens: 122, cache_creation_input_tokens: 5,
    prompt_tokens_details: { cached_tokens: 100 }, completion_tokens_details: { reasoning_tokens: 0 } });
});

test('tool calls return to Roblox at message_stop and the run ends before a second turn', async t => {
  const { backend, events } = claude(t);
  for (const [scenario, count] of [['tool', 1], ['parallel', 2]]) {
    const frames = [];
    const reply = await backend.request({ body: body('SCENARIO:' + scenario, { tools }), url, source: local, onFrame: frame => frames.push(frame) });
    const response = JSON.parse(reply.body), message = response.choices[0].message;
    assert.equal(response.choices[0].finish_reason, 'tool_calls'); assert.equal(message.content, 'Checking Roblox.');
    assert.equal(message.tool_calls.length, count);
    for (const call of message.tool_calls) {
      assert.equal(call.type, 'function'); assert.equal(call.function.name, 'lookup');
      assert.deepEqual(JSON.parse(call.function.arguments), { value: 'fixture' }); assert.match(call.id, /^call_[a-f0-9]{24}$/);
    }
    assert.deepEqual(frames.flatMap(frame => frame.choices[0].delta.tool_calls || []).map(call => call.index), [...Array(count).keys()]);
    const run = events().filter(event => event.type === 'run').at(-1);
    assert.equal(running(run.pid), false);
  }
  await sleep(1700);
  const log = events();
  assert.equal(log.filter(event => event.type === 'tools/call-sent').length, 3, 'the MCP calls reached the bridge');
  assert.equal(log.filter(event => event.type === 'tools/call-result').length, 0, 'no held call was answered');
  assert.equal(log.filter(event => event.type === 'second-turn').length, 0, 'no second model turn started');
});

test('non-UAI tools, closed tool lists and provider failures are refused without a tool call', async t => {
  const { backend } = claude(t);
  const ask = scenario => backend.request({ body: body('SCENARIO:' + scenario, { tools }), url, source: local });
  await assert.rejects(ask('host'), /requested a local desktop action \(Bash\)\. UAI runs tools only in Roblox; nothing was run\./);
  // A UAI tool this request did not offer still goes to Roblox, which applies
  // its own registry, scope and permission checks.
  const unoffered = JSON.parse((await ask('unoffered')).body).choices[0];
  assert.equal(unoffered.finish_reason, 'tool_calls'); assert.equal(unoffered.message.tool_calls[0].function.name, 'remotes_capture');
  await assert.rejects(ask('mcp-down'), /could not reach the UAI tools/);
  await assert.rejects(ask('extra-tool'), /tools other than the UAI tools/);
  await assert.rejects(ask('error'), /usage or rate limit/);
  assert.equal(backend.capability().state, 'ready');
  await assert.rejects(ask('auth-error'), /not signed in, or its sign-in expired/);
  assert.equal(backend.capability().state, 'signed-out', 'an expired sign-in stops further runs');
});

test('stop ends the run, the child and its temporary folder', async t => {
  const { backend, events } = claude(t);
  const controller = new AbortController(), frames = [];
  const pending = backend.request({ body: body('SCENARIO:hang'), url, signal: controller.signal, source: local, onFrame: frame => frames.push(frame) });
  const stopped = assert.rejects(pending, /^Error: Stopped$/);
  await until(() => frames.length);
  const run = events().find(event => event.type === 'run');
  assert.equal(running(run.pid), true);
  controller.abort(); await stopped;
  assert.equal(running(run.pid), false);
  assert.equal(fs.existsSync(path.dirname(run.cwd)), false);
  // A stopped run frees the single slot for the next request.
  const reply = await backend.request({ body: body('SCENARIO:text'), url, source: local });
  assert.equal(JSON.parse(reply.body).choices[0].message.content, 'PONG');
  const root = path.dirname(path.dirname(run.cwd));
  await backend.close();
  assert.equal(fs.existsSync(root), false, 'close removes the private root');
  await assert.rejects(backend.request({ body: body('SCENARIO:text'), url, source: local }), /Stopped/);
});

test('only one Claude Code run is active per bridge', async t => {
  const { backend, events } = claude(t, {}, { waitMs: 100 });
  const controller = new AbortController();
  const first = backend.request({ body: body('SCENARIO:hang'), url, signal: controller.signal, source: local });
  const stopped = assert.rejects(first, /Stopped/);
  await until(() => events().find(event => event.type === 'run'));
  await assert.rejects(backend.request({ body: body('SCENARIO:text'), url, source: local }), /one request at a time/);
  assert.equal(events().filter(event => event.type === 'run').length, 1);
  controller.abort(); await stopped;
});

test('inference routes the sentinel to Claude Code, OpenCode routes to OpenCode and others to HTTP', async t => {
  const { backend } = claude(t);
  await backend.start();
  const opencodeCalls = [];
  const opencode = { label: 'OpenCode', capability: () => ({ available: true }),
    accepts: target => target.startsWith('https://opencode.ai/'),
    request: async input => { opencodeCalls.push(input.url); return { status: 200, headers: {}, body: '{"choices":[]}' }; } };
  const provider = http.createServer((req, res) => { req.resume(); req.on('end', () => { res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"plain":true}'); }); });
  provider.listen(0, '127.0.0.1'); await new Promise(resolve => provider.once('listening', resolve));
  t.after(() => provider.close());
  const relay = createInference({ opencode, claudeCode: backend }); t.after(() => relay.close());
  const job = (id, target, payload) => ({ id, instance: relay.instance, url: target, headers: {}, body: payload });
  const finished = async id => { await until(() => relay.get(id).state !== 'running'); return relay.get(id); };

  relay.start(job('claude_sentinel_job', url, body('SCENARIO:text')), local);
  const claudeResult = await finished('claude_sentinel_job');
  assert.equal(claudeResult.state, 'completed', claudeResult.error);
  assert.equal(JSON.parse(claudeResult.body).choices[0].message.content, 'PONG');

  relay.start(job('opencode_route_job', 'https://opencode.ai/zen/v1/chat/completions', body('x')), local);
  assert.equal((await finished('opencode_route_job')).state, 'completed');
  assert.deepEqual(opencodeCalls, ['https://opencode.ai/zen/v1/chat/completions']);

  relay.start(job('plain_route_job', 'http://127.0.0.1:' + provider.address().port + '/v1/chat/completions', body('x')), local);
  assert.equal((await finished('plain_route_job')).body, '{"plain":true}');

  relay.start(job('claude_failure_job', url, body('SCENARIO:error')), local);
  const failed = await finished('claude_failure_job');
  assert.equal(failed.state, 'failed'); assert.match(failed.error, /usage or rate limit.*discord\.gg/);

  // Anything that is not the local game is refused before a job exists.
  for (const source of [{}, { local: false }, undefined]) {
    assert.throws(() => relay.start(job('claude_remote_job', url, body('SCENARIO:text')), source),
      error => error.status === 403 && /only the Roblox game on this computer/.test(error.message));
  }
  assert.equal(relay.get('claude_remote_job'), null);
  assert.throws(() => relay.start(job('claude_model_job', url, JSON.stringify({ model: 'gpt-5', messages: [] })), local), error => error.status === 400);
});

test('the bridge refuses Claude Code to browsers, forwarded requests and the companion relay', async t => {
  const bridge = await startBridge(t);
  const hello = await (await fetch(bridge.base + '/api/hello', { headers: { Authorization: 'Bearer ' + bridge.token } })).json();
  assert.equal(hello.capabilities.claudeCode.state, 'missing');
  assert.equal(hello.capabilities.claudeCode.available, false);
  assert.match(hello.capabilities.claudeCode.message, /Install Claude Code/);
  let next = 0;
  const submit = (headers = {}, extra = {}) => raw(bridge.base + '/api/inference', { headers: { authorization: 'Bearer ' + bridge.token, ...headers },
    payload: { id: 'claude_origin_' + (++next) + '_job', instance: hello.instance, url, headers: {}, body: body('hello'), ...extra } });
  const refused = /only the Roblox game on this computer/;
  const game = await submit();
  assert.equal(game.status, 409, 'the local game reaches the availability check'); assert.match(game.text, /Install Claude Code/);
  for (const [headers, extra] of [[{ origin: bridge.base }], [{ 'x-forwarded-for': '203.0.113.9' }], [{ forwarded: 'for=203.0.113.9' }],
    [{ 'sec-fetch-site': 'same-origin' }], [{ host: 'localhost:' + bridge.port }], [{}, { timeout: 120 }]]) {
    const response = await submit(headers, extra);
    assert.equal(response.status, 403, JSON.stringify([headers, extra])); assert.match(response.text, refused);
  }
  const models = await fetch(bridge.base + '/api/claudecode/models', { headers: { Authorization: 'Bearer ' + bridge.token } });
  assert.equal(models.status, 400); assert.match((await models.json()).error, /Install Claude Code/);
});

test('prompt, tool and environment helpers keep the contract', () => {
  for (const good of [url, 'https://CLAUDE-CODE.invalid/v1/chat/completions', 'https://claude-code.invalid:443/v1/chat/completions']) assert.equal(official(good), true, good);
  for (const bad of ['http://claude-code.invalid/v1/chat/completions', 'https://claude-code.invalid:8443/v1/chat/completions',
    'https://user:pw@claude-code.invalid/v1/chat/completions', 'https://claude-code.invalid/v1/chat/completions?x=1',
    'https://claude-code.invalid/v1/responses', 'https://claude-code.invalid.evil.test/v1/chat/completions', 'https://api.anthropic.com/v1/messages']) assert.equal(official(bad), false, bad);
  assert.throws(() => toolDefinitions({ tools: [{ type: 'function', function: { name: 'x'.repeat(55) } }] }), /at most 54/);
  assert.throws(() => toolDefinitions({ tools: [{ type: 'function', function: { name: 'a' } }, { type: 'function', function: { name: 'a' } }] }), /unique/);
  assert.deepEqual(toolDefinitions({ tools: [{ type: 'function', function: { name: 'bash' } }] }), [{ name: 'bash', description: '', inputSchema: { type: 'object', properties: {} } }]);
  const png = 'data:image/png;base64,aGVsbG8=';
  const prompt = promptFor({ messages: [{ role: 'developer', content: [{ type: 'text', text: 'Dev.' }] }, { role: 'user', content: [{ type: 'text', text: 'Look' }, { type: 'image_url', image_url: { url: png } }] },
    { role: 'assistant', content: null, tool_calls: [{ id: 'c1', type: 'function', function: { name: 'lookup', arguments: '{}' } }] }, { role: 'tool', tool_call_id: 'c1', content: 'done' }] });
  assert.match(prompt.system, /^Dev\.\n\nYou are Project UAI/);
  assert.deepEqual(prompt.content[1], { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'aGVsbG8=' } });
  const conversation = JSON.parse(prompt.content[0].text.slice('Conversation to continue:\n'.length));
  assert.equal(conversation.length, 3); assert.match(conversation[0].content[1].text, /Attached image 1/);
  assert.ok(!prompt.content[0].text.includes('aGVsbG8='));
  assert.throws(() => promptFor({ messages: [{ role: 'user', content: [{ type: 'image_url', image_url: { url: 'file:///secret.png' } }] }] }), /reattach/);
  assert.throws(() => promptFor({ messages: [{ role: 'user', content: Array(9).fill({ type: 'image_url', image_url: { url: png } }) }] }), /limit/);
  const environment = childEnv({ HOME: '/home/u', USERPROFILE: 'C:\\Users\\u', APPDATA: 'C:\\A', CLAUDE_CONFIG_DIR: '/c', ANTHROPIC_BASE_URL: 'x', Anthropic_Custom_Headers: 'y', CLAUDE_CODE_OAUTH_TOKEN: 'kept-untouched' });
  assert.deepEqual(environment, { HOME: '/home/u', USERPROFILE: 'C:\\Users\\u', APPDATA: 'C:\\A', CLAUDE_CONFIG_DIR: '/c', CLAUDE_CODE_OAUTH_TOKEN: 'kept-untouched' });
});
