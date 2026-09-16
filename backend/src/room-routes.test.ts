import { describe, expect, it } from 'vitest';
import { buildApp } from './app.js';

describe('private room API', () => {
  it('creates, joins, protects, and starts a room when all seats are ready', async () => {
    const app = buildApp();
    try {
      const created = await app.inject({
        method: 'POST',
        url: '/api/rooms',
        payload: { playerCount: 4, displayName: 'Host' },
      });
      expect(created.statusCode).toBe(200);
      const first = created.json();
      const code = first.room.code;
      expect(first.room.viewerSeat).toBe(0);
      expect(first.room.players).toHaveLength(1);
      const initialEvents = await app.inject(
        `/api/rooms/${code}/events?token=${first.playerToken}`,
      );
      expect(initialEvents.statusCode).toBe(200);
      expect(initialEvents.json().events[0].type).toBe('room-created');
      const joined = [];
      for (const name of ['North', 'East', 'South']) {
        const response = await app.inject({
          method: 'POST',
          url: `/api/rooms/${code}/join`,
          payload: { displayName: name },
        });
        expect(response.statusCode).toBe(200);
        joined.push(response.json());
      }
      expect(
        joined[2].room.players.map((player: { seat: number }) => player.seat),
      ).toEqual([0, 1, 2, 3]);
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `/api/rooms/${code}/join`,
            payload: { displayName: 'Late' },
          })
        ).statusCode,
      ).toBe(409);
      expect((await app.inject(`/api/rooms/${code}`)).statusCode).toBe(404);
      const hostReady = await app.inject({
        method: 'POST',
        url: `/api/rooms/${code}/ready`,
        payload: { token: first.playerToken, ready: true },
      });
      expect(hostReady.statusCode).toBe(200);
      for (const item of joined) {
        const response = await app.inject({
          method: 'POST',
          url: `/api/rooms/${code}/ready`,
          payload: { token: item.playerToken, ready: true },
        });
        expect(response.statusCode).toBe(200);
      }
      expect(
        (
          await app.inject(`/api/rooms/${code}?token=${first.playerToken}`)
        ).json().started,
      ).toBe(true);
      const game = await app.inject(
        `/api/rooms/${code}/game?token=${first.playerToken}`,
      );
      expect(game.statusCode).toBe(200);
      expect(game.json().phase).toBe('declaration');
      expect(game.json().hand).toHaveLength(25);
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `/api/rooms/${code}/game/commands`,
            payload: {
              action: 'advance',
              token: joined[0].playerToken,
              revision: game.json().revision,
            },
          })
        ).statusCode,
      ).toBe(422);
      const events = await app.inject(
        `/api/rooms/${code}/events?token=${first.playerToken}&after=1`,
      );
      expect(events.statusCode).toBe(200);
      expect(
        events.json().events.map((item: { type: string }) => item.type),
      ).toContain('player-ready');
      expect(
        (
          await app.inject(`/api/rooms/${code}?token=${joined[0].playerToken}`)
        ).json().viewerSeat,
      ).toBe(1);
      expect(
        (
          await app.inject({
            method: 'POST',
            url: `/api/rooms/${code}/ready`,
            payload: {
              token: '11111111-1111-4111-8111-111111111111',
              ready: true,
            },
          })
        ).statusCode,
      ).toBe(404);
    } finally {
      await app.close();
    }
  });
});
