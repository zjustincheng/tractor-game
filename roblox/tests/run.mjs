import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import process from 'node:process';
import console from 'node:console';
const root = fileURLToPath(new URL('../../', import.meta.url));
const interpreter = process.argv[2] || 'lua';

// Luau and Lua both cap a function at 200 live locals. The client LocalScript
// is one large chunk, so require spare slots to keep additions from silently
// breaking compilation in Studio.
const HEADROOM = 12;
const client = readFileSync(
  new URL('../src/client/Main.client.luau', import.meta.url),
  'utf8',
);
const extras = Array.from({ length: HEADROOM }, (_, i) => `headroom${i}`);
let level = '=';
while (client.includes(`]${level}]`)) level += '=';
const probeDir = mkdtempSync(join(tmpdir(), 'tractor-headroom-'));
try {
  const probe = join(probeDir, 'probe.lua');
  writeFileSync(
    probe,
    `local chunk, err = load([${level}[${client}\nlocal ${extras.join(', ')}\n]${level}])\n` +
      `assert(chunk, err)\nprint('PASS: client compiles with ${HEADROOM} spare top-level locals')\n`,
  );
  const output = execFileSync(interpreter, [probe], { encoding: 'utf8' });
  if (!output.includes('PASS:'))
    throw new Error(
      `Client has fewer than ${HEADROOM} spare top-level locals: ${output}`,
    );
  console.log(output.trim());
} finally {
  rmSync(probeDir, { recursive: true, force: true });
}
for (const suite of [
  'profile',
  'declare',
  'quads',
  'tracker',
  'pass',
  'streak',
  'ranked',
  'practice',
  'trained',
  'setup',
  'moves',
  'chaodi',
  'matchmaker',
  'multiplayer',
  'tables',
  'crossserver',
  'matchserver',
  'server',
  'layout',
  'client',
]) {
  const output = execFileSync(interpreter, [`roblox/tests/${suite}.lua`], {
    cwd: root,
    encoding: 'utf8',
  });
  // Fengari can report Lua assertion errors with exit code 0. Require completion.
  if (!output.includes('PASS:'))
    throw new Error(`${suite} did not complete successfully`);
  console.log(output.trim());
}
console.log(
  execFileSync(
    process.execPath,
    ['--import', 'tsx', 'roblox/tests/parity.mjs', interpreter],
    { cwd: root, encoding: 'utf8' },
  ).trim(),
);
