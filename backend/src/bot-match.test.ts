import { describe, expect, it } from 'vitest';
import {
  RULES_VERSION,
  chooseBotBurial,
  chooseBotLead,
  chooseBotPlay,
  gameConfig,
  nextDealer,
  PLAYER_COUNTS,
  teamAt,
  startTrick,
} from '@tractor/rules';
import type { Card, Rank } from '@tractor/rules';
import {
  botLeadContext,
  commandBotMatch,
  newBotMatch,
  progressBotDeclarations,
} from './bot-match.js';
import type { BotCommand, BotMatch } from './bot-match.js';
import { botView } from './bot-routes.js';
import { buildApp } from './app.js';
import { heuristicPolicy } from './bot-policy.js';
import type { BotPolicy } from './bot-policy.js';

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

describe('public bot lead knowledge', () => {
  it('uses the complete injected policy for bot turns and watch suggestions', () => {
    const pick = seeded(13);
    let match = newBotMatch(4, 0, pick, 'expert');
    const seats = new Set<number>();
    const calls = { follow: 0, declare: 0, bury: 0 };
    const base = heuristicPolicy('standard');
    const policy: BotPolicy = {
      ...base,
      follow: (...args) => {
        calls.follow++;
        return base.follow(...args);
      },
      declare: (...args) => {
        calls.declare++;
        expect(args[1].length).toBeLessThanOrEqual(1);
        return base.declare(...args);
      },
      bury: (...args) => {
        calls.bury++;
        return base.bury(...args);
      },
      lead: (hand, trump, context) => {
        seats.add(context.seat!);
        expect(context).not.toHaveProperty('hands');
        expect(context.cardsRemaining).toBe(hand.length);
        return chooseBotLead(hand, trump, context);
      },
    };
    match = progressBotDeclarations(match, 400, policy);
    for (let step = 0; step < 300 && match.state.phase !== 'finished'; step++) {
      const view = botView(
        '00000000-0000-4000-8000-000000000001',
        match,
        step,
        policy,
      );
      const command = decision(match);
      if (command.action === 'play') command.cardIds = view.suggestion;
      match = commandBotMatch(
        match,
        command,
        match.state.declarationDeadline + 1,
        pick,
        policy,
      );
    }
    expect(match.state.phase).toBe('finished');
    expect(calls.follow).toBeGreaterThan(0);
    expect(calls.declare).toBeGreaterThan(0);
    expect(calls.bury).toBeGreaterThan(0);
    expect(seats.has(0)).toBe(true);
    expect([...seats].some((seat) => seat !== 0)).toBe(true);
  });

  it('keeps the selected difficulty when starting the next round', () => {
    const match = newBotMatch(4, 0, seeded(3), 'sharp');
    const settled = {
      defenderScore: 0,
      kittyBasePoints: 0,
      kittyMultiplier: 1,
      kittyPoints: 0,
      outcome: {} as never,
      levels: match.state.levels,
      attackingTeam: match.state.attackingTeam,
      rolesSwapped: false,
      jackReset: false,
      winner: null,
    } as NonNullable<BotMatch['settlement']>;
    const next = commandBotMatch(
      { ...match, settlement: settled },
      { action: 'next-round' },
      100,
      seeded(4),
    );
    expect(next.difficulty).toBe('sharp');
  });

  it('uses opponent trump exhaustion in the suggestion used by watch mode', () => {
    const match = newBotMatch(4, 0, seeded(2));
    const trump = { level: '2', suit: 'spades' } as const;
    const make = (id: string, suit: 'clubs' | 'spades'): Card => ({
      id,
      kind: 'suited',
      rank: '3',
      suit,
    });
    const hands = [
      [make('s0', 'spades'), make('c0', 'clubs')],
      [make('c1', 'clubs'), make('c1b', 'clubs')],
      [make('s2', 'spades'), make('c2', 'clubs')],
      [make('c3', 'clubs'), make('c3b', 'clubs')],
    ];
    match.state = {
      ...match.state,
      phase: 'tricks',
      trump,
      hands,
      trick: startTrick({
        playerCount: 4,
        hands,
        trump,
        attackingTeam: 'A',
        leaderSeat: 0,
      }),
    };
    const id = '11111111-1111-4111-8111-111111111111';
    expect(botView(id, match, 0).suggestion).toEqual(['s0']);
    match.history = [
      {
        round: match.state.round,
        number: 1,
        trump,
        winnerSeat: 0,
        points: 0,
        defenderPoints: 0,
        penalty: 0,
        plays: [
          { seat: 0, cards: [make('old-s0', 'spades')], matchesLead: true },
          { seat: 1, cards: [make('old-c1', 'clubs')], matchesLead: false },
          { seat: 2, cards: [make('old-s2', 'spades')], matchesLead: true },
          { seat: 3, cards: [make('old-c3', 'clubs')], matchesLead: false },
        ],
      },
    ];
    expect(botView(id, match, 0).suggestion).toEqual(['c0']);
  });

  it('tracks each seat, detects partial follows, and excludes earlier rounds', () => {
    const match = newBotMatch(4, 0, seeded(1));
    const trump = { level: '2', suit: 'spades' } as const;
    const spade: Card = { id: 's', kind: 'suited', rank: '3', suit: 'spades' };
    const club: Card = { id: 'c', kind: 'suited', rank: '3', suit: 'clubs' };
    const item = {
      round: match.state.round,
      number: 1,
      trump,
      winnerSeat: 0,
      points: 0,
      defenderPoints: 0,
      penalty: 0,
      plays: [
        { seat: 0, cards: [spade, spade], matchesLead: true },
        { seat: 1, cards: [spade, club], matchesLead: false },
      ],
    };
    match.history = [
      {
        ...item,
        round: match.state.round - 1,
        plays: [
          item.plays[0]!,
          { seat: 3, cards: [club, club], matchesLead: false },
        ],
      },
      item,
      { ...item, number: 2 },
    ];
    const context = botLeadContext(match, 2);
    expect(context.knownVoids).toEqual([{ seat: 1, category: 'trump' }]);
    expect(context.seenCards).toHaveLength(8);
    expect(context.seat).toBe(2);
    expect(context.playerCount).toBe(4);
  });
});

