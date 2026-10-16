'use strict';

// Claude Code owns its sign-in and its upstream connection. This adapter runs
// the user's own installed, unmodified `claude` binary once per request, for
// the Roblox game on this computer only, and returns UAI tool calls to Roblox
// without executing anything on the host. It never reads, copies or moves
// Claude credentials, and never redirects the child away from the user's own
// configuration: personal, local use under
// https://code.claude.com/docs/en/legal-and-compliance.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const childProcess = require('node:child_process');
const { once } = require('node:events');
const { StringDecoder } = require('node:string_decoder');
const { help } = require('./support');
const { responseBody } = require('./native-response');

const PREFIX = 'mcp__uai__';
const ALIASES = ['sonnet', 'opus', 'haiku', 'fable'];
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];
const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05'];
const MAX_LINE = 8 << 20;
const MAX_REPLY = 8 << 20;
const MAX_ARGUMENTS = 256000;
const missing = 'Install Claude Code from https://code.claude.com and sign in, then restart Cowork. Claude Code (local CLI) is for personal use on this computer; it is unavailable on mobile and through relays.';
const signedOut = 'Run `claude` in a terminal and sign in, then restart Cowork.';
const update = 'Update Claude Code (run `claude update`), then restart Cowork.';
const localOnly = 'Claude Code (local CLI) serves only the Roblox game on this computer, using your own Claude Code sign-in. It is unavailable on mobile, through the Android companion and through relays.';
const busy = 'Claude Code (local CLI) answers one request at a time. Wait for the current reply, or use another provider for parallel work such as subagents.';
const hostAction = 'Claude Code requested a local desktop action. UAI runs tools only in Roblox; nothing was run.';
// Names the refused tool, so a refusal can be diagnosed without logs.
const hostActionFor = name => typeof name === 'string' && /^[\w.:-]{1,80}$/.test(name)
  ? 'Claude Code requested a local desktop action (' + name + '). UAI runs tools only in Roblox; nothing was run.' : hostAction;
// Flags this adapter relies on. Older builds that lack one fail with a clear
// update message instead of an unexplained exit.
const FLAGS = ['--print', '--verbose', '--input-format', '--output-format', '--include-partial-messages', '--tools',
  '--mcp-config', '--strict-mcp-config', '--allowedTools', '--permission-mode', '--permission-prompts',
  '--disable-slash-commands', '--no-session-persistence', '--settings', '--system-prompt', '--model', '--effort'];
const pause = (ms, signal) => new Promise((resolve, reject) => {
  if (signal?.aborted) { reject(Error('Stopped')); return; }
  const abort = () => { clearTimeout(timer); reject(Error('Stopped')); };
  const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve(); }, ms);
  signal?.addEventListener('abort', abort, { once: true });
});

// The reserved .invalid host never resolves (RFC 2606), so a request that
// misses the bridge fails at DNS and nothing leaves the machine.
function official(url) {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && u.hostname === 'claude-code.invalid' && !u.port && !u.username && !u.password &&
      !u.search && !u.hash && u.pathname === '/v1/chat/completions';
  } catch { return false; }
}

function validModel(model) {
  return typeof model === 'string' && (ALIASES.includes(model) || /^claude-[a-z0-9][a-z0-9.-]{0,98}$/i.test(model));
}

function executable(candidate, platform) {
  try {
    if (!path.isAbsolute(candidate) || !fs.statSync(candidate).isFile()) return null;
    const real = fs.realpathSync(candidate);
    if (platform === 'win32') return real.toLowerCase().endsWith('.exe') ? real : null;
    fs.accessSync(real, fs.constants.X_OK);
    // Only ELF or Mach-O images qualify; a shell or Node shim is resolved to
    // its package instead of being run.
    const fd = fs.openSync(real, 'r'), magic = Buffer.alloc(4);
    try { fs.readSync(fd, magic, 0, 4, 0); } finally { fs.closeSync(fd); }
    const word = magic.readUInt32BE(0);
    return word === 0x7f454c46 || [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe].includes(word) ? real : null;
  } catch { return null; }
}

