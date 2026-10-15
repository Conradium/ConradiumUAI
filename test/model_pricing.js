// Normalization regressions: provider identity, zero prices, precision, failure.
const assert = require('node:assert/strict');
const { normalize, render, snapshotText } = require('../tools/sync_pricing');
const raw = { modelsdev: {}, litellm: {}, openrouter: { data: [] } };
for (const provider of ['openai', 'anthropic', 'google', 'deepseek', 'opencode', 'opencode-go', 'groq', 'togetherai', 'mistral', 'xai', 'fireworks-ai', 'cerebras']) {
	raw.modelsdev[provider] = { models: { fixture: { cost: { input: 3, output: 6 }, limit: { context: 10000, output: 2000 }, tool_call: true } } };
}
for (let index = 0; index < 100; index++) raw.openrouter.data.push({ id: 'vendor/model-' + index, pricing: { prompt: '0.000000091', completion: '0.000000182', input_cache_read: '0.0000000182' } });
raw.openrouter.data.push({ id: 'vendor/model-0:free', pricing: { prompt: '0', completion: '0' } });
raw.litellm['openai/fixture'] = { litellm_provider: 'openai', mode: 'chat', input_cost_per_token: 0.000009, output_cost_per_token: 0.000018 };
raw.litellm['anthropic/vendor/retained'] = { litellm_provider: 'anthropic', mode: 'chat', input_cost_per_token: 0.000002, output_cost_per_token: 0.000010 };
const providers = normalize(raw);
assert.equal(providers.openai.fixture.price.input, 3, 'models.dev takes precedence over supplemental rates');
assert.equal(providers['opencode-go'].fixture.price, undefined, 'catalog rates do not establish an additional subscription charge');
assert.equal(providers['opencode-go'].fixture.context, 10000, 'Go retains its own model limits');
assert.equal(providers.anthropic['vendor/retained'].price.input, 2, 'only the known LiteLLM provider prefix is removed');
assert.equal(providers.openrouter['vendor/model-0'].price.input, 0.091);
assert.equal(providers.openrouter['vendor/model-0'].price.cacheRead, 0.0182, 'sub-microtoken prices retain precision');
assert.equal(providers.openrouter['vendor/model-0:free'].price.input, 0);
assert.equal(providers.openrouter['model-0'], undefined, 'model namespaces are not erased');
assert.throws(() => normalize({ ...raw, openrouter: { data: [] } }), /incomplete model list/);
assert.throws(() => normalize(raw, [{ id: 'paid', cost: [{ input: 1, output: 1 }] }]), /verified free rates/);
const snapshot = { schema: 1, updated: '2026-10-15T00:00:00.000Z', sources: {}, providers };
assert.equal(render(JSON.parse(snapshotText(snapshot))), render(snapshot), 'offline generation is deterministic');
console.log('Model pricing normalization: 11 assertions passed.');