describe('complete bot matches', () => {
  it.each(PLAYER_COUNTS)(
    'completes a Standard match with %i seats',
    (playerCount) => {
      let match = newBotMatch(playerCount, 0, seeded(playerCount), 'standard');
      let now = 0;
      let steps = 0;
      while (match.state.phase !== 'finished' && steps++ < 500) {
        now = Math.max(now + 1, match.state.declarationDeadline);
        match = commandBotMatch(
          match,
          decision(match),
          now,
          seeded(playerCount),
        );
      }
      expect(match.state.phase).toBe('finished');
      expect(match.history.length).toBeGreaterThan(0);
    },
  );

  it.each(PLAYER_COUNTS)(
    'completes a Sharp match with %i seats',
    (playerCount) => {
      let match = newBotMatch(
        playerCount,
        0,
        seeded(playerCount + 100),
        'sharp',
      );
      let now = 0;
      let steps = 0;
      while (match.state.phase !== 'finished' && steps++ < 500) {
        now = Math.max(now + 1, match.state.declarationDeadline);
        match = commandBotMatch(
          match,
          decision(match),
          now,
          seeded(playerCount + 100),
        );
      }
      expect(match.state.phase).toBe('finished');
      expect(match.history.length).toBeGreaterThan(0);
    },
  );

  it.each(PLAYER_COUNTS)(
    'completes a Relaxed match with %i seats',
    (playerCount) => {
      let match = newBotMatch(
        playerCount,
        0,
        seeded(playerCount + 200),
        'relaxed',
      );
      let now = 0;
      let steps = 0;
      while (match.state.phase !== 'finished' && steps++ < 500) {
        now = Math.max(now + 1, match.state.declarationDeadline);
        match = commandBotMatch(
          match,
          decision(match),
          now,
          seeded(playerCount + 200),
        );
      }
      expect(match.state.phase).toBe('finished');
      expect(match.history.length).toBeGreaterThan(0);
    },
  );

  it.each(['relaxed', 'standard', 'sharp', 'expert'] as const)(
    'completes a seeded full match at %s difficulty',
    (difficulty) => {
      let match = newBotMatch(4, 0, seeded(4242), difficulty);
      let now = 0;
      let steps = 0;
      while (match.state.phase !== 'finished' && steps++ < 250) {
        now = Math.max(now + 1, match.state.declarationDeadline);
        match = commandBotMatch(match, decision(match), now, seeded(4242));
      }
      expect(match.state.phase).toBe('finished');
      expect(match.history.length).toBeGreaterThan(0);
      expect(match.replay?.deals.length).toBeGreaterThan(0);
    },
  );

  it('starts a quick match at a random level and marks it as one-round mode', () => {
    const quick = newBotMatch(4, 0, () => 0, 'standard', true);
    expect(quick.quickMatch).toBe(true);
    expect(quick.state.round).toBe(1);
    expect(quick.state.levels).toEqual({ A: '2', B: '2' });
    let firstPick = true;
    const high = newBotMatch(
      4,
      0,
      (max) => (firstPick ? ((firstPick = false), 12) : Math.min(max - 1, 0)),
      'standard',
      true,
    );
    expect(high.state.levels).toEqual({ A: 'A', B: 'A' });
    expect(
      botView('00000000-0000-4000-8000-000000000000', quick, 0).quickMatch,
    ).toBe(true);
  });

  it('records the immutable starting deal for deterministic replay', () => {
    const match = newBotMatch(4, 1234, () => 0);
    expect(match.replay?.rulesVersion).toBe(RULES_VERSION);
    expect(match.replay?.createdAt).toBe(1234);
    expect(match.replay?.initialHands).toHaveLength(4);
    expect(match.replay?.initialKitty).toHaveLength(8);
    expect(match.replay?.deals).toHaveLength(1);
    expect(
      match.replay!.initialHands.flat().length +
        (match.replay?.initialKitty.length ?? 0),
    ).toBe(108);
  });

  it.each(['relaxed', 'standard', 'sharp', 'expert'] as const)(
    'keeps the %s bot difficulty on the match',
    (difficulty) => {
      expect(newBotMatch(4, 0, () => 0, difficulty).difficulty).toBe(
        difficulty,
      );
    },
  );

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
      commandBotMatch(
        match,
        { action: 'declare', cardIds: [] },
        match.state.declarationDeadline,
        pick,
      ),
    ).toThrow('closed');
    expect(JSON.stringify(match)).toBe(snapshot);
  });

  it('does not let bots declare from cards that have not been dealt', () => {
    const match = newBotMatch(4, 1000, seeded(91));
    expect(match.state.declaration).toBeNull();
    const early = progressBotDeclarations(match, 1000 + 399);
    expect(early.state.declaration).toBeNull();
    const progressed = progressBotDeclarations(match, 1000 + 400 * 25);
    expect(progressed.state.declaration).not.toBeNull();
    const declaration = progressed.state.declaration!;
    expect(progressed.replay!.deals[0]!.exposedCards).toEqual(
      expect.arrayContaining(
        declaration.cardIds.map((cardId) => ({
          cardId,
          seat: declaration.playerSeat,
        })),
      ),
    );
    expect(match.replay!.deals[0]!.exposedCards).toBeUndefined();
    expect(
      JSON.parse(JSON.stringify(progressed)).replay.deals[0].exposedCards,
    ).toEqual(progressed.replay!.deals[0]!.exposedCards);
    expect(progressed.state.declarationDeadline).toBeGreaterThanOrEqual(
      1000 + 25 * 400 + 8000,
    );
  });

  it('projects only the human hand and public plays, and reveals the kitty only to its dealer', () => {
    const pick = seeded(37);
    let match = newBotMatch(4, 0, pick);
    const id = '11111111-1111-4111-8111-111111111111';
    const initial = botView(id, match, 0);
    expect(initial.hand).toEqual(match.state.hands[0]);
    expect(JSON.stringify(initial)).not.toContain('"hands"');
    expect(JSON.stringify(initial)).not.toContain('"kitty":');
    expect(initial.seenRankCounts).toMatchObject({ '2': 0, A: 0 });
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
      expect(view.difficulty).toBe('standard');
      const url = `/api/bot-matches/${view.id}`;
      const replay = await app.inject(`${url}/replay`);
      expect(replay.statusCode).toBe(200);
      expect(replay.headers['content-disposition']).toContain('attachment');
      expect(replay.json().format).toBe(1);
      expect(replay.json().replay.rulesVersion).toBe(RULES_VERSION);
      expect(replay.json().events).toEqual([]);
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
      const archive = await app.inject(`${url}/replay`);
      const behavior = await app.inject(`${url}/behavior.csv`);
      expect(behavior.statusCode).toBe(200);
      expect(behavior.body).toContain(
        'led_category,had_led_category,used_trump',
      );
      expect(behavior.body).toContain('winner_before,winner_after,winner_seat');
      expect(behavior.body).toContain('trick_points,rating');
      const summary = await app.inject(`${url}/behavior-summary.csv`);
      expect(summary.statusCode).toBe(200);
      expect(summary.body).toContain('necessary_ruff,failed_ruff');
      expect(summary.body).toContain('team_points_captured');
      expect(
        archive
          .json()
          .events.some((event: { actor?: string }) => event.actor === 'bot'),
      ).toBe(true);
      expect(
        archive
          .json()
          .events.some(
            (event: { action: string; actor?: string }) =>
              event.action === 'trick-complete' && event.actor === 'system',
          ),
      ).toBe(true);
    } finally {
      await app.close();
      await other.close();
    }
  });
});