// An npm installation ships either a native binary or a JavaScript entry.
// Prefer the native binary; otherwise run the entry with this Node runtime.
function packageEntry(directory, platform) {
  try {
    const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8'));
    if (manifest?.name !== '@anthropic-ai/claude-code') return null;
    const exe = platform === 'win32' ? 'claude.exe' : 'claude';
    const optional = '@anthropic-ai/claude-code-' + platform + '-' + process.arch;
    for (const folder of [path.join(directory, 'node_modules', ...optional.split('/')), path.join(path.dirname(directory), optional.split('/')[1])]) {
      for (const name of [exe, path.join('bin', exe)]) {
        const native = executable(path.join(folder, name), platform);
        if (native) return { command: native, prefixArgs: [] };
      }
    }
    const bin = typeof manifest.bin === 'string' ? manifest.bin : manifest.bin?.claude;
    if (typeof bin !== 'string') return null;
    const target = path.resolve(directory, bin), relative = path.relative(directory, target);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) return null;
    if (/\.[cm]?js$/i.test(target)) return fs.statSync(target).isFile() ? { command: process.execPath, prefixArgs: [fs.realpathSync(target)] } : null;
    const native = executable(target, platform) || (platform === 'win32' ? executable(target + '.exe', platform) : null);
    return native ? { command: native, prefixArgs: [] } : null;
  } catch { return null; }
}

function findBinary(env = process.env, platform = process.platform) {
  if (env.UAI_CLAUDE_DISABLED === '1') return null;
  if (env.UAI_CLAUDE_BINARY) {
    const native = executable(env.UAI_CLAUDE_BINARY, platform);
    return native ? { command: native, prefixArgs: [] } : null;
  }
  const exe = platform === 'win32' ? 'claude.exe' : 'claude';
  const home = platform === 'win32' ? env.USERPROFILE || env.HOME : env.HOME || env.USERPROFILE;
  const natives = [], shims = [];
  if (home && path.isAbsolute(home)) {
    natives.push(path.join(home, '.local', 'bin', exe));
    if (platform !== 'win32') natives.push(path.join(home, '.claude', 'local', 'claude'));
  }
  const folders = (env.PATH || env.Path || '').split(path.delimiter).filter(folder => path.isAbsolute(folder));
  for (const folder of folders) natives.push(path.join(folder, exe));
  for (const candidate of natives) {
    const native = executable(candidate, platform);
    if (native) return { command: native, prefixArgs: [] };
  }
  // Never run a .cmd/.ps1/shell shim and never use a shell: resolve the npm
  // package the shim would have started.
  if (home && path.isAbsolute(home)) shims.push([path.join(home, '.claude', 'local', 'claude'), path.join(home, '.claude', 'local')]);
  for (const folder of folders) for (const name of ['claude.cmd', 'claude.ps1', 'claude']) shims.push([path.join(folder, name), folder]);
  for (const [shim, folder] of shims) {
    try { if (!fs.statSync(shim).isFile()) continue; } catch { continue; }
    const packages = [path.join(folder, 'node_modules', '@anthropic-ai', 'claude-code')];
    if (platform !== 'win32') {
      packages.push(path.join(folder, '..', 'lib', 'node_modules', '@anthropic-ai', 'claude-code'));
      try {
        const real = fs.realpathSync(shim).split(path.sep), at = real.lastIndexOf('claude-code');
        if (at > 0 && real[at - 1] === '@anthropic-ai') packages.unshift(real.slice(0, at + 1).join(path.sep) || path.sep);
      } catch { /* Not a package link. */ }
    }
    for (const directory of packages) {
      const entry = packageEntry(directory, platform);
      if (entry) return entry;
    }
  }
  return null;
}

// Two variables could redirect the user's own sign-in elsewhere. Everything
// else, including HOME, USERPROFILE, APPDATA and CLAUDE_CONFIG_DIR, stays as is
// so Claude Code finds the user's own login.
function childEnv(env) {
  const copy = { ...env };
  for (const name of Object.keys(copy)) if (['ANTHROPIC_BASE_URL', 'ANTHROPIC_CUSTOM_HEADERS'].includes(name.toUpperCase())) delete copy[name];
  return copy;
}

