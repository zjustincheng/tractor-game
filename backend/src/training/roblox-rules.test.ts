import { describe, expect, it } from 'vitest';
import type { Card, MatchState } from '@tractor/rules';
import { robloxJokerPairs } from './roblox-rules.js';
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
