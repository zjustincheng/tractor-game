import { describe, expect, it, vi } from 'vitest';
import { DEFAULT_BOT_LEAD_WEIGHTS, chooseBotOpeningLead } from '@tractor/rules';
import type { Card } from '@tractor/rules';
import { heuristicPolicy } from '../bot-policy.js';
import { learnedBotPolicy } from './bot-policy.js';
import { newPolicy } from './learned-policy.js';
import { playTrainingMatch, seededRandom } from './self-play.js';

const hand: Card[] = [
  { id: 'c3', kind: 'suited', suit: 'clubs', rank: '3' },
  { id: 'sA', kind: 'suited', suit: 'spades', rank: 'A' },
];
const trump = { level: '2', suit: 'spades' } as const;
const context = {
  seat: 0,
  playerCount: 4,
  cardsRemaining: 2,
  role: 'attackers' as const,
  defenderScore: 0,
  swapThreshold: 80,
};

describe('deployed policy adapters', () => {
  it('keeps learned leads identical across difficulty and hidden-hand inputs', () => {
    const policy = learnedBotPolicy(
      newPolicy(seededRandom(9)),
      newPolicy(seededRandom(10)),
    );
    const expected = policy.lead(hand, trump, context, []);
    expect(
      policy.lead(hand, trump, { ...context, beliefSearch: true }, [
        hand,
        hand,
        hand,
      ]),
    ).toEqual(expected);
  });
  it('uses the exact Sharp opening rule including its search context', () => {
    const otherHands = [hand, hand, hand];
    expect(
      heuristicPolicy('sharp').lead(hand, trump, context, otherHands),
    ).toEqual(
      chooseBotOpeningLead(
        hand,
        otherHands,
        trump,
        { ...context, beliefSearch: true },
        'sharp',
      ),
    );
  });
  it('runs all four deployed learned decisions against Sharp in the simulator', () => {
    const candidate = learnedBotPolicy(
      newPolicy(seededRandom(9)),
      newPolicy(seededRandom(10)),
    );
    const spies = [
      vi.spyOn(candidate, 'lead'),
      vi.spyOn(candidate, 'follow'),
      vi.spyOn(candidate, 'declare'),
      vi.spyOn(candidate, 'bury'),
    ];
    for (const candidateTeam of ['A', 'B'] as const) {
      const result = playTrainingMatch({
        seed: 42,
        playerCount: 4,
        candidateTeam,
        candidate: DEFAULT_BOT_LEAD_WEIGHTS,
        opponent: DEFAULT_BOT_LEAD_WEIGHTS,
        candidatePolicy: candidate,
        opponentPolicy: heuristicPolicy('sharp'),
        maxRounds: 1,
      });
      expect(result.rounds).toBe(1);
      expect(result.decisions).toBeGreaterThan(0);
    }
    for (const spy of spies) expect(spy).toHaveBeenCalled();
  }, 20000);
});