function toolDefinitions(body) {
  if (!Array.isArray(body.tools)) return [];
  const seen = new Set();
  return body.tools.map(tool => {
    const f = tool?.type === 'function' ? tool.function || tool : null;
    // Claude sees mcp__uai__<name>; tool names are limited to 64 characters.
    if (!f || typeof f.name !== 'string' || !/^[a-zA-Z0-9_-]{1,54}$/.test(f.name) || seen.has(f.name))
      throw Error('Claude Code requires unique UAI function tools named with at most 54 letters, digits, _ or -');
    seen.add(f.name);
    const schema = f.parameters && typeof f.parameters === 'object' && !Array.isArray(f.parameters) ? f.parameters : {};
    return { name: f.name, description: String(f.description || ''), inputSchema: { type: 'object', properties: {}, ...schema } };
  });
}

function textOf(content) {
  if (typeof content === 'string') return content;
  return Array.isArray(content) ? content.map(part => typeof part === 'string' ? part : typeof part?.text === 'string' ? part.text : '').filter(Boolean).join('\n') : '';
}

// No history is carried between runs: the caller's compacted messages and
// tool results remain the sole conversation of record.
function promptFor(body) {
  const source = body.messages || body.input;
  if (!Array.isArray(source) && typeof source !== 'string') throw Error('Claude Code requires a conversation');
  const system = typeof body.instructions === 'string' && body.instructions ? [body.instructions] : [];
  const images = [], conversation = [];
  for (const message of typeof source === 'string' ? [{ role: 'user', content: source }] : source) {
    if (['system', 'developer'].includes(message?.role)) { const text = textOf(message.content); if (text) system.push(text); continue; }
    if (!Array.isArray(message?.content)) { conversation.push(message); continue; }
    conversation.push({ ...message, content: message.content.map(part => {
      if (!['image_url', 'input_image'].includes(part?.type)) return part;
      const uri = typeof part.image_url === 'string' ? part.image_url : part.image_url?.url;
      const match = typeof uri === 'string' && /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/.exec(uri);
      if (!match) throw Error('Claude Code needs images attached through Cowork; reattach the picture or use another image-capable provider.');
      if (images.length >= 8 || Buffer.byteLength(uri) > 8 << 20) throw Error('Claude Code image attachment limit reached');
      images.push({ type: 'image', source: { type: 'base64', media_type: match[1], data: match[2] } });
      return { type: 'text', text: '[Attached image ' + images.length + '; it follows the conversation]' };
    }) });
  }
  system.push([
    'You are Project UAI, acting in Roblox through the uai tools only.',
    'Continue the conversation given in the user message. It is the whole conversation of record; respect its message roles.',
    'Call mcp__uai__* tools when an action is needed. Tool names in the conversation omit the mcp__uai__ prefix. Results arrive in the next request. Never invent results.',
  ].join('\n'));
  return { system: system.join('\n\n'), content: [{ type: 'text', text: 'Conversation to continue:\n' + JSON.stringify(conversation) }, ...images] };
}

function effortOf(body) {
  const value = body.reasoning_effort ?? body.reasoning?.effort;
  return EFFORTS.includes(value) ? value : value === 'minimal' ? 'low' : undefined;
}

// Provider failures arrive as text. Keep a short, redacted summary.
function failureText(event) {
  const raw = [event?.result, ...(Array.isArray(event?.errors) ? event.errors : [])].filter(item => typeof item === 'string').join(' ');
  const text = raw.replace(/sk-ant-[\w-]+/g, '[redacted]').replace(/Bearer\s+\S+/gi, 'Bearer [redacted]')
    .replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 200);
  const lower = text.toLowerCase();
  if (/usage limit|rate.?limit|\b429\b|quota/.test(lower)) return { message: 'Claude Code reports a usage or rate limit on your Claude plan. Wait for it to reset, then try again.' };
  if (/\/login|log ?in|logged out|sign.?in|authenticat|oauth|\b401\b|credential|api key/.test(lower)) return { message: 'Claude Code is not signed in, or its sign-in expired. ' + signedOut, signedOut: true };
  if (/overloaded|\b529\b/.test(lower)) return { message: 'Claude is temporarily overloaded. Try again shortly.' };
  return { message: 'Claude Code could not answer' + (text ? ': ' + text : event?.subtype ? ' (' + String(event.subtype).replace(/[^\w-]/g, '').slice(0, 40) + ')' : '.') };
}

