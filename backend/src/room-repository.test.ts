import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { MemoryRoomRepository } from './room-repository.js';

it('does not publish a mutated room when its snapshot cannot be written', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'tractor-room-failure-'));
  const store = new MemoryRoomRepository(() => 100, directory);
  await store.initialize();
  const room = {
    code: 'ABCDEF',
    createdAt: 100,
    revision: 1,
    matchRevision: 0,
  };
  try {
    await store.create(room, {});
    mkdirSync(join(directory, 'ABCDEF.json.tmp'));
    await expect(
      store.transact(room.code, (current, save) => {
        current!.revision++;
        save(current!, {});
      }),
    ).rejects.toThrow();
    expect(await store.read(room.code)).toEqual(room);
    await store.close();
    const restored = new MemoryRoomRepository(() => 100, directory);
    await restored.initialize();
    expect(await restored.read(room.code)).toEqual(room);
    await restored.close();
  } finally {
    await store.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
