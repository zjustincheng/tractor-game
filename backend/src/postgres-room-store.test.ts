import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from './app.js';
import { PostgresRoomStore } from './postgres-room-store.js';
import type { Room } from './room-routes.js';

const databaseUrl = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseUrl)(
  'PostgreSQL rooms across backend instances',
  () => {
    const schema = `room_test_${randomUUID().replaceAll('-', '')}`;
    const admin = new Pool({ connectionString: databaseUrl });
    let url: string;
    let now = 100000;
    let first: ReturnType<typeof buildApp>;
    let second: ReturnType<typeof buildApp>;
    let store: PostgresRoomStore<Room>;
    beforeAll(async () => {
      await admin.query(`create schema ${schema}`);
      const connection = new URL(databaseUrl!);
      connection.searchParams.set('options', `-c search_path=${schema}`);
      url = connection.toString();
      first = buildApp({ databaseUrl: url, now: () => now });
      second = buildApp({ databaseUrl: url, now: () => now });
      store = new PostgresRoomStore<Room>(url, () => now);
      await Promise.all([first.ready(), second.ready()]);
    });
    afterAll(async () => {
      await Promise.all([first?.close(), second?.close(), store?.close()]);
      await admin.query(`drop schema ${schema} cascade`);
      await admin.end();
    });

    it('serializes joins and commands, protects hands, and restores committed moves', async () => {
      expect(
        (await first.inject('/api/health')).json().multiplayerPersistence,
      ).toBe('postgres');
      const created = (
        await first.inject({
          method: 'POST',
          url: '/api/rooms',
          payload: { playerCount: 4, displayName: 'Host' },
        })
      ).json();
      const code = created.room.code;
      const joins = await Promise.all(
        Array.from({ length: 6 }, (_, i) =>
          (i % 2 ? first : second).inject({
            method: 'POST',
            url: `/api/rooms/${code}/join`,
            payload: { displayName: `Player ${i}` },
          }),
        ),
      );
      expect(
        joins.filter((response) => response.statusCode === 409),
      ).toHaveLength(3);
      const players = [
        created,
        ...joins
          .filter((response) => response.statusCode === 200)
          .map((response) => response.json()),
      ].sort((a, b) => a.room.viewerSeat - b.room.viewerSeat);
      expect(players.map((player) => player.room.viewerSeat)).toEqual([
        0, 1, 2, 3,
      ]);
      const ready = await Promise.all(
        players.map((player, i) =>
          (i % 2 ? first : second).inject({
            method: 'POST',
            url: `/api/rooms/${code}/ready`,
            payload: { token: player.playerToken, ready: true },
          }),
        ),
      );
      expect(ready.map((response) => response.statusCode)).toEqual([
        200, 200, 200, 200,
      ]);
      const views = await Promise.all(
        players.map(async (player) =>
          (
            await second.inject(
              `/api/rooms/${code}/game?token=${player.playerToken}`,
            )
          ).json(),
        ),
      );
      expect(
        new Set(
          views.flatMap((view) =>
            view.hand.map((card: { id: string }) => card.id),
          ),
        ).size,
      ).toBe(100);
      for (const view of views) {
        expect(view.hands).toBeUndefined();
        expect(view.kitty).toBeUndefined();
        expect(
          view.players.every(
            (player: object) => !('token' in player) && !('hand' in player),
          ),
        ).toBe(true);
      }
      expect(
        (await first.inject(`/api/rooms/${code}/game?token=wrong`)).statusCode,
      ).toBe(404);
      now += 9000;
      const command = {
        method: 'POST' as const,
        url: `/api/rooms/${code}/game/commands`,
        payload: {
          action: 'advance',
          requestId: randomUUID(),
          token: created.playerToken,
          revision: 1,
        },
      };
      const raced = await Promise.all([
        first.inject(command),
        second.inject(command),
      ]);
      expect(raced.map((response) => response.statusCode).sort()).toEqual([
        200, 409,
      ]);
      const accepted = raced
        .find((response) => response.statusCode === 200)!
        .json();
      expect((await first.inject(command)).statusCode).toBe(200);
      const snapshot = await store.read(code);
      const rows = await store.pool.query(
        'select revision, payload from tractor_room_events where code = $1 order by revision',
        [code],
      );
      expect(rows.rows).toHaveLength(9);
      expect(rows.rows.at(-1).payload).toMatchObject({
        action: 'advance',
        matchRevision: 2,
      });
      await first.close();
      first = buildApp({ databaseUrl: url, now: () => now });
      expect(
        (
          await first.inject(
            `/api/rooms/${code}/game?token=${created.playerToken}`,
          )
        ).json(),
      ).toEqual(accepted);
      expect(await store.read(code)).toEqual(snapshot);
      expect(
        (
          await first.inject({
            method: 'POST',
            url: `/api/rooms/${code}/ready`,
            payload: { token: created.playerToken, ready: false },
          })
        ).statusCode,
      ).toBe(409);

      // An event insertion failure must also roll back the snapshot update.
      await store.pool.query(
        `alter table tractor_room_events add constraint reject_game_event check (not (payload ? 'action')) not valid`,
      );
      now += 9000;
      const failed = await second.inject({
        ...command,
        payload: { ...command.payload, revision: 2 },
      });
      expect(failed.statusCode).toBe(500);
      expect(await store.read(code)).toEqual(snapshot);
      await store.pool.query(
        'alter table tractor_room_events drop constraint reject_game_event',
      );
      const retry = await first.inject({
        ...command,
        payload: { ...command.payload, revision: 2 },
      });
      expect(retry.statusCode).toBe(200);
      expect(retry.json().phase).toBe('kitty');
      const kittyViews = await Promise.all(
        players.map(async (player) =>
          (
            await first.inject(
              `/api/rooms/${code}/game?token=${player.playerToken}`,
            )
          ).json(),
        ),
      );
      expect(kittyViews[0].hand).toHaveLength(33);
      for (const other of kittyViews.slice(1))
        expect(other.hand).toHaveLength(25);
      const kitty = (await store.read(code))!.match!.kitty;
      for (const card of kitty) {
        expect(
          kittyViews[0].hand.map((item: { id: string }) => item.id),
        ).toContain(card.id);
        for (const other of kittyViews.slice(1))
          expect(
            other.hand.map((item: { id: string }) => item.id),
          ).not.toContain(card.id);
      }

      expect(
        (
          await second.inject({
            ...command,
            payload: {
              action: 'bury',
              token: players[1].playerToken,
              revision: 3,
              cardIds: [],
            },
          })
        ).statusCode,
      ).toBe(403);
      const beforeExpiry = await store.read(code);
      now += 24 * 60 * 60 * 1000;
      expect(
        (await first.inject(`/api/rooms/${code}?token=${created.playerToken}`))
          .statusCode,
      ).toBe(404);
      expect(
        (
          await second.inject({
            ...command,
            payload: { ...command.payload, revision: 3 },
          })
        ).statusCode,
      ).toBe(404);
      const afterExpiry = await store.pool.query(
        'select payload from tractor_rooms where code = $1',
        [code],
      );
      expect(afterExpiry.rows[0].payload).toEqual(beforeExpiry);
    });

    it('reserves a new invite code atomically and rolls back thrown mutations', async () => {
      const room = {
        code: 'ABCDEF',
        createdAt: now,
        revision: 1,
        matchRevision: 0,
      } as Room;
      const results = await Promise.all([
        store.create(room, { type: 'create' }),
        store.create(room, { type: 'create' }),
      ]);
      expect(results.sort()).toEqual([false, true]);
      await expect(
        store.transact(room.code, (current, save) => {
          current!.revision++;
          save(current!, { type: 'change' });
          throw new Error('validation failed');
        }),
      ).rejects.toThrow('validation failed');
      expect(await store.read(room.code)).toEqual(room);
      const events = await store.pool.query(
        'select * from tractor_room_events where code = $1',
        [room.code],
      );
      expect(events.rows).toHaveLength(1);
    });
  },
);
