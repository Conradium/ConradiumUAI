'use strict';

// Native CLI backends return one OpenAI-compatible body to Roblox. The message
// uses the shared shape { content: [{ type: 'text' | 'reasoning', text }],
// tokens: { input, output, reasoning, cache: { read, write } }, finish }.
const crypto = require('node:crypto');

function responseBody(model, message, calls, responses) {
  const parts = Array.isArray(message?.content) ? message.content : [];
  const text = parts.filter(p => p.type === 'text').map(p => p.text || '').join('');
  const reasoning = parts.filter(p => p.type === 'reasoning').map(p => p.text || '').join('');
  const id = 'uai_' + crypto.randomBytes(12).toString('hex');
  const tokens = message?.tokens;
  // Native input/output contain only uncached input and visible output.
  // OpenAI-compatible totals include cache reads/writes and reasoning.
  const promptTokens = (tokens?.input || 0) + (tokens?.cache?.read || 0) + (tokens?.cache?.write || 0);
  const completionTokens = (tokens?.output || 0) + (tokens?.reasoning || 0);
  const usage = tokens ? { prompt_tokens: promptTokens, completion_tokens: completionTokens,
    total_tokens: promptTokens + completionTokens, cache_creation_input_tokens: tokens.cache?.write || 0,
    prompt_tokens_details: { cached_tokens: tokens.cache?.read || 0 }, completion_tokens_details: { reasoning_tokens: tokens.reasoning || 0 } } : undefined;
  if (responses) {
    const output = [];
    if (reasoning) output.push({ type: 'reasoning', summary: [{ type: 'summary_text', text: reasoning }] });
    if (text) output.push({ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] });
    for (const call of calls) output.push({ type: 'function_call', id: call.id, call_id: call.id, name: call.name, arguments: JSON.stringify(call.arguments) });
    return { id, object: 'response', model, status: message?.finish === 'length' ? 'incomplete' : 'completed', output,
      ...(tokens ? { usage: { input_tokens: usage.prompt_tokens, output_tokens: usage.completion_tokens, total_tokens: usage.total_tokens,
        cache_creation_input_tokens: usage.cache_creation_input_tokens,
        input_tokens_details: usage.prompt_tokens_details, output_tokens_details: usage.completion_tokens_details } } : {}) };
  }
  const result = { role: 'assistant', content: text || null };
  if (reasoning) result.reasoning_content = reasoning;
  if (calls.length) result.tool_calls = calls.map(call => ({ id: call.id, type: 'function', function: { name: call.name, arguments: JSON.stringify(call.arguments) } }));
  return { id, object: 'chat.completion', model, ...(usage ? { usage } : {}), choices: [{ index: 0, message: result,
    finish_reason: message?.finish === 'length' ? 'length' : calls.length ? 'tool_calls' : 'stop' }] };
}

module.exports = { responseBody };
