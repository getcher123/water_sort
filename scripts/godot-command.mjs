import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const project = path.join(root, 'godot');
export const godot = process.env.GODOT_BIN || 'godot';

export function checkGodotVersion() {
  const result = spawnSync(godot, ['--version'], { encoding: 'utf8', timeout: 15000 });
  if (result.error) {
    throw new Error(`Cannot run Godot. Install Godot 4.6.3 and add it to PATH or set GODOT_BIN. ${result.error.message}`);
  }
  const version = (result.stdout || '').trim();
  if (result.status !== 0 || !version.startsWith('4.6.3.stable.')) {
    throw new Error(`Expected Godot 4.6.3 stable; received: ${version || result.stderr || result.status}`);
  }
  console.log(`Using Godot ${version}`);
}

export function runGodot(args, timeout = 120000) {
  const result = spawnSync(godot, ['--headless', '--path', project, ...args], {
    cwd: project, stdio: 'inherit', timeout,
  });
  if (result.error) throw new Error(`Godot command failed: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`Godot failed (exit ${result.status}, signal ${result.signal || 'none'})`);
}

export function importAndTest() {
  checkGodotVersion();
  runGodot(['--editor', '--import', '--quit']);
  runGodot(['--script', 'tests/test_board.gd'], 25000);
  runGodot(['--script', 'tests/test_controller.gd'], 25000);
}
