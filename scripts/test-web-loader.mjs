/**
 * Transport-only tests for the built Godot HTML shell.
 *
 * Run: node scripts/test-web-loader.mjs
 * Optional: node --expose-gc scripts/test-web-loader.mjs /absolute/path/to/dist
 *
 * This is NOT browser automation, a WebGL test, or Godot engine execution.
 * The real generated inline loader runs in a Node vm with mocked DOM, Engine,
 * timers and fetch. Real exported asset bytes, streams and SHA-256 are used.
 * No network requests, installation, publication, or source mutation occurs.
 */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { createHash, webcrypto } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { createContext, runInContext } from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dist = path.resolve(process.argv[2] || path.join(root, 'dist'));
const html = readFileSync(path.join(dist, 'index.html'), 'utf8');
const manifest = JSON.parse(readFileSync(path.join(dist, 'runtime-manifest.json'), 'utf8'));
const inlineScripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map(match => match[1]);
const loaderSource = inlineScripts.find(script => script.includes('const nativeFetch') && script.includes('async function play()'));
if (!loaderSource) throw new Error('Built HTML does not contain the expected custom loader');
if (/\$GODOT_(CONFIG|URL|HEAD_INCLUDE)/.test(html)) throw new Error('Unexpanded Godot template in dist/index.html');

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const baseUrl = 'https://loader-test.invalid/game/index.html';
const assetPrefix = '/game/';
const maxAssetBytes = 25 * 1024 * 1024;
let assertions = 0;
const results = [];
const metadata = {html_sha256:digest(html), wasm_sha256:manifest.sha256, wasm_bytes:manifest.bytes};

function equal(actual, expected, message) { assertions += 1; assert.equal(actual, expected, message); }
function ok(value, message) { assertions += 1; assert.ok(value, message); }
function matches(value, pattern, message) { assertions += 1; assert.match(String(value), pattern, message); }

function fileInventory(directory, prefix = '') {
  const entries = [];
  for (const name of readdirSync(directory)) {
    const full = path.join(directory, name);
    const relative = path.posix.join(prefix, name);
    const stat = statSync(full);
    if (stat.isDirectory()) entries.push(...fileInventory(full, relative));
    else if (stat.isFile()) entries.push({file:relative, bytes:stat.size});
  }
  return entries;
}

function auditAssets() {
  const files = fileInventory(dist);
  ok(files.length > 0, 'Export output is not empty');
  for (const entry of files) ok(entry.bytes <= maxAssetBytes, `${entry.file} exceeds 25 MiB`);
  equal(existsSync(path.join(dist, 'index.wasm')), false, 'Oversized original is not deployed');
  equal(manifest.parts.length, 2, 'This build uses exactly two raw parts');
  let partSum = 0;
  const parts = manifest.parts.map(part => {
    const buffer = readFileSync(path.join(dist, part.file));
    equal(buffer.length, part.bytes, `${part.file} size`);
    equal(digest(buffer), part.sha256, `${part.file} hash`);
    partSum += buffer.length;
    return buffer;
  });
  equal(partSum, manifest.bytes, 'Part sizes sum to the whole runtime');
  const raw = Buffer.concat(parts);
  equal(raw.subarray(0, 8).toString('hex'), '0061736d01000000', 'WebAssembly magic and version');
  equal(digest(raw), manifest.sha256, 'Reassembled runtime hash');
  const gzip = readFileSync(path.join(dist, manifest.gzip.file));
  equal(gzip.length, manifest.gzip.bytes, 'Gzip size');
  equal(digest(gzip), manifest.gzip.sha256, 'Gzip hash');
  const inflated = gunzipSync(gzip);
  equal(inflated.length, manifest.bytes, 'Inflated runtime size');
  equal(digest(inflated), manifest.sha256, 'Inflated runtime hash');
  ok(inflated.equals(raw), 'Gzip and raw parts contain identical engine bytes');
  const localOriginal = path.join(root, '.local', 'index.wasm');
  if (existsSync(localOriginal)) {
    equal(digest(readFileSync(localOriginal)), manifest.sha256, 'Retained original matches manifest');
  }
  metadata.gzip_bytes = gzip.length;
  metadata.parts = manifest.parts.map(({file, bytes}) => ({file, bytes}));
  metadata.asset_count = files.length;
  metadata.largest_asset = files.reduce((largest, entry) => entry.bytes > largest.bytes ? entry : largest);
  metadata.total_asset_bytes = files.reduce((sum, entry) => sum + entry.bytes, 0);
  metadata.game_pack_sha256 = digest(readFileSync(path.join(dist, 'index.pck')));
}

