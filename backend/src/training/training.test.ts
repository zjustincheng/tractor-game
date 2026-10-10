import { describe, expect, it } from 'vitest';
import {
  DEFAULT_BOT_LEAD_WEIGHTS,
  PLAYER_COUNTS,
  chooseBotLead,
} from '@tractor/rules';
import type { Card } from '@tractor/rules';
import { playTrainingMatch } from './self-play.js';
import {
  generationSeeds,
  mutateWeights,
  newCheckpoint,
  parseCheckpoint,
  parseConfig,
  parseWeights,
  shouldPromote,
  summarize,
  trainGeneration,
} from './optimizer.js';
import type { Evaluation } from './optimizer.js';
import { scorePostGameTrajectories } from './post-game-scorer.js';
import type { TrainingDecision } from './self-play.js';

const config = {
  seed: 42,
  playerCounts: [4] as const,
  trainSeeds: 1,
  validationSeeds: 1,
  maxRounds: 60,
};
const weights = DEFAULT_BOT_LEAD_WEIGHTS;

describe('self-play matches', () => {
  it.each(PLAYER_COUNTS)(
    'plays %i seats through a match winner, not just one round',
    (playerCount) => {
      const seats = new Set<number>();
      const result = playTrainingMatch({
        seed: 20042,
        playerCount,
        candidateTeam: 'A',
        candidate: weights,
        opponent: weights,
        maxRounds: 60,
        onDecision: (decision) => {
          seats.add(decision.seat);
          // The recorder exposes only this seat's hand; chosen cards must come from it.
          expect(
            decision.chosenCards.every((id) =>
              decision.hand.some((card) => card.id === id),
            ),
          ).toBe(true);
          expect(decision).not.toHaveProperty('hands');
          expect(decision).not.toHaveProperty('kitty');
        },
      });
      expect(seats.size).toBe(playerCount);
      expect(result.truncated).toBe(false);
      expect(result.winner).not.toBeNull();
      expect(result.rounds).toBeGreaterThan(1);
      expect(
        result.settlements.slice(0, -1).every((round) => round.winner === null),
      ).toBe(true);
      expect(result.settlements.at(-1)?.winner).toBe(result.winner);
      expect(result.settlements).toHaveLength(result.rounds);
    },
    60000,
  );

  it('reproduces identical seeded play and marks capped matches without a reward', () => {
    const options = {
      seed: 9,
      playerCount: 4 as const,
      candidateTeam: 'A' as const,
      candidate: weights,
      opponent: weights,
      maxRounds: 1,
    };
    const first = playTrainingMatch(options);
    expect(playTrainingMatch(options)).toEqual(first);
    expect(first).toMatchObject({ rounds: 1, winner: null, truncated: true });
    expect(summarize([first])).toEqual({
      games: 1,
      wins: 0,
      losses: 0,
      truncated: 1,
      winRate: 0,
    });
  });

  it('actually changes a legal decision when trained weights change', () => {
    const hand: Card[] = [
      { id: 'trump', kind: 'suited', rank: '3', suit: 'spades' },
      { id: 'ace', kind: 'suited', rank: 'A', suit: 'clubs' },
    ];
    const trump = { level: '2' as const, suit: 'spades' as const };
    const context = {
      role: 'attackers' as const,
      defenderScore: 0,
      swapThreshold: 80,
      cardsRemaining: 2,
    };
    expect(chooseBotLead(hand, trump, context)).toEqual(['trump']);
    expect(
      chooseBotLead(hand, trump, {
        ...context,
        weights: { trump: 0, endgamePower: 0 },
      }),
    ).toEqual(['ace']);
  });
});

