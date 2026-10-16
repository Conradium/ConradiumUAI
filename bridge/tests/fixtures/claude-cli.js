'use strict';
// Offline stand-in for the `claude` binary. It never contacts an upstream
// provider and never reads a credential. The scenario comes from
// UAI_CLAUDE_FIXTURE_SCENARIO, or from a SCENARIO:<name> marker in the prompt.
const fs = require('node:fs');
const args = process.argv.slice(2);
const log = value => fs.appendFileSync(process.env.UAI_CLAUDE_FIXTURE_LOG, JSON.stringify(value) + '\n');
const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
const option = name => { const at = args.indexOf(name); return at >= 0 ? args[at + 1] : undefined; };
const FLAGS = ['-p, --print', '--verbose', '--input-format <format>', '--output-format <format>', '--include-partial-messages',
  '--tools <tools...>', '--mcp-config <configs...>', '--strict-mcp-config', '--allowedTools, --allowed-tools <tools...>',
  '--permission-mode <mode>  (choices: "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")',
  '--permission-prompts <target>', '--disable-slash-commands', '--no-session-persistence', '--settings <file-or-json>',
  '--system-prompt <prompt>', '--model <model>', '--effort <level>', '--bare'];

if (args[0] === '--version') { process.stdout.write('2.1.301 (Claude Code)\n'); return; }
if (args[0] === '--help') {
  // The first --help after this marker is created answers nothing, as a CLI
  // that was too busy to reply would.
  const once = process.env.UAI_CLAUDE_FIXTURE_HELP_FAILS_ONCE;
  if (once && !fs.existsSync(once)) { fs.writeFileSync(once, ''); process.exitCode = 1; return; }
  const omit = process.env.UAI_CLAUDE_FIXTURE_OMIT_FLAG;
  process.stdout.write('Usage: claude [options] [command] [prompt]\n\nOptions:\n' +
    FLAGS.filter(flag => !omit || !flag.startsWith(omit)).map(flag => '  ' + flag + '\n').join(''));
  // A real CLI can take seconds to exit after printing its help.
  if (process.env.UAI_CLAUDE_FIXTURE_SLOW_EXIT) setTimeout(() => {}, Number(process.env.UAI_CLAUDE_FIXTURE_SLOW_EXIT));
  return;
}
if (args[0] === 'auth' && args[1] === 'status') {
  const loggedIn = process.env.UAI_CLAUDE_FIXTURE_AUTH !== 'out';
  process.stdout.write(JSON.stringify({ loggedIn, authMethod: loggedIn ? 'claude.ai' : 'none', apiProvider: 'firstParty',
    ...(loggedIn ? { email: 'fixture@example.invalid', orgId: 'org-fixture', orgName: 'Fixture org', subscriptionType: 'max' } : {}) }));
  process.exitCode = loggedIn ? 0 : 1;
  return;
}