function element(id) {
  return {
    id, hidden: id === 'progress', textContent:'', style:{}, focusCount:0, onclick:null,
    listeners:new Map(),
    addEventListener(type, callback) {
      const list = this.listeners.get(type) || [];
      list.push(callback); this.listeners.set(type, list);
    },
    focus() { this.focusCount += 1; }
  };
}

function harness(options = {}) {
  const elements = new Map(['canvas','loader','start','progress','bar','load-text','game-status'].map(id => [id, element(id)]));
  elements.get('canvas').style.visibility = 'hidden';
  const records = [];
  const errors = [];
  const timers = new Map();
  const state = {engineConstructions:0, engineStarts:0, runtimeReads:0, reloads:0, runtimeHash:null, runtimeBytes:0, lateResolve:null};
  let context;
  let nextTimer = 1;
  const contentType = file => file.endsWith('.json') ? 'application/json' : file.endsWith('.js') ? 'application/javascript' : file.endsWith('.gz') ? 'application/gzip' : 'application/octet-stream';
  async function nativeFetch(input, init) {
    const inputUrl = typeof input === 'string' || input instanceof URL ? input : input.url;
    const url = new URL(inputUrl, baseUrl);
    const method = (init?.method || (typeof input === 'object' ? input.method : '') || 'GET').toUpperCase();
    const record = {url:url.href, file:url.pathname.startsWith(assetPrefix) ? decodeURIComponent(url.pathname.slice(assetPrefix.length)) : null, method, input, init};
    records.push(record);
    if (init?.signal?.aborted) throw new DOMException('Aborted', 'AbortError');
    if (url.origin !== new URL(baseUrl).origin || !url.pathname.startsWith(assetPrefix)) return new Response('native passthrough', {status:200});
    const file = record.file;
    const full = path.resolve(dist, file);
    if (!full.startsWith(`${dist}${path.sep}`)) throw new Error('Mock fetch refuses path escape');
    if (options.missingFile === file) return new Response('missing', {status:404});
    if (options.throwFile === file) throw new TypeError('Injected network failure');
    if (!existsSync(full)) return new Response('not found', {status:404});
    let body = readFileSync(full);
    if (file === 'runtime-manifest.json' && options.wrongFinalHash) {
      body = Buffer.from(JSON.stringify({...manifest, sha256:'0'.repeat(64)}));
    }
    if (options.corruptFile === file) {
      body = Buffer.from(body);
      body[Math.min(4096, body.length - 1)] ^= 0x80;
    }
    if (options.truncateFile === file) body = body.subarray(0, body.length - 1);
    if (options.overlongFile === file) body = Buffer.concat([body, Buffer.from([0])]);
    if (options.readerErrorFile === file) {
      let sent = false;
      return new Response(new ReadableStream({
        pull(controller) {
          if (!sent) { sent = true; controller.enqueue(body.subarray(0, 1024)); }
          else controller.error(new Error('Injected body reader failure'));
        }
      }), {headers:{'Content-Type':contentType(file)}});
    }
    return new Response(method === 'HEAD' ? null : body, {status:200,headers:{'Content-Type':contentType(file),'Content-Length':String(body.length)}});
  }
  class MockEngine {
    static isWebGLAvailable(version) { equal(version, 2, 'Shell checks WebGL 2'); return !options.noWebGL; }
    constructor(config) { state.engineConstructions += 1; this.config = config; }
    async startGame() {
      state.engineStarts += 1;
      equal(this.config.canvas, elements.get('canvas'), 'Mock receives canvas');
      equal(this.config.canvasResizePolicy, 0, 'Canvas sizing controlled by shell');
      if (options.hangEngine) {
        await new Promise(resolve => { state.lateResolve = resolve; });
        return;
      }
      const request = options.requestInput ? new Request(new URL('./index.wasm', baseUrl)) : './index.wasm';
      const response = await context.fetch(request);
      equal(response.status, 200, 'Synthetic WASM response status');
      equal(response.headers.get('Content-Type'), 'application/wasm', 'Synthetic WASM MIME');
      equal(response.headers.get('Content-Length'), String(manifest.bytes), 'Synthetic WASM length header');
      const bytes = await response.arrayBuffer();
      state.runtimeReads += 1;
      state.runtimeBytes = bytes.byteLength;
      state.runtimeHash = digest(Buffer.from(bytes));
      equal(state.runtimeBytes, manifest.bytes, 'Mock consumer receives full runtime');
      equal(state.runtimeHash, manifest.sha256, 'Mock consumer receives unmodified runtime');
      const pck = await context.fetch('./index.pck');
      equal(pck.status, 200, 'Game pack bypasses WASM adapter');
      equal((await pck.arrayBuffer()).byteLength, statSync(path.join(dist, 'index.pck')).size, 'Real game pack remains readable');
      this.config.onProgress?.(manifest.bytes, manifest.bytes);
    }
  }
  const documentListeners = new Map();
  const sandbox = {
    document:{
      getElementById(id) { if (!elements.has(id)) throw new Error(`Unexpected DOM id: ${id}`); return elements.get(id); },
      addEventListener(type, callback) { documentListeners.set(type, callback); }
    },
    location:{href:baseUrl, reload() { state.reloads += 1; }},
    fetch:nativeFetch, crypto:webcrypto, URL, Request, Response, Blob, ReadableStream, AbortController,
    WebAssembly: options.noWebAssembly ? undefined : Object.freeze({}),
    console:{error(...args) { errors.push(args.map(item => item?.message || String(item)).join(' ')); }, log() {}, warn() {}},
    setTimeout(callback, delay) { const id = nextTimer++; timers.set(id, {callback, delay}); return id; },
    clearTimeout(id) { timers.delete(id); }
  };
  if (!options.noDecompressionStream) sandbox.DecompressionStream = DecompressionStream;
  if (!options.noEngine) sandbox.Engine = MockEngine;
  sandbox.window = sandbox;
  context = createContext(sandbox);
  runInContext(loaderSource, context, {filename:'dist/index.html:inline-loader', timeout:5000});
  const installedFetch = context.fetch;
  return {
    context, elements, records, errors, timers, state, installedFetch,
    async start() {
      const callback = elements.get('start').listeners.get('click')?.[0];
      ok(callback, 'Play click listener installed');
      return callback();
    },
    fireWatchdog() {
      const entry = [...timers.entries()].find(([, timer]) => timer.delay === 120000);
      ok(entry, '120-second startup watchdog is installed');
      timers.delete(entry[0]);
      entry[1].callback();
    }
  };
}

