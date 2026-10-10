import process from 'node:process';
import console from 'node:console';
import { spawnSync } from 'node:child_process';

if (!process.env.TEST_DATABASE_URL) {
  console.error(
    'Set TEST_DATABASE_URL to a local test database before running PostgreSQL tests.',
  );
  process.exit(1);
}
const result = spawnSync(
  process.execPath,
  [
    'node_modules/vitest/vitest.mjs',
    'run',
    'backend/src/postgres-room-store.test.ts',
  ],
  { stdio: 'inherit' },
);
process.exit(result.status ?? 1);
