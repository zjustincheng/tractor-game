import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from './app.js';
import { MatchStore } from './match-store.js';
import { newBotMatch } from './bot-match.js';

const folders: string[] = [];
function directory() {
  const folder = mkdtempSync(join(tmpdir(), 'tractor-save-test-'));
  folders.push(folder);
  return folder;
}
afterEach(() => {
  for (const folder of folders.splice(0))
    rmSync(folder, { recursive: true, force: true });
});

describe('durable solo matches', () => {
  it('restores completed tricks, settlement, revision, and next-round progression after restart', async () => {
    const saveDirectory = directory();
    let now = 0;
    let app = buildApp({ saveDirectory, now: () => now, pickIndex: () => 0 });
    try {
      const created = await app.inject({
        method: 'POST',
        url: '/api/bot-matches',
        payload: { playerCount: 4 },
      });
      expect(created.statusCode).toBe(200);
      let view = created.json();
      const url = `/api/bot-matches/${view.id}`;
      for (let step = 0; view.phase !== 'finished' && step < 100; step++) {
        now = Math.max(now + 1, view.declarationDeadline);
        const action =
          view.phase === 'declaration' || view.trickComplete
            ? 'advance'
            : view.phase === 'kitty'
              ? 'bury'
              : 'play';
        const response = await app.inject({
          method: 'POST',
          url: `${url}/commands`,
          payload: {
            action,
            cardIds: view.suggestion,
            revision: view.revision,
          },
        });
        expect(response.statusCode, response.body).toBe(200);
        view = response.json();
      }
      expect(view.phase).toBe('finished');
      expect(view.history.length).toBe(view.trickNumber);
      expect(view.rounds).toHaveLength(1);
      expect(
        view.history.flatMap((item: { plays: { cards: unknown[] }[] }) =>
          item.plays.flatMap((play) => play.cards),
        ),
      ).toHaveLength(100);
      await app.close();
      app = buildApp({ saveDirectory, now: () => now, pickIndex: () => 0 });
      const restored = await app.inject(url);
      expect(restored.statusCode).toBe(200);
      expect(restored.json()).toEqual(view);
      const next = await app.inject({
        method: 'POST',
        url: `${url}/commands`,
        payload: { action: 'next-round', revision: view.revision },
      });
      expect(next.statusCode).toBe(200);
      expect(next.json().history).toEqual(view.history);
      expect(next.json().round).toBe(2);
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `${url}/commands`,
            payload: { action: 'next-round', revision: view.revision },
          })
        ).statusCode,
      ).toBe(409);
    } finally {
      await app.close();
    }
  });

  it('leaves the previous snapshot and memory unchanged if a replacement cannot be written', () => {
    const folder = directory();
    const store = new MatchStore(folder);
    const id = '11111111-1111-4111-8111-111111111111';
    const original = {
      match: newBotMatch(4, 0, () => 0),
      revision: 0,
      touched: 0,
    };
    store.set(id, original);
    const saved = readFileSync(join(folder, `${id}.json`), 'utf8');
    mkdirSync(join(folder, `${id}.json.tmp`));
    expect(() => store.set(id, { ...original, revision: 1 })).toThrow();
    expect(store.get(id)).toEqual(original);
    expect(readFileSync(join(folder, `${id}.json`), 'utf8')).toBe(saved);
  });

  it('fails clearly on corrupt snapshots without overwriting them', () => {
    const folder = directory();
    const file = join(folder, '11111111-1111-4111-8111-111111111111.json');
    writeFileSync(file, 'broken');
    expect(() => buildApp({ saveDirectory: folder })).toThrow(
      'Cannot restore match',
    );
    expect(readFileSync(file, 'utf8')).toBe('broken');
  });

  it('expires snapshots after thirty idle days', async () => {
    const folder = directory();
    let now = 0;
    const app = buildApp({
      saveDirectory: folder,
      now: () => now,
      pickIndex: () => 0,
    });
    try {
      const created = await app.inject({
        method: 'POST',
        url: '/api/bot-matches',
        payload: { playerCount: 4 },
      });
      now = 31 * 24 * 60 * 60 * 1000;
      expect(
        (await app.inject(`/api/bot-matches/${created.json().id}`)).statusCode,
      ).toBe(404);
      expect(new MatchStore(folder).size).toBe(0);
    } finally {
      await app.close();
    }
  });
});
