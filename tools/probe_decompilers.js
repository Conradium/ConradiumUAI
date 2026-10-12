'use strict';

// Explicit live integration probe. Sends ONLY this file's constant authored
// `return 42` fixture; never accepts an input file, credential, or game script.
// Run after the normal review/build gate: node tools/probe_decompilers.js
// Returned source is compiled, never executed. A literal return is checked
// independently so an HTTP 200 or syntactically valid error is not a pass.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const directory = path.join(root, 'refer', 'decompile-probe');
const compiler = process.env.LUAU_COMPILE || path.join(root, 'refer', 'native-tools', 'luau', process.platform === 'win32' ? 'luau-compile.exe' : 'luau-compile');
const fixture = 'return 42\n';
const MAX_RESPONSE = 2 * 1024 * 1024;
function compile(args) {
  return spawnSync(compiler, args, { cwd: root, windowsHide: true, timeout: 10000, maxBuffer: MAX_RESPONSE });
}
function literalResult(source) {
  let rest = source;
  while (true) {
    rest = rest.trimStart();
    const block = /^--\[(=*)\[/.exec(rest);
    if (block) {
      const close = ']' + block[1] + ']';
      const at = rest.indexOf(close, block[0].length);
      if (at < 0) return false;
      rest = rest.slice(at + close.length);
    } else if (rest.startsWith('--')) {
      const newline = rest.indexOf('\n');
      rest = newline < 0 ? '' : rest.slice(newline + 1);
    } else break;
  }
  return /^return\s+(?:42(?:\.0*)?|0x2a)\s*;?\s*$/i.test(rest);
}
async function probe(service, bytecode) {
  const started = Date.now();
  const result = { service: service.name, status: null, sourceCompiled: false, expectedLiteral: false };
  try {
    const response = await fetch(service.url, {
      method: 'POST', headers: { 'Content-Type': service.contentType, Accept: 'text/plain' },
      body: service.body(bytecode), signal: AbortSignal.timeout(30000), redirect: 'error',
    });
    result.status = response.status;
    result.contentType = response.headers.get('content-type');
    const reader = response.body.getReader();
    const chunks = []; let bytes = 0;
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      bytes += part.value.length;
      if (bytes > MAX_RESPONSE) { await reader.cancel(); throw new Error('response exceeds 2 MiB'); }
      chunks.push(Buffer.from(part.value));
    }
    const body = Buffer.concat(chunks);
    result.bytes = body.length;
    // Retain response separately for manual inspection; never execute it.
    fs.writeFileSync(path.join(directory, service.name + '-response.txt'), body);
    if (response.status === 200) {
      const source = new TextDecoder('utf-8', { fatal: true }).decode(body);
      const sourcePath = path.join(directory, service.name + '-source.lua');
      fs.writeFileSync(sourcePath, source, 'utf8');
      const checked = compile(['--null', sourcePath]);
      result.sourceCompiled = !checked.error && checked.status === 0;
      result.expectedLiteral = literalResult(source);
      if (!result.sourceCompiled) result.diagnostic = 'returned text did not compile as Luau';
      else if (!result.expectedLiteral) result.diagnostic = 'returned chunk requires manual comparison with return 42';
    } else result.diagnostic = 'service refused the authored synthetic bytecode';
  } catch (error) {
    result.diagnostic = error && error.message ? error.message : String(error);
  }
  result.milliseconds = Date.now() - started;
  result.ok = result.status === 200 && result.sourceCompiled && result.expectedLiteral;
  return result;
}
async function main() {
  if (process.argv.length !== 2) throw new Error('This probe accepts no source files or arguments.');
  fs.mkdirSync(directory, { recursive: true });
  const input = path.join(directory, 'authored-fixture.lua');
  fs.writeFileSync(input, fixture, 'utf8');
  const built = compile(['--binary', input]);
  if (built.error || built.status !== 0 || !built.stdout || built.stdout.length === 0 || built.stdout.length > 65536
      || built.stdout[0] === 0 || built.stdout[0] > 20) throw new Error('Could not compile the fixed synthetic fixture to Luau bytecode.');
  fs.writeFileSync(path.join(directory, 'authored-fixture.bin'), built.stdout);
  const services = [
    { name: 'bytefall', url: 'https://decompiler.bytefall.dev/decompile', contentType: 'application/json',
      body: bytes => JSON.stringify({ script: bytes.toString('base64') }) },
    { name: 'luacid', url: 'https://api.luacid.dev/decompile?type_annotations=functions&generated_names=readable&indent=tab',
      contentType: 'application/octet-stream', body: bytes => bytes },
  ];
  const results = await Promise.all(services.map(service => probe(service, built.stdout)));
  const report = { at: new Date().toISOString(), fixture, bytecodeBytes: built.stdout.length,
    scope: 'Public services with an authored literal fixture; no Roblox/executor or private-source coverage.', results };
  fs.writeFileSync(path.join(directory, 'results.json'), JSON.stringify(report, null, 2) + '\n');
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  if (results.some(result => !result.ok)) process.exitCode = 1;
}
main().catch(error => { process.stderr.write(String(error.message || error) + '\n'); process.exitCode = 1; });