describe('outcome-based optimization', () => {
  it('derives a small outcome-based lead adjustment only from completed games', () => {
    const decision = (
      structured: boolean,
      role: 'attackers' | 'defenders' = 'attackers',
    ): TrainingDecision => {
      const hand: Card[] = structured
        ? [
            { id: 'c3a', kind: 'suited', rank: '3', suit: 'clubs' },
            { id: 'c3b', kind: 'suited', rank: '3', suit: 'clubs' },
            { id: 'c4a', kind: 'suited', rank: '4', suit: 'clubs' },
            { id: 'c4b', kind: 'suited', rank: '4', suit: 'clubs' },
          ]
        : [{ id: 'c4', kind: 'suited', rank: '4', suit: 'clubs' }];
      return {
        round: 1,
        trick: 1,
        seat: 0,
        team: 'A',
        role,
        hand,
        trump: { level: '2', suit: 'spades' },
        publicPlays: [],
        seenCards: [],
        knownVoids: [],
        defenderScore: 0,
        winnerBefore: null,
        chosenCards: hand.map((card) => card.id),
        winnerAfter: 0,
      };
    };
    const trajectories = [
      ...Array.from({ length: 6 }, () => ({
        candidateTeam: 'A' as const,
        winner: 'A' as const,
        decisions: [decision(true)],
      })),
      ...Array.from({ length: 6 }, () => ({
        candidateTeam: 'A' as const,
        winner: 'B' as const,
        decisions: [decision(false)],
      })),
    ];
    const scored = scorePostGameTrajectories(weights, trajectories);
    expect(scored.analysis).toMatchObject({
      matches: 12,
      wins: 6,
      losses: 6,
      leadDecisions: 12,
      applied: true,
    });
    expect(scored.analysis.associations.structure.correlation).toBeGreaterThan(
      0,
    );
    expect(scored.weights.structure).toBeGreaterThan(weights.structure);
    expect(scored.weights.jokerBig).toBe(weights.jokerBig);
    expect(
      scorePostGameTrajectories(weights, trajectories.slice(0, 11)).analysis
        .applied,
    ).toBe(false);
  });

  it('mutates bounded coefficients deterministically without mutating the incumbent', () => {
    const parent = { ...weights };
    const candidate = mutateWeights(parent, 43);
    expect(candidate).toEqual(mutateWeights(parent, 43));
    expect(candidate).not.toEqual(parent);
    expect(parseWeights(candidate)).toEqual(candidate);
    expect(parent).toEqual(weights);
    expect(mutateWeights(parent, 44)).not.toEqual(candidate);
  });

  it('separates training, validation and successive generation seed sets', () => {
    const input = parseConfig({
      ...config,
      trainSeeds: 10000,
      validationSeeds: 10000,
      seed: 0xffffffff,
    });
    const seeds = [
      generationSeeds(input, 1, false),
      generationSeeds(input, 1, true),
      generationSeeds(input, 2, false),
      generationSeeds(input, 2, true),
    ].flat();
    expect(new Set(seeds).size).toBe(40000);
  });

  it('requires improvement over the incumbent on validation and rejects truncation', () => {
    const incumbent: Evaluation = {
      games: 20,
      wins: 10,
      losses: 10,
      truncated: 0,
      winRate: 0.5,
    };
    const candidate = { ...incumbent, wins: 13, losses: 7, winRate: 0.65 };
    expect(shouldPromote(candidate, incumbent)).toBe(true);
    expect(shouldPromote(incumbent, incumbent)).toBe(false);
    expect(shouldPromote({ ...candidate, truncated: 1 }, incumbent)).toBe(
      false,
    );
    expect(shouldPromote(candidate, { ...incumbent, winRate: 0.7 })).toBe(
      false,
    );
    expect(shouldPromote(candidate, { ...incumbent, games: 22 })).toBe(false);
  });

  it('resumes from a serialized checkpoint with the same next generation', () => {
    const initial = newCheckpoint(parseConfig({ ...config, maxRounds: 1 }));
    const first = trainGeneration(initial);
    expect(first.reports[0]).toMatchObject({
      accepted: false,
      training: { games: 2, truncated: 2 },
      postGameAnalysis: { applied: false },
      validationCandidate: null,
    });
    expect(first.weights).toEqual(initial.weights);
    const resumed = trainGeneration(
      parseCheckpoint(JSON.parse(JSON.stringify(first))),
    );
    expect(resumed).toEqual(trainGeneration(first));
    expect(resumed.generation).toBe(2);
  }, 20000);

  it('rejects incompatible or corrupt checkpoints and unreasonable configuration', () => {
    const initial = newCheckpoint(parseConfig(config));
    expect(() =>
      parseCheckpoint({ ...initial, policyVersion: 'different-policy' }),
    ).toThrow(/incompatible/);
    expect(() =>
      parseCheckpoint({ ...initial, weights: { ...weights, trump: NaN } }),
    ).toThrow(/weight/);
    expect(() => parseWeights({ ...weights, typo: 1 })).toThrow(/keys/);
    expect(() => parseConfig({ ...config, playerCounts: [5] })).toThrow(
      /Players/,
    );
    expect(() => parseConfig({ ...config, maxRounds: 0 })).toThrow(/maxRounds/);
    expect(() => parseConfig({ ...config, trainSeeds: 10001 })).toThrow(
      /limits/,
    );
  });
});
