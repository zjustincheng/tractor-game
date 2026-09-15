import { describe, expect, it } from 'vitest';
import {
  chooseBotBurial,
  chooseBotPlay,
  gameConfig,
  nextDealer,
  PLAYER_COUNTS,
  teamAt,
  startTrick,
} from '@tractor/rules';
import type { Card, Rank } from '@tractor/rules';
import { commandBotMatch, newBotMatch } from './bot-match.js';
import type { BotCommand, BotMatch } from './bot-match.js';
import { botView } from './bot-routes.js';
import { buildApp } from './app.js';

function seeded(seed: number) {
  return (max: number) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed % max;
  };
}

function decision(match: BotMatch): BotCommand {
  const { state } = match;
  if (state.phase === 'finished') return { action: 'next-round' };
  if (state.phase === 'kitty')
    return {
      action: 'bury',
      cardIds: chooseBotBurial(
        [...state.hands[0]!, ...state.kitty],
        state.kitty.length,
        state.trump!,
      ),
    };
  if (state.phase === 'declaration' || state.trick?.status === 'complete')
    return { action: 'advance' };
  return {
    action: 'play',
    cardIds: chooseBotPlay(
      state.hands[0]!,
      state.trick!.plays[0]?.components ?? null,
      state.trump!,
    ),
  };
}

describe('complete bot matches', () => {
  it('retains the failed-gamble explanation and penalty after bots finish the trick', () => {
    const pick = seeded(17);
    const match = newBotMatch(4, 0, pick);
    const hands = [
      ['3', '8'],
      ['4', '9'],
      ['6', 'Q'],
      ['7', 'A'],
    ].map((ranks, seat) =>
      ranks.map((rank): Card => ({
        id: `${seat}-${rank}`,
        kind: 'suited',
        rank: rank as Rank,
        suit: 'clubs',
      })),
    );
    const trump = { level: '2', suit: 'spades' } as const;
    const trick = startTrick({
      playerCount: 4,
      attackingTeam: 'A',
      leaderSeat: 0,
      hands,
      trump,
    });
    const ready: BotMatch = {
      ...match,
      state: { ...match.state, phase: 'tricks', hands, trump, trick },
    };
    const result = commandBotMatch(
      ready,
      { action: 'play', cardIds: ['0-3', '0-8'] },
      9000,
      pick,
    );
    expect(result.state.trick?.status).toBe('complete');
    expect(result.message).toContain('Gamble failed;');
    expect(result.message).toContain('won trick 1');
    expect(result.penalties).toBe(20);
    expect(result.state.hands[0]!.map((card) => card.id)).toEqual(['0-8']);
  });
  it.each(PLAYER_COUNTS)(
    'plays a %i-player match through A with card conservation and dealer rotation',
    (count) => {
      const pick = seeded(713 + count);
      let match = newBotMatch(count, 0, pick);
      let steps = 0;
      let seenRounds = 0;
      let now = 0;
      while (!match.settlement?.winner && steps++ < 12000) {
        const before = match;
        now = Math.max(now + 1, match.state.declarationDeadline);
        match = commandBotMatch(match, decision(match), now, pick);
        const { state } = match;
        if (state.phase === 'kitty' || state.phase === 'tricks')
          expect(teamAt(state.dealerSeat)).toBe(state.attackingTeam);
        if (state.trick?.status === 'complete') {
          expect(new Set(state.hands.map((hand) => hand.length)).size).toBe(1);
          expect(state.trick.plays).toHaveLength(count);
        }
        const remaining = [...state.hands.flat(), ...state.kitty];
        expect(new Set(remaining.map((card) => card.id)).size).toBe(
          remaining.length,
        );
        if (state.round !== before.state.round) {
          seenRounds++;
          expect(state.dealerSeat).toBe(
            nextDealer(
              before.state.dealerSeat,
              count,
              before.settlement!.rolesSwapped,
            ),
          );
          expect(state.levels).toEqual(before.settlement!.levels);
          expect(remaining).toHaveLength(gameConfig(count).cardCount);
        }
      }
      expect(steps).toBeLessThan(12000);
      expect(seenRounds).toBeGreaterThan(0);
      expect(match.settlement?.winner).not.toBeNull();
      expect(match.settlement!.levels[match.settlement!.winner!]).toBe('A');
    },
    30000,
  );

  it('rejects out-of-turn and early commands without consuming cards', () => {
    const pick = seeded(13);
    const match = newBotMatch(4, 0, pick);
    const snapshot = JSON.stringify(match);
    expect(() =>
      commandBotMatch(
        match,
        { action: 'play', cardIds: [match.state.hands[0]![0]!.id] },
        1,
        pick,
      ),
    ).toThrow('not your turn');
    expect(() =>
      commandBotMatch(match, { action: 'advance' }, 7999, pick),
    ).toThrow('still open');
    expect(() =>
      commandBotMatch(match, { action: 'declare', cardIds: [] }, 8000, pick),
    ).toThrow('closed');
    expect(JSON.stringify(match)).toBe(snapshot);
  });

  it('projects only the human hand and public plays, and reveals the kitty only to its dealer', () => {
    const pick = seeded(37);
    let match = newBotMatch(4, 0, pick);
    const id = '11111111-1111-4111-8111-111111111111';
    const initial = botView(id, match, 0);
    expect(initial.hand).toEqual(match.state.hands[0]);
    expect(JSON.stringify(initial)).not.toContain('"hands"');
    expect(JSON.stringify(initial)).not.toContain('"kitty":');
    match = {
      ...match,
      state: {
        ...match.state,
        phase: 'kitty',
        dealerSeat: 0,
        trump: { level: '2', suit: 'clubs' },
      },
    };
    expect(botView(id, match, 1).hand).toHaveLength(33);
    match = { ...match, state: { ...match.state, dealerSeat: 1 } };
    expect(botView(id, match, 2).hand).toHaveLength(25);
  });

  it('serves a complete round, rejects duplicate commands, and isolates app instances', async () => {
    let now = 0;
    const app = buildApp({ now: () => now, pickIndex: seeded(125) });
    const other = buildApp();
    try {
      const created = await app.inject({
        method: 'POST',
        url: '/api/bot-matches',
        payload: { playerCount: 4 },
      });
      expect(created.statusCode).toBe(200);
      let view = created.json();
      const url = `/api/bot-matches/${view.id}`;
      expect((await other.inject(url)).statusCode).toBe(404);
      const post = (payload: Record<string, unknown>) =>
        app.inject({ method: 'POST', url: `${url}/commands`, payload });
      expect(
        (await post({ action: 'advance', revision: view.revision })).statusCode,
      ).toBe(422);
      let steps = 0;
      while (view.phase !== 'finished' && steps++ < 200) {
        now = Math.max(now + 1, view.declarationDeadline);
        const action =
          view.phase === 'declaration' || view.trickComplete
            ? 'advance'
            : view.phase === 'kitty'
              ? 'bury'
              : 'play';
        const payload = {
          action,
          cardIds: view.suggestion,
          revision: view.revision,
        };
        const response = await post(payload);
        expect(response.statusCode, response.body).toBe(200);
        view = response.json();
        expect((await post(payload)).statusCode).toBe(409);
      }
      expect(view.phase).toBe('finished');
      expect(view.settlement).not.toBeNull();
      const next = await post({
        action: 'next-round',
        revision: view.revision,
      });
      expect(next.statusCode).toBe(200);
      expect(next.json().round).toBe(2);
    } finally {
      await app.close();
      await other.close();
    }
  });
});