function assertSuccess(test) {
  equal(test.state.engineStarts, 1, 'Exactly one mock engine start');
  equal(test.state.runtimeReads, 1, 'Exactly one runtime response consumed');
  equal(test.elements.get('loader').hidden, true, 'Loader hidden only after mock start succeeds');
  equal(test.elements.get('canvas').style.visibility, 'visible', 'Canvas revealed after mock start');
  equal(test.elements.get('canvas').focusCount, 1, 'Canvas receives focus');
  equal(test.elements.get('bar').style.width, '100%', 'Progress reaches completion');
  equal(test.errors.length, 0, 'No loader error logged');
  equal(test.timers.size, 0, 'Watchdog cleared');
  ok(test.context.fetch !== test.installedFetch, 'Native fetch restored after success');
  equal(test.records.some(record => record.file === 'index.wasm'), false, 'No network request for absent oversized original');
}

function assertFailure(test, pattern) {
  equal(test.elements.get('loader').hidden, false, 'Loader remains visible after failure');
  equal(test.elements.get('canvas').style.visibility, 'hidden', 'Unstarted canvas is not revealed');
  equal(test.elements.get('progress').hidden, true, 'Failed progress is hidden');
  equal(test.elements.get('start').hidden, false, 'Reload action is visible');
  equal(test.elements.get('start').textContent, 'Обновить', 'Reload label is actionable');
  matches(test.elements.get('load-text').textContent, /Не удалось загрузить игру/, 'User sees loader failure');
  equal(test.timers.size, 0, 'Failure clears watchdog');
  ok(test.context.fetch !== test.installedFetch, 'Failure restores native fetch');
  equal(test.errors.length, 1, 'Failure logged once despite promise propagation');
  matches(test.errors[0], pattern, 'Expected failure reason');
  for (const request of test.records.filter(record => record.init?.signal)) {
    equal(request.init.signal.aborted, true, 'Outstanding runtime download signal aborted');
  }
  equal(typeof test.elements.get('start').onclick, 'function', 'Reload callback installed');
  test.elements.get('start').onclick();
  equal(test.state.reloads, 1, 'Reload callback works');
}