(async () => {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  const user = JSON.parse(input.trim().split('\n')[0]);
  const prompt = user.message.content[0].text;
  const scenario = /SCENARIO:([\w-]+)/.exec(prompt)?.[1] || process.env.UAI_CLAUDE_FIXTURE_SCENARIO || 'text';
  const mcp = JSON.parse(fs.readFileSync(option('--mcp-config'), 'utf8')).mcpServers.uai;
  const rpc = async (method, params, id) => {
    const response = await fetch(mcp.url, { method: 'POST', headers: { ...mcp.headers, 'content-type': 'application/json',
      accept: 'application/json, text/event-stream' }, body: JSON.stringify({ jsonrpc: '2.0', ...(id === undefined ? {} : { id }), method, params }) });
    return response.status === 200 ? response.json() : { status: response.status };
  };
  const initialized = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'claude-code-fixture' } }, 0);
  const notified = await rpc('notifications/initialized');
  const tools = (await rpc('tools/list', {}, 1)).result.tools;
  log({ type: 'run', pid: process.pid, args, cwd: process.cwd(), cwdEntries: fs.readdirSync(process.cwd()), scenario,
    env: { HOME: process.env.HOME, USERPROFILE: process.env.USERPROFILE, APPDATA: process.env.APPDATA,
      baseUrl: process.env.ANTHROPIC_BASE_URL, customHeaders: process.env.ANTHROPIC_CUSTOM_HEADERS },
    mcp: { type: mcp.type, url: mcp.url, authorization: mcp.headers.Authorization }, protocol: initialized.result.protocolVersion,
    notificationStatus: notified.status, tools, system: fs.readFileSync(option('--system-prompt-file'), 'utf8'), user });

  const session = 'fixture-session', model = option('--model');
  const stream = event => emit({ type: 'stream_event', event, session_id: session, parent_tool_use_id: null });
  const assistant = content => emit({ type: 'assistant', message: { id: 'msg_fixture', role: 'assistant', model, content }, parent_tool_use_id: null, session_id: session });
  const text = (index, value) => {
    stream({ type: 'content_block_start', index, content_block: { type: 'text', text: '' } });
    for (const part of [value.slice(0, 2), value.slice(2)]) stream({ type: 'content_block_delta', index, delta: { type: 'text_delta', text: part } });
    stream({ type: 'content_block_stop', index });
    assistant([{ type: 'text', text: value }]);
  };
  const tool = (index, name, id) => {
    stream({ type: 'content_block_start', index, content_block: { type: 'tool_use', id, name, input: {} } });
    for (const part of ['{"value":', '"fixture"}']) stream({ type: 'content_block_delta', index, delta: { type: 'input_json_delta', partial_json: part } });
    stream({ type: 'content_block_stop', index });
    assistant([{ type: 'tool_use', id, name, input: { value: 'fixture' } }]);
  };
  const toolNames = tools.map(item => 'mcp__uai__' + item.name);
  emit({ type: 'system', subtype: 'init', session_id: session, model, cwd: process.cwd(), permissionMode: option('--permission-mode'),
    tools: scenario === 'extra-tool' ? [...toolNames, 'Bash'] : toolNames,
    mcp_servers: [{ name: 'uai', status: scenario === 'mcp-down' ? 'failed' : 'connected' }] });
  stream({ type: 'message_start', message: { id: 'msg_fixture', model, usage: { input_tokens: 10, cache_read_input_tokens: 100, cache_creation_input_tokens: 5, output_tokens: 1 } } });

  if (scenario === 'hang') {
    text(0, 'Working');
    setInterval(() => {}, 1000);
    return;
  }
  if (scenario === 'tool' || scenario === 'parallel' || scenario === 'host' || scenario === 'unoffered' || scenario === 'bare' || scenario === 'bare-unoffered') {
    text(0, 'Checking Roblox.');
    const count = scenario === 'parallel' ? 2 : 1;
    const name = { host: 'Bash', unoffered: 'mcp__uai__remotes_capture', bare: 'lookup', 'bare-unoffered': 'run_luau' }[scenario] || 'mcp__uai__lookup';
    for (let index = 0; index < count; index++) tool(index + 1, name, 'toolu_fixture_' + index);
    stream({ type: 'message_delta', delta: { stop_reason: 'tool_use' }, usage: { output_tokens: 12 } });
    // Send the MCP calls first, as a slow pipe could, so the bridge must hold them.
    for (let index = 0; index < count && scenario !== 'host' && scenario !== 'unoffered' && !scenario.startsWith('bare'); index++) {
      log({ type: 'tools/call-sent', index });
      rpc('tools/call', { name: 'lookup', arguments: { value: 'fixture' } }, 10 + index)
        .then(reply => log({ type: 'tools/call-result', index, reply }), () => log({ type: 'tools/call-closed', index }));
    }
    await new Promise(resolve => setTimeout(resolve, 150));
    stream({ type: 'message_stop' });
    // A real CLI would continue with a second turn once results arrive.
    setTimeout(() => { log({ type: 'second-turn' }); stream({ type: 'message_start', message: { id: 'msg_second', usage: {} } }); }, 1500);
    setInterval(() => {}, 1000);
    return;
  }
  if (scenario === 'error' || scenario === 'auth-error') {
    emit({ type: 'result', subtype: 'success', is_error: true, session_id: session,
      result: scenario === 'error' ? 'Claude AI usage limit reached|1760000000' : 'Invalid API key · Please run /login' });
    return;
  }
  if (scenario === 'thinking') {
    stream({ type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: '' } });
    stream({ type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: 'Checked.' } });
    stream({ type: 'content_block_stop', index: 0 });
    assistant([{ type: 'thinking', thinking: 'Checked.' }]);
  }
  text(scenario === 'thinking' ? 1 : 0, 'PONG');
  stream({ type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 7 } });
  stream({ type: 'message_stop' });
  emit({ type: 'result', subtype: 'success', is_error: false, result: 'PONG', session_id: session,
    usage: { input_tokens: 10, output_tokens: 7, cache_read_input_tokens: 100, cache_creation_input_tokens: 5 } });
})().catch(error => { process.stderr.write(String(error?.stack || error)); process.exitCode = 1; });
