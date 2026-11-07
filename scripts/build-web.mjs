import { readFileSync, writeFileSync, mkdirSync, copyFileSync, renameSync, existsSync, readdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import path from 'node:path';
import { root, project, importAndTest, runGodot } from './godot-command.mjs';

const dist = path.join(root, 'dist');
mkdirSync(dist, {recursive:true});
mkdirSync(path.join(root, '.local'), {recursive:true});
importAndTest();
runGodot(['--export-release', 'Web', path.join(dist, 'index.html')], 300000);

// The Godot runtime exceeds the static host's 25 MiB per-file limit.
// Use gzip without server Content-Encoding; the shell explicitly decompresses it.
// Smaller raw chunks remain an older-browser fallback. Game/engine code is unchanged.
const wasmPath = path.join(dist, 'index.wasm');
const wasm = readFileSync(wasmPath);
const sha = buffer => createHash('sha256').update(buffer).digest('hex');
const gzip = gzipSync(wasm, {level:6});
writeFileSync(path.join(dist, 'engine.wasm.gz'), gzip);
const parts = [];
const chunkBytes = 20 * 1024 * 1024;
for (let start=0,index=1;start<wasm.length;start+=chunkBytes,index++) {
  const chunk = wasm.subarray(start,Math.min(start+chunkBytes,wasm.length));
  const file = `engine-part-${index}.bin`;
  writeFileSync(path.join(dist,file),chunk);
  parts.push({file,bytes:chunk.length,sha256:sha(chunk)});
}
writeFileSync(path.join(dist,'runtime-manifest.json'), JSON.stringify({bytes:wasm.length,sha256:sha(wasm),gzip:{file:'engine.wasm.gz',bytes:gzip.length,sha256:sha(gzip)},parts},null,2)+'\n');
renameSync(wasmPath,path.join(root,'.local','index.wasm'));
copyFileSync(path.join(project,'assets','icon.svg'),path.join(dist,'app-icon.svg'));
copyFileSync(path.join(project,'assets','Nunito-OFL.txt'),path.join(dist,'FONT-LICENSE.txt'));
copyFileSync(path.join(project,'assets','Godot-LICENSE.txt'),path.join(dist,'GODOT-LICENSE.txt'));
copyFileSync(path.join(project,'assets','Godot-COPYRIGHT.txt'),path.join(dist,'GODOT-COPYRIGHT.txt'));
for(const file of readdirSync(dist)) {
  const full = path.join(dist,file);
  if(statSync(full).isFile() && statSync(full).size > 25*1024*1024) throw new Error(`Static asset too large: ${file}`);
}
if (!existsSync(path.join(dist,'index.html')) || !existsSync(path.join(dist,'index.pck'))) throw new Error('Incomplete export');
console.log(JSON.stringify({ok:true,runtime_bytes:wasm.length,gzip_bytes:gzip.length,parts:parts.map(p=>({file:p.file,bytes:p.bytes})),output:dist}));
