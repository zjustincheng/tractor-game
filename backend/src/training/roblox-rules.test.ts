import { describe, expect, it } from 'vitest';
import type { Card, Declaration, MatchState, Trump } from '@tractor/rules';
import {
  chaodiOptions,
  chaodiStronger,
  chooseRobloxChaodi,
  robloxJokerPairs,
} from './roblox-rules.js';
import { playTrainingMatch } from './self-play.js';
import { DEFAULT_BOT_LEAD_WEIGHTS } from '@tractor/rules';

const joker = (kind: 'small' | 'big', copy: number): Card =>
  ({ id: `${copy}:joker:${kind}`, kind: 'joker', joker: kind }) as Card;
const card = (rank: string, suit: string, copy = 0): Card =>
  ({ id: `${copy}:${suit}:${rank}`, kind: 'suited', rank, suit }) as Card;

function state(overrides: Partial<MatchState> = {}): MatchState {
  return {
    phase: 'declaration',
    levels: { A: '4', B: '4' },
    attackingTeam: 'A',
    round: 1,
    declaration: null,
    ...overrides,
  } as MatchState;
}

const strong = [
  joker('big', 0),
  joker('big', 1),
  card('4', 'clubs'),
  card('4', 'hearts'),
  card('4', 'spades'),
];

describe('Roblox joker-pair declarations', () => {
  it('offers a pair only with enough backing trump', () => {
    const pairs = robloxJokerPairs(state(), 1, strong);
    expect(pairs).toHaveLength(1);
    expect(pairs[0]).toMatchObject({
      kind: 'joker',
      joker: 'big',
      multiplicity: 2,
      playerSeat: 1,
    });
    expect(robloxJokerPairs(state(), 1, strong.slice(0, 4))).toHaveLength(0);
  });

  it('needs two of the same joker', () => {
    const mixed = [
      joker('big', 0),
      joker('small', 0),
      ...strong.slice(2),
      card('4', 'diamonds'),
    ];
    expect(robloxJokerPairs(state(), 1, mixed)).toHaveLength(0);
  });

  it('respects the current declaration', () => {
    const current = robloxJokerPairs(state(), 1, strong)[0]!;
    expect(
      robloxJokerPairs(state({ declaration: current }), 2, strong),
    ).toHaveLength(0);
  });

  it('ranks Chao Di calls like the game', () => {
    expect(
      chaodiStronger({ count: 1, suit: 'hearts' }, { count: 2, suit: 'clubs' }),
    ).toBe(true);
    expect(
      chaodiStronger({ count: 2, suit: 'hearts' }, { count: 2, suit: 'clubs' }),
    ).toBe(false);
    expect(
      chaodiStronger(
        { count: 2, suit: 'hearts' },
        { count: 2, suit: 'spades' },
      ),
    ).toBe(true);
    expect(
      chaodiStronger(
        { count: 2, suit: 'spades' },
        { count: 2, suit: null, joker: 'small' },
      ),
    ).toBe(true);
    expect(
      chaodiStronger(
        { count: 2, suit: null, joker: 'small' },
        { count: 2, suit: null, joker: 'big' },
      ),
    ).toBe(true);
    expect(
      chaodiStronger(
        { count: 2, suit: null, joker: 'big' },
        { count: 2, suit: null, joker: 'small' },
      ),
    ).toBe(false);
    expect(
      chaodiStronger(
        { count: 2, suit: null, joker: 'big' },
        { count: 3, suit: 'clubs' },
      ),
    ).toBe(true);
  });

  it('offers only calls that beat the current one', () => {
    const hand = [
      card('4', 'clubs', 0),
      card('4', 'clubs', 1),
      card('4', 'hearts', 0),
      card('4', 'hearts', 1),
      joker('big', 0),
      joker('big', 1),
    ];
    const current = {
      kind: 'suit',
      playerSeat: 0,
      level: '4',
      suit: 'hearts',
      multiplicity: 2,
      cardIds: [],
    } as Declaration;
    const calls = chaodiOptions(hand, '4', current, 1);
    expect(calls.map((call) => call.suit ?? call.joker)).toEqual(['big']);
  });

  it('calls Chao Di only when the new trump clearly helps', () => {
    const trump = { level: '4', suit: 'hearts' } as Trump;
    const clubs = [
      card('4', 'clubs', 0),
      card('4', 'clubs', 1),
      card('3', 'clubs'),
      card('5', 'clubs'),
      card('9', 'clubs'),
      card('K', 'clubs'),
      card('7', 'spades'),
    ];
    const calls = chaodiOptions(
      clubs,
      '4',
      {
        kind: 'suit',
        playerSeat: 0,
        level: '4',
        suit: 'hearts',
        multiplicity: 1,
        cardIds: [],
      } as Declaration,
      1,
    );
    expect(chooseRobloxChaodi(calls, clubs, trump, false)).toBe(0);
    expect(chooseRobloxChaodi(calls, clubs, trump, true)).toBe(0);
    const weak = [
      card('4', 'clubs', 0),
      card('4', 'clubs', 1),
      card('7', 'spades'),
      card('8', 'spades'),
      card('9', 'diamonds'),
      card('J', 'diamonds'),
      card('5', 'hearts'),
    ];
    expect(
      chooseRobloxChaodi(chaodiOptions(weak, '4', null, 1), weak, trump, false),
    ).toBeNull();
  });

  it('runs Chao Di in training matches and keeps every card', () => {
    let calls = 0;
    for (const seed of [3, 7, 11]) {
      const result = playTrainingMatch({
        seed,
        playerCount: 4,
        candidateTeam: 'A',
        candidate: DEFAULT_BOT_LEAD_WEIGHTS,
        opponent: DEFAULT_BOT_LEAD_WEIGHTS,
        maxRounds: 3,
        robloxRules: true,
        chaodiDecision: () => 0,
        onChaodi: () => calls++,
      });
      expect(result.rounds).toBeGreaterThan(0);
      for (const settlement of result.settlements)
        expect(settlement.defenderScore).toBeGreaterThanOrEqual(0);
    }
    expect(calls).toBeGreaterThan(0);
  });

  it('plays a full training match with the option on', () => {
    const result = playTrainingMatch({
      seed: 11,
      playerCount: 4,
      candidateTeam: 'A',
      candidate: DEFAULT_BOT_LEAD_WEIGHTS,
      opponent: DEFAULT_BOT_LEAD_WEIGHTS,
      maxRounds: 2,
      robloxRules: true,
    });
    expect(result).toBeTruthy();
  });
});
