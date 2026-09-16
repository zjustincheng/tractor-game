import { afterEach, describe, expect, it } from 'vitest';
import { previewResponseSchema } from '@tractor/protocol';
import { gameConfig, PLAYER_COUNTS } from '@tractor/rules';
import { buildApp } from './app.js';

const apps: ReturnType<typeof buildApp>[] = [];
function app() {
  const instance = buildApp({ pickIndex: () => 0 });
  apps.push(instance);
  return instance;
}
afterEach(async () => {
  await Promise.all(apps.splice(0).map((instance) => instance.close()));
});

describe('practice API', () => {
  it('reports health and accurately describes supported capabilities', async () => {
    const server = app();
    expect((await server.inject('/api/health')).json().status).toBe('ok');
    const response = await server.inject('/api/config');
    expect(response.json().capabilities).toEqual({
      practicePreview: true,
      practiceTricks: true,
      multiplayer: true,
    });
    expect(response.json().modes).toHaveLength(4);
  });
  it.each(PLAYER_COUNTS)(
    'projects only the viewer’s hand for %i players',
    async (playerCount) => {
      const response = await app().inject({
        method: 'POST',
        url: '/api/practice-preview',
        payload: { playerCount, level: '5', trumpSuit: null },
      });
      expect(response.statusCode).toBe(200);
      const view = previewResponseSchema.parse(response.json());
      const config = gameConfig(playerCount);
      expect(view.hand).toHaveLength(config.handSize);
      expect(view.seats).toHaveLength(playerCount);
      expect(
        view.seats.every((seat) => seat.cardCount === config.handSize),
      ).toBe(true);
      expect(view.kittyCount).toBe(config.kittySize);
      expect(Object.keys(view).sort()).toEqual([
        'hand',
        'id',
        'kind',
        'kittyCount',
        'rulesVersion',
        'seats',
        'settings',
        'viewerSeat',
      ]);
      expect(response.body).not.toContain('"kitty":');
      expect(response.body).not.toContain('"hands":');
      expect(response.headers['cache-control']).toBe('no-store');
    },
  );
  it.each([
    { playerCount: 5, level: '2', trumpSuit: 'spades' },
    { playerCount: '4', level: '2', trumpSuit: 'spades' },
    { playerCount: 4, level: '1', trumpSuit: 'spades' },
    { playerCount: 4, level: '2', trumpSuit: 'bogus' },
    { playerCount: 4, level: '2', trumpSuit: 'spades', viewerSeat: 1 },
    {},
  ])('rejects invalid settings %#', async (payload) => {
    const response = await app().inject({
      method: 'POST',
      url: '/api/practice-preview',
      payload,
    });
    expect(response.statusCode).toBe(400);
    expect(response.json().code).toBe('INVALID_SETTINGS');
  });
  it('limits payloads and returns safe errors for malformed JSON', async () => {
    const server = app();
    const response = await server.inject({
      method: 'POST',
      url: '/api/practice-preview',
      payload: 'x'.repeat(5000),
      headers: { 'content-type': 'application/json' },
    });
    expect(response.statusCode).toBe(413);
    const malformed = await server.inject({
      method: 'POST',
      url: '/api/practice-preview',
      payload: '{oops',
      headers: { 'content-type': 'application/json' },
    });
    expect(malformed.statusCode).toBe(400);
    expect(malformed.json()).toEqual({
      code: 'INVALID_REQUEST',
      message: 'The request could not be accepted.',
    });
  });

  it('serves deterministic trick exercises and validates attempts server-side', async () => {
    const server = app();
    const list = await server.inject('/api/practice-tricks');
    expect(list.statusCode).toBe(200);
    expect(list.json().exercises).toHaveLength(7);
    for (const item of list.json().exercises as { id: string }[]) {
      const itemResponse = await server.inject(
        `/api/practice-tricks/${item.id}`,
      );
      expect(itemResponse.statusCode).toBe(200);
      expect(itemResponse.json().id).toBe(item.id);
    }
    const exercise = await server.inject('/api/practice-tricks/follow-a-pair');
    expect(exercise.statusCode).toBe(200);
    const view = exercise.json();
    expect(view.hand).toHaveLength(5);
    expect(view.nextSeat).toBe(view.viewerSeat);
    const invalid = await server.inject({
      method: 'POST',
      url: '/api/practice-tricks/follow-a-pair/attempt',
      payload: { cardIds: [view.hand[0].id] },
    });
    expect(invalid.statusCode).toBe(422);
    expect(invalid.json().code).toBe('WRONG_CARD_COUNT');
    const validCards = view.hand
      .slice(0, 4)
      .map((card: { id: string }) => card.id);
    const accepted = await server.inject({
      method: 'POST',
      url: '/api/practice-tricks/follow-a-pair/attempt',
      payload: { cardIds: validCards },
    });
    expect(accepted.statusCode).toBe(200);
    expect(accepted.json().accepted).toBe(true);
    expect(accepted.json().matchesLead).toBe(false);
  });

  it('creates a private practice round with legal declaration options', async () => {
    const server = app();
    const created = await server.inject({
      method: 'POST',
      url: '/api/practice-rounds',
      payload: { playerCount: 4, attackingTeam: 'A' },
    });
    expect(created.statusCode).toBe(200);
    const view = created.json();
    expect(view.phase).toBe('declaration');
    expect(view.hand).toHaveLength(25);
    expect(view.seats).toHaveLength(4);
    expect(view.kittyCount).toBe(8);
    expect(view.declarationOptions.length).toBeGreaterThan(0);
    const id = view.id as string;
    const option = view.declarationOptions[0];
    const declared = await server.inject({
      method: 'POST',
      url: `/api/practice-rounds/${id}/declaration`,
      payload: { cardIds: option.cardIds },
    });
    expect(declared.statusCode).toBe(200);
    expect(declared.json().declaration).toMatchObject({
      kind: option.kind,
      multiplicity: option.multiplicity,
    });
    expect(declared.json().declarationDeadline).toBeGreaterThan(Date.now());
    expect(declared.json().kittyCount).toBe(8);
    expect(declared.json().hand).toHaveLength(25);
    expect(
      (await server.inject('/api/practice-rounds/missing')).statusCode,
    ).toBe(404);
  });
});