function probe(binary, args, env, timeout) {
  return new Promise(resolve => {
    let output = '', size = 0, done = false, timer, child;
    const finish = code => { if (done) return; done = true; clearTimeout(timer); resolve({ code, output }); };
    try {
      child = childProcess.spawn(binary.command, [...binary.prefixArgs, ...args],
        { cwd: os.tmpdir(), env, windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch { finish(null); return; }
    timer = setTimeout(() => { child.kill(); finish(null); }, timeout);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => { size += chunk.length; if (size <= 1 << 20) output += chunk; });
    child.stderr.resume();
    child.on('error', () => finish(null));
    child.on('close', code => finish(code));
  });
}

// Startup probes are generous: `claude --help` alone can take several seconds.
// A failed startup is retried after retryMs, so a slow moment needs no restart.
function createClaudeCode({ env = process.env, binary = findBinary(env), probeMs = 20000, waitMs = 3000, retryMs = 30000 } = {}) {
  let directory, rpcServer, rpcSecret, starting, closed = false, active = false;
  let state = binary ? 'starting' : 'missing', version, authMethod, apiProvider, failure, failedAt = 0;
  const jobs = new Map(), children = new Set();
  const alive = child => child.exitCode === null && child.signalCode === null;
  const killChildren = () => { for (const child of children) if (alive(child)) child.kill(); };
  process.once('exit', killChildren);
  const label = value => typeof value === 'string' && /^[\w .-]{1,40}$/.test(value) ? value : undefined;
  const message = () => closed ? 'Claude Code bridge stopped' : state === 'missing' ? missing : state === 'signed-out' ? signedOut :
    state === 'starting' ? 'Claude Code is still starting. Try again in a moment.' : failure || 'Claude Code could not start. ' + update;
  // Reading the capability also retries a failed startup once retryMs passed.
  const capability = () => (state === 'failed' && !closed && start().catch(() => {}), { schema: 1, available: !!binary && !closed, state, models: '/api/claudecode/models', aliases: ALIASES,
    ...(version ? { version } : {}), ...(authMethod ? { authMethod } : {}), ...(apiProvider ? { apiProvider } : {}),
    ...(state !== 'ready' || closed ? { message: help(message()) } : {}) });

  function serveMcp(req, res) {
    const job = req.url?.startsWith('/mcp/') ? jobs.get(req.url.slice('/mcp/'.length)) : undefined;
    const supplied = Buffer.from(String(req.headers.authorization || '')), expected = Buffer.from('Bearer ' + rpcSecret);
    if (!job || req.headers.origin !== undefined || supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) {
      res.writeHead(403); res.end(); return;
    }
    if (req.method !== 'POST') { res.writeHead(405, { allow: 'POST' }); res.end(); return; }
    let size = 0; const chunks = [];
    const hold = () => { job.pending.add(res); res.on('close', () => job.pending.delete(res)); };
    req.on('error', () => {});
    req.on('data', chunk => { size += chunk.length; if (size <= 1 << 20) chunks.push(chunk); });
    req.on('end', () => {
      if (size > 1 << 20) { job.fail('Claude Code returned oversized tool arguments; nothing was run.'); hold(); return; }
      let input;
      try { input = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { res.writeHead(400); res.end(); return; }
      if (!input || typeof input !== 'object' || Array.isArray(input)) { res.writeHead(400); res.end(); return; }
      const reply = body => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ jsonrpc: '2.0', id: input.id, ...body })); };
      if (input.id === undefined || input.id === null) { res.writeHead(202); res.end(); return; }
      if (input.method === 'initialize') {
        const asked = input.params?.protocolVersion;
        reply({ result: { protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0], capabilities: { tools: {} }, serverInfo: { name: 'uai', version: '1.0.0' } } });
      } else if (input.method === 'ping') reply({ result: {} });
      else if (input.method === 'tools/list') reply({ result: { tools: job.tools } });
      else if (input.method === 'tools/call') {
        const name = input.params?.name, args = input.params?.arguments ?? {};
        const bytes = Buffer.byteLength(JSON.stringify(args) || '');
        if (!job.tools.some(tool => tool.name === name) || !args || typeof args !== 'object' || Array.isArray(args) ||
            job.held >= 64 || job.argumentBytes + bytes > MAX_ARGUMENTS) {
          job.fail('Claude Code returned invalid or oversized tool arguments; nothing was run.'); hold(); return;
        }
        job.held += 1; job.argumentBytes += bytes;
        // Hold the result. Roblox executes the call; answering here would let
        // Claude take a second model turn on an invented result.
        hold();
      } else reply({ error: { code: -32601, message: 'Method not found' } });
    });
  }

  async function start() {
    if (closed) throw Error('Claude Code bridge stopped');
    if (!binary) throw Error(missing);
    if (starting && !(state === 'failed' && Date.now() - failedAt >= retryMs)) return starting;
    state = 'starting';
    starting = (async () => {
      const fail = text => { state = 'failed'; failure = text; failedAt = Date.now(); };
      const retrying = ' It retries shortly; if this persists, ' + update;
      const probeEnv = childEnv(env);
      // Judge each probe by what it printed: a CLI that is slow to exit after
      // answering still answered.
      const reported = await probe(binary, ['--version'], probeEnv, probeMs);
      const found = /\b(\d+\.\d+\.\d+)\b/.exec(reported.output);
      if (closed) return;
      if (!found) { fail('Claude Code did not report its version in time.' + retrying); return; }
      version = found[1];
      const usage = await probe(binary, ['--help'], probeEnv, probeMs);
      if (closed) return;
      if (!usage.output.trim()) { fail('Claude Code ' + version + ' did not answer --help in time.' + retrying); return; }
      const lacking = FLAGS.filter(flag => !new RegExp('(?:^|[\\s,\\[])' + flag + '(?![\\w-])', 'm').test(usage.output));
      if (!/\bdontAsk\b/.test(usage.output)) lacking.push('--permission-mode dontAsk');
      if (lacking.length) { fail('Claude Code ' + version + ' lacks ' + lacking.join(', ') + '. ' + update); return; }
      // Only the login flag and two display labels are kept from this output.
      const auth = await probe(binary, ['auth', 'status', '--json'], probeEnv, probeMs);
      let loggedIn;
      try {
        const status = JSON.parse(auth.output);
        loggedIn = status?.loggedIn; authMethod = label(status?.authMethod); apiProvider = label(status?.apiProvider);
      } catch { loggedIn = undefined; }
      if (closed) return;
      if (typeof loggedIn !== 'boolean') { fail('Claude Code could not report its sign-in status in time.' + retrying); return; }
      if (!loggedIn) { state = 'signed-out'; return; }
      if (!rpcServer) {
        directory = fs.mkdtempSync(path.join(os.tmpdir(), 'project-uai-claude-'));
        rpcSecret = crypto.randomBytes(32).toString('hex');
        rpcServer = http.createServer(serveMcp);
        rpcServer.listen(0, '127.0.0.1'); await once(rpcServer, 'listening');
      }
      if (closed) return;
      state = 'ready';
    })().catch(() => { if (state === 'starting') { state = 'failed'; failedAt = Date.now(); failure = 'Claude Code could not start. ' + update; } });
    return starting;
  }

  async function models() {
    await start();
    if (closed || state !== 'ready') throw Error(message());
    return { object: 'list', data: ALIASES.map(id => ({ id, object: 'model', owned_by: 'claude-code',
      name: 'Claude ' + id[0].toUpperCase() + id.slice(1) + ' (latest)' })) };
  }

  // One model turn, read from stream-json. Resolves with the response body on
  // a text-only result or on the first message_stop that carries tool calls.
  function run(child, job, { model, signal, onFrame }) {
    return new Promise((resolve, reject) => {
      const decoder = new StringDecoder('utf8');
      let settled = false, buffer = '', stderr = '';
      const fresh = () => ({ stopped: false, text: '', reasoning: '', finalText: '', finalReasoning: '', blocks: new Map(), complete: new Map(), usage: {}, stop: null });
      let turn = fresh();
      const done = (error, value) => {
        if (settled) return;
        settled = true; job.fail = () => {};
        signal?.removeEventListener('abort', abort);
        if (alive(child)) child.kill();
        for (const res of job.pending) res.destroy();
        if (error) reject(error); else resolve(value);
      };
      const fail = text => done(Error(text));
      const abort = () => fail('Stopped');
      const frame = value => { if (!settled) onFrame(value); };
      const usage = value => { for (const [key, amount] of Object.entries(value || {})) if (typeof amount === 'number') turn.usage[key] = amount; };
      const body = calls => {
        const text = turn.text || turn.finalText, reasoning = turn.reasoning || turn.finalReasoning, u = turn.usage;
        const tokens = Object.keys(u).length ? { input: u.input_tokens || 0, output: u.output_tokens || 0, reasoning: 0,
          cache: { read: u.cache_read_input_tokens || 0, write: u.cache_creation_input_tokens || 0 } } : undefined;
        return responseBody(model, { content: [...(reasoning ? [{ type: 'reasoning', text: reasoning }] : []), ...(text ? [{ type: 'text', text }] : [])],
          tokens, finish: turn.stop === 'max_tokens' ? 'length' : 'stop' }, calls, false);
      };
      const toolBlock = block => ['tool_use', 'server_tool_use', 'mcp_tool_use'].includes(block?.type);
      // Any well-formed UAI tool goes to Roblox, even one this request did not
      // offer: Roblox enforces its registry, scope and permissions and answers
      // with a normal "not run" result. Anything else is a host tool.
      const uaiBlock = block => block.type === 'tool_use' && typeof block.name === 'string' &&
        new RegExp('^' + PREFIX + '[a-zA-Z0-9_-]{1,54}$').test(block.name);
      function handoff() {
        const calls = []; let bytes = 0;
        for (const [, block] of [...turn.blocks.entries()].sort((a, b) => a[0] - b[0])) {
          let args = turn.complete.get(block.id)?.input;
          if (args === undefined) {
            try { args = block.json ? JSON.parse(block.json) : {}; } catch { fail('Claude Code returned malformed tool arguments; nothing was run.'); return; }
          }
          bytes += Buffer.byteLength(JSON.stringify(args) || '');
          if (!args || typeof args !== 'object' || Array.isArray(args) || calls.length >= 64 || bytes > MAX_ARGUMENTS) {
            fail('Claude Code returned invalid or oversized tool arguments; nothing was run.'); return;
          }
          calls.push({ id: 'call_' + crypto.randomBytes(12).toString('hex'), name: block.name.slice(PREFIX.length), arguments: args });
        }
        for (const [index, call] of calls.entries()) frame({ choices: [{ delta: { tool_calls: [{ index, id: call.id, type: 'function',
          function: { name: call.name, arguments: JSON.stringify(call.arguments) } }] } }] });
        // Never let a second model turn start: the child stops here, before it
        // could act on the held MCP calls.
        done(null, body(calls));
      }
      function streamEvent(event) {
        if (!event || typeof event !== 'object') return;
        if (event.type === 'message_start') {
          if (turn.stopped) { fail('Claude Code started another model turn; UAI stopped it. Nothing was run.'); return; }
          turn = fresh(); usage(event.message?.usage);
        } else if (event.type === 'content_block_start' && toolBlock(event.content_block)) {
          if (!uaiBlock(event.content_block)) { fail(hostActionFor(event.content_block.name)); return; }
          turn.blocks.set(event.index, { id: event.content_block.id, name: event.content_block.name, json: '' });
        } else if (event.type === 'content_block_delta') {
          const delta = event.delta;
          if (delta?.type === 'text_delta' && typeof delta.text === 'string' && delta.text) {
            turn.text += delta.text; frame({ choices: [{ delta: { content: delta.text } }] });
          } else if (delta?.type === 'thinking_delta' && typeof delta.thinking === 'string' && delta.thinking) {
            turn.reasoning += delta.thinking; frame({ choices: [{ delta: { reasoning_content: delta.thinking } }] });
          } else if (delta?.type === 'input_json_delta' && typeof delta.partial_json === 'string') {
            const block = turn.blocks.get(event.index);
            if (block) block.json += delta.partial_json;
            if (block && block.json.length > MAX_ARGUMENTS * 2) fail('Claude Code returned oversized tool arguments; nothing was run.');
          }
          if (turn.text.length + turn.reasoning.length > MAX_REPLY) fail('Claude Code response exceeds the bridge limit');
        } else if (event.type === 'message_delta') {
          usage(event.usage);
          if (typeof event.delta?.stop_reason === 'string') turn.stop = event.delta.stop_reason;
        } else if (event.type === 'message_stop') {
          turn.stopped = true;
          if (turn.blocks.size) handoff();
        }
      }
      function handle(line) {
        let event;
        try { event = JSON.parse(line); } catch { return; }
        if (!event || typeof event !== 'object' || Array.isArray(event)) return;
        if (event.parent_tool_use_id) { fail(hostAction); return; }
        if (event.type === 'system' && event.subtype === 'init') {
          const servers = Array.isArray(event.mcp_servers) ? event.mcp_servers : [];
          if (servers.find(server => server?.name === 'uai')?.status !== 'connected') { fail('Claude Code could not reach the UAI tools. Restart Cowork and try again.'); return; }
          const listed = Array.isArray(event.tools) ? event.tools : [];
          if (servers.some(server => server?.name !== 'uai') || listed.some(name => typeof name !== 'string' || !name.startsWith(PREFIX)))
            fail('Claude Code offered tools other than the UAI tools, so nothing was run. ' + update);
        } else if (event.type === 'stream_event') streamEvent(event.event);
        else if (event.type === 'assistant') {
          const message = event.message;
          if (event.error || message?.model === '<synthetic>') {
            const failed = failureText({ result: textOf(message?.content) || String(event.error || '') });
            if (failed.signedOut) state = 'signed-out';
            fail(failed.message); return;
          }
          for (const block of Array.isArray(message?.content) ? message.content : []) {
            if (toolBlock(block)) {
              if (!uaiBlock(block)) { fail(hostActionFor(block.name)); return; }
              turn.complete.set(block.id, block);
            } else if (block?.type === 'text' && typeof block.text === 'string') turn.finalText += block.text;
            else if (block?.type === 'thinking' && typeof block.thinking === 'string') turn.finalReasoning += block.thinking;
          }
        } else if (event.type === 'result') {
          if (event.is_error || event.subtype !== 'success') {
            const failed = failureText(event);
            if (failed.signedOut) state = 'signed-out';
            fail(failed.message); return;
          }
          if (turn.blocks.size) { fail('Claude Code could not hand off the requested tool call. Nothing was run.'); return; }
          if (!Object.keys(turn.usage).length) usage(event.usage);
          done(null, body([]));
        }
      }
      job.fail = fail;
      signal?.addEventListener('abort', abort, { once: true });
      if (signal?.aborted) { abort(); return; }
      child.on('error', () => fail('Claude Code could not start. ' + update));
      child.on('close', code => {
        if (/unknown option|unrecognized|error: option/i.test(stderr)) fail('This Claude Code version does not accept a required option. ' + update);
        else fail('Claude Code stopped before answering (exit ' + code + ').');
      });
      // Read only for a version mismatch; provider output is never logged.
      child.stderr.setEncoding('utf8');
      child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-4096); });
      child.stdout.on('data', chunk => {
        if (settled) return;
        buffer += decoder.write(chunk);
        for (let at = buffer.indexOf('\n'); !settled && at >= 0; at = buffer.indexOf('\n')) {
          const line = buffer.slice(0, at).trim(); buffer = buffer.slice(at + 1);
          if (line) handle(line);
        }
        if (!settled && buffer.length > MAX_LINE) fail('Claude Code output exceeds the bridge limit');
      });
    });
  }

  async function request({ body, url, signal, onFrame = () => {}, source } = {}) {
    if (closed || signal?.aborted) throw Error('Stopped');
    if (source?.local !== true) throw Error(localOnly);
    // One Claude Code run per bridge keeps usage within ordinary individual
    // use. A run that was just stopped gets a moment to exit first.
    for (let waited = 0; active && waited < waitMs; waited += 50) await pause(50, signal);
    if (active) throw Error(busy);
    active = true;
    let key, location, child, job;
    try {
      await start();
      if (closed || signal?.aborted) throw Error('Stopped');
      if (state !== 'ready') throw Error(message());
      if (!official(url)) throw Error('Unsupported Claude Code endpoint');
      const input = JSON.parse(body);
      const model = typeof input.model === 'string' ? input.model.trim() : '';
      if (!validModel(model)) throw Error('Choose a Claude Code model: sonnet, opus, haiku, fable or a full claude- model ID.');
      const tools = toolDefinitions(input), prompt = promptFor(input), effort = effortOf(input);
      key = crypto.randomBytes(16).toString('hex'); location = path.join(directory, key);
      // The working folder stays empty, so no project CLAUDE.md is found.
      const cwd = path.join(location, 'cwd');
      fs.mkdirSync(cwd, { recursive: true, mode: 0o700 });
      // Files keep the system prompt within Windows command-line limits and
      // the MCP bearer secret out of the process command line.
      const mcpConfig = path.join(location, 'mcp.json'), systemPrompt = path.join(location, 'system-prompt.txt');
      fs.writeFileSync(mcpConfig, JSON.stringify({ mcpServers: { uai: { type: 'http',
        url: 'http://127.0.0.1:' + rpcServer.address().port + '/mcp/' + key, headers: { Authorization: 'Bearer ' + rpcSecret } } } }), { mode: 0o600 });
      fs.writeFileSync(systemPrompt, prompt.system, { mode: 0o600 });
      job = { tools, pending: new Set(), held: 0, argumentBytes: 0, fail: () => {} };
      jobs.set(key, job);
      child = childProcess.spawn(binary.command, [...binary.prefixArgs,
        '-p', '--verbose', '--input-format', 'stream-json', '--output-format', 'stream-json', '--include-partial-messages',
        '--tools', '', '--mcp-config', mcpConfig, '--strict-mcp-config', '--allowedTools', PREFIX + '*',
        '--permission-mode', 'dontAsk', '--permission-prompts', 'none', '--disable-slash-commands', '--no-session-persistence',
        '--settings', JSON.stringify({ disableAllHooks: true }), '--system-prompt-file', systemPrompt,
        '--model', model, ...(effort ? ['--effort', effort] : [])],
      { cwd, env: childEnv(env), windowsHide: true, shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
      children.add(child);
      child.stdin.on('error', () => {});
      child.stdin.end(JSON.stringify({ type: 'user', message: { role: 'user', content: prompt.content } }) + '\n');
      const payload = await run(child, job, { model, signal, onFrame });
      return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) };
    } finally {
      if (key) jobs.delete(key);
      for (const res of job?.pending || []) res.destroy();
      if (child) {
        if (alive(child)) { const exited = once(child, 'exit').catch(() => {}); child.kill(); await Promise.race([exited, pause(3000)]); }
        children.delete(child);
      }
      if (location && path.dirname(location) === directory && path.basename(location) === key)
        try { fs.rmSync(location, { recursive: true, force: true, maxRetries: 2, retryDelay: 100 }); } catch { /* close retries the private root. */ }
      active = false;
    }
  }

  // Requests for the sentinel endpoint that this backend will not serve are
  // refused with a reason; plain HTTP would only fail at DNS.
  function refusal(url, body, source) {
    if (!official(url)) return null;
    if (source?.local !== true) return { status: 403, message: localOnly };
    if (closed || state !== 'ready') return { status: 409, message: message() };
    try { if (validModel(String(JSON.parse(body).model || '').trim())) return null; } catch { /* Refused below. */ }
    return { status: 400, message: 'Choose a Claude Code model: sonnet, opus, haiku, fable or a full claude- model ID.' };
  }

  function accepts(url, body, source) {
    if (closed || state !== 'ready' || !official(url) || source?.local !== true) return false;
    try { return validModel(String(JSON.parse(body).model || '').trim()); } catch { return false; }
  }

  async function close() {
    if (closed) return; closed = true;
    process.removeListener('exit', killChildren);
    for (const job of jobs.values()) job.fail('Stopped');
    rpcServer?.closeAllConnections(); rpcServer?.close();
    const running = [...children].filter(alive).map(child => once(child, 'exit').catch(() => {}));
    killChildren();
    await Promise.race([Promise.all(running), pause(2500)]);
    // This root was created by mkdtemp, never derived from a caller's path.
    if (directory && path.dirname(directory) === os.tmpdir() && path.basename(directory).startsWith('project-uai-claude-'))
      try { fs.rmSync(directory, { recursive: true, force: true, maxRetries: 2, retryDelay: 100 }); } catch { /* Left private in the temp folder. */ }
  }

  return { label: 'Claude Code', start, request, models, capability, close, accepts, refusal, official };
}

module.exports = { createClaudeCode, findBinary, official, promptFor, toolDefinitions, effortOf, childEnv, validModel };
