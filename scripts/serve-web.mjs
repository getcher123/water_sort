import { createServer } from 'node:http';
import { createReadStream, existsSync, realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { root } from './godot-command.mjs';

const dist = path.join(root, 'dist');
const port = Number(process.env.PORT || 4173);
if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error('PORT must be an integer between 1024 and 65535.');
}
if (!existsSync(path.join(dist, 'index.html'))) {
  throw new Error('Missing Web build. Run npm run build first.');
}
const base = realpathSync(dist);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
  '.gz': 'application/gzip',
  '.bin': 'application/octet-stream',
  '.pck': 'application/octet-stream',
};

const server = createServer((request, response) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }
  try {
    let pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if (pathname === '/water_sort') {
      response.writeHead(308, { Location: '/water_sort/' }).end();
      return;
    }
    if (pathname.startsWith('/water_sort/')) pathname = pathname.slice('/water_sort'.length);
    if (pathname.endsWith('/')) pathname += 'index.html';
    const candidate = path.resolve(base, '.' + pathname);
    if (!candidate.startsWith(base + path.sep)) throw new Error('Outside build directory');
    const file = realpathSync(candidate);
    if (!file.startsWith(base + path.sep)) throw new Error('Outside build directory');
    const stat = statSync(file);
    if (!stat.isFile()) throw new Error('Not a file');
    response.writeHead(200, {
      'Content-Type': types[path.extname(file)] || 'application/octet-stream',
      'Content-Length': stat.size,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    // .gz is an opaque payload: the game loader decompresses it explicitly.
    if (request.method === 'HEAD') response.end();
    else createReadStream(file).on('error', () => response.destroy()).pipe(response);
  } catch {
    response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Jelly Sort: http://127.0.0.1:${port}/`);
  console.log(`Pages subpath test: http://127.0.0.1:${port}/water_sort/`);
});
server.on('error', error => {
  console.error(error.message);
  process.exitCode = 1;
});
