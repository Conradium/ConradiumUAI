'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { startBridge, readStream, sleep } = require('./helpers/bridge');
const { makePng } = require('./helpers/images');

test('OpenCode Responses crosses the authenticated bridge with identity, images, previews and one provider dispatch', async t => {
  const bridge = await startBridge(t), received = [];
  const raw = [
    { type: 'response.created', response: { model: 'muse-spark-fixture' } },
    { type: 'response.output_text.delta', delta: 'Image received' },
    { type: 'response.completed', response: { status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: 'Image received' }] }] } },
  ].map(frame => 'data: ' + JSON.stringify(frame) + '\n\n').join('');
  const provider = http.createServer((req, res) => {
    let body = ''; req.on('data', chunk => body += chunk); req.on('end', () => {
      received.push({ headers: req.headers, body: JSON.parse(body), url: req.url });
      res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(raw);
    });
  });
  provider.listen(0, '127.0.0.1'); await once(provider, 'listening');
  t.after(() => { provider.closeAllConnections(); provider.close(); });
  const headers = { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json', 'X-UAI-Browser-Id': 'responses-browser' };
  const post = (route, body) => fetch(bridge.base + route, { method: 'POST', headers, body: JSON.stringify(body) });
  await post('/api/agent/events', { state: { sessionId: 'responses-session', imageInput: true } });
  const hello = await (await fetch(bridge.base + '/api/hello', { headers })).json();
  const bytes = makePng(3, 4);
  const upload = await fetch(bridge.base + '/api/pictures', { method: 'POST', headers: { ...headers, 'content-type': 'image/png',
    'X-UAI-Picture-Id': 'pic_responses_wire', 'X-UAI-Session-Id': 'responses-session', 'X-UAI-Picture-Name': 'fixture.png' }, body: bytes });
  assert.equal(upload.status, 201);
  assert.equal((await post('/api/send', { sessionId: 'responses-session', text: 'Look', pictureIds: ['pic_responses_wire'], commandId: 'responses-image-command' })).status, 202);
  const inbox = await (await fetch(bridge.base + '/api/agent/inbox', { headers })).json();
  const image = inbox.commands[0].images[0];
  const session = 'ses_' + ((~(BigInt(Date.now()) << 12n)) & ((1n << 48n) - 1n)).toString(16).padStart(12, '0') + 'FixtureSession';
  const input = { id: 'responses-wire-request', instance: hello.instance, sessionId: 'responses-session',
    url: 'http://127.0.0.1:' + provider.address().port + '/inference/v1/responses?tenant=fixture',
    headers: { Authorization: 'Bearer provider-fixture-key', 'User-Agent': 'opencode/latest/2.0.27/desktop', 'x-opencode-client': 'desktop', 'x-opencode-session': session, 'X-Stainless-Timeout': '1', accept: '*/*', 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'muse-spark-fixture', stream: true, input: [{ role: 'user', content: [{ type: 'input_text', text: 'Look' }, { type: 'input_image', image_url: image.url }] }] }) };
  const events = await readStream(bridge.base, bridge.token, async () => {
    assert.equal((await post('/api/inference', input)).status, 202);
    let job;
    for (let attempt = 0; attempt < 100; attempt++) {
      job = await (await fetch(bridge.base + '/api/inference/' + input.id, { headers })).json();
      if (job.state !== 'running') break;
      await sleep(10);
    }
    assert.equal(job.state, 'completed'); assert.equal(job.body, raw);
    assert.equal((await post('/api/inference', input)).status, 202);
  });
  assert.equal(received.length, 1);
  assert.equal(received[0].url, '/inference/v1/responses?tenant=fixture');
  assert.equal(received[0].headers.authorization, 'Bearer provider-fixture-key');
  assert.equal(received[0].headers['user-agent'], 'opencode/latest/2.0.27/desktop');
  assert.equal(received[0].headers['x-opencode-client'], 'desktop');
  assert.equal(received[0].headers['x-opencode-session'], session);
  assert.equal(received[0].headers['x-stainless-timeout'], undefined, 'legacy native deadline metadata cannot limit Cowork work');
  assert.equal(received[0].body.input[0].content[1].image_url, 'data:image/png;base64,' + bytes.toString('base64'));
  const deltas = events.filter(event => event.kind === 'inference:delta');
  assert.equal(deltas.map(event => event.text).join(''), 'Image received');
  assert.equal(deltas[0].sessionId, 'responses-session');
  assert.equal(events.find(event => event.kind === 'inference:done').state, 'completed');
  const replay = await readStream(bridge.base, bridge.token);
  assert.equal(replay.filter(event => event.kind === 'inference:delta').map(event => event.text).join(''), 'Image received');
  assert.doesNotMatch(JSON.stringify([events, replay]), /provider-fixture-key|base64/);
});