async function test(name, execute) {
  const before = assertions;
  const started = performance.now();
  try {
    await execute();
    results.push({name, status:'PASS', assertions:assertions-before, milliseconds:Math.round(performance.now()-started)});
  } catch (error) {
    results.push({name, status:'FAIL', assertions:assertions-before, milliseconds:Math.round(performance.now()-started), error:error.message});
  }
  globalThis.gc?.();
}

await test('built assets: size ceiling, gzip/parts/original identity', auditAssets);
await test('gzip route: actual decompression and exact bytes', async () => {
  const run = harness();
  await run.start();
  assertSuccess(run);
  equal(run.records.filter(record => record.file === manifest.gzip.file).length, 1, 'Gzip fetched once');
  equal(run.records.some(record => manifest.parts.some(part => part.file === record.file)), false, 'Raw parts not fetched on gzip route');
  await run.start();
  equal(run.state.engineStarts, 1, 'Repeated Play cannot launch another engine');
});
await test('raw fallback: absent DecompressionStream and Request input', async () => {
  const run = harness({noDecompressionStream:true, requestInput:true});
  await run.start();
  assertSuccess(run);
  equal(run.records.some(record => record.file === manifest.gzip.file), false, 'Fallback does not request gzip');
  for (const part of manifest.parts) equal(run.records.filter(record => record.file === part.file).length, 1, 'Each raw part fetched once');
});
await test('adapter boundary: unrelated, cross-origin and HEAD pass through', async () => {
  const run = harness();
  const init = {headers:{'X-Test':'untouched'}};
  const pck = new Request(new URL('./index.pck', baseUrl));
  await run.context.fetch(pck, init);
  equal(run.records[0].input, pck, 'Unrelated Request object preserved');
  equal(run.records[0].init, init, 'Unrelated init object preserved');
  await run.context.fetch('https://different.invalid/game/index.wasm');
  equal(run.records[1].url, 'https://different.invalid/game/index.wasm', 'Other-origin WASM untouched');
  await run.context.fetch(new URL('./index.wasm', baseUrl), {method:'HEAD'});
  equal(run.records[2].method, 'HEAD', 'HEAD is not intercepted');
  equal(run.records.length, 3, 'No manifest/chunk fetch for nonmatching requests');
  equal(run.errors.length, 0, 'Passthrough does not alter error UI');
});
await test('same-size gzip corruption fails SHA before delivery', async () => {
  const run = harness({corruptFile:manifest.gzip.file});
  await run.start();
  assertFailure(run, /Runtime hash mismatch/);
  equal(run.state.runtimeReads, 0, 'Corrupt bytes never reach the mock consumer');
});
await test('missing second raw part shows recoverable error', async () => {
  const run = harness({noDecompressionStream:true, missingFile:manifest.parts[1].file});
  await run.start();
  assertFailure(run, /Runtime download failed: 404/);
  equal(run.state.runtimeReads, 0, 'No partial synthetic WASM response is delivered');
});
await test('truncated gzip fails expected length', async () => {
  const run = harness({truncateFile:manifest.gzip.file});
  await run.start();
  assertFailure(run, /Runtime size mismatch/);
});
await test('overlong gzip fails size ceiling during reading', async () => {
  const run = harness({overlongFile:manifest.gzip.file});
  await run.start();
  assertFailure(run, /Runtime exceeds expected size/);
});
await test('mid-stream body reader error is surfaced', async () => {
  const run = harness({readerErrorFile:manifest.gzip.file});
  await run.start();
  assertFailure(run, /Injected body reader failure/);
});
await test('whole-runtime hash is checked after decompression', async () => {
  const run = harness({wrongFinalHash:true});
  await run.start();
  assertFailure(run, /Runtime hash mismatch/);
  equal(run.state.runtimeReads, 0, 'Wrong final hash never reaches the mock consumer');
});
await test('missing manifest produces error and reload action', async () => {
  const run = harness({missingFile:'runtime-manifest.json'});
  await run.start();
  assertFailure(run, /Missing runtime manifest/);
});
await test('missing Engine script produces error before initialization', async () => {
  const run = harness({noEngine:true});
  await run.start();
  assertFailure(run, /Engine script did not load/);
  equal(run.state.engineConstructions, 0, 'No Engine created');
  equal(run.records.length, 0, 'No asset requests attempted');
});
await test('WebGL unavailable: clear compatibility message, no launch', async () => {
  const run = harness({noWebGL:true});
  await run.start();
  matches(run.elements.get('load-text').textContent, /WebGL 2/, 'Compatibility limitation shown');
  equal(run.elements.get('loader').hidden, false, 'Compatibility message remains visible');
  equal(run.elements.get('start').hidden, true, 'Unsupported start action hidden');
  equal(run.state.engineConstructions, 0, 'Unsupported engine not constructed');
  equal(run.records.length, 0, 'No needless download');
  equal(run.errors.length, 0, 'Unsupported feature is not a runtime exception');
  ok(run.context.fetch !== run.installedFetch, 'Native fetch restored');
});
await test('startup watchdog: visible timeout, late success ignored', async () => {
  const run = harness({hangEngine:true});
  const playing = run.start();
  await new Promise(resolve => setImmediate(resolve));
  run.fireWatchdog();
  assertFailure(run, /Runtime startup timeout/);
  ok(run.state.lateResolve, 'Mock engine is waiting');
  run.state.lateResolve();
  await playing;
  equal(run.elements.get('loader').hidden, false, 'Late resolution cannot dismiss failure');
  equal(run.elements.get('canvas').style.visibility, 'hidden', 'Late resolution cannot reveal canvas');
});

const failed = results.filter(result => result.status === 'FAIL');
console.log(JSON.stringify({
  scope:'Node vm transport tests only; mocked DOM/Engine/fetch. No browser, WebGL or actual Godot execution.',
  tested_at_utc:new Date().toISOString(),
  node:process.version,
  dist,
  metadata,
  cases:results.length,
  passed:results.length-failed.length,
  failed:failed.length,
  assertions,
  results
}, null, 2));
if (failed.length) process.exitCode = 1;