it('allows calls on dealt cards without shortening the slower deal or post-deal window', () => {
  for (let seed = 1; seed <= 1000; seed++) {
    const pick = seeded(seed);
    const match = newBotMatch(4, 1000, pick);
    const view = botView('11111111-1111-4111-8111-111111111111', match, 0);
    const option = view.declarationOptions.find((option) =>
      option.cardIds.every(
        (id) => match.state.hands[0]!.findIndex((card) => card.id === id) < 20,
      ),
    );
    if (!option) continue;
    expect(match.state.declarationDeadline).toBe(19000);
    const availableAt =
      1000 +
      400 *
        (Math.max(
          ...option.cardIds.map((id) =>
            match.state.hands[0]!.findIndex((card) => card.id === id),
          ),
        ) +
          1);
    const command: BotCommand = { action: 'declare', cardIds: option.cardIds };
    expect(() =>
      commandBotMatch(match, command, availableAt - 1, pick),
    ).toThrow('Wait for those cards');
    const declared = commandBotMatch(match, command, availableAt, pick);
    expect(declared.state.declarationDeadline).toBeGreaterThanOrEqual(19000);
    expect(declared.dealingStartedAt).toBe(1000);
    expect(() =>
      commandBotMatch(declared, { action: 'advance' }, 18999, pick),
    ).toThrow('still open');
    return;
  }
  throw new Error('No seeded early-call fixture found');
});
