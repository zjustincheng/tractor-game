import { describe, expect, it } from 'vitest';
import {
  parseHistoricalPolicyGame,
  summarizePolicyHistory,
} from './policy-evaluation.js';
import type { HistoricalPolicyGame } from './policy-evaluation.js';
import {
  pointMargin,
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
  recoverChampionMarginSamples,
  policyPasses,
  shouldRollbackLearner,
  summarizePaired,
} from './policy-training.js';
import type { PolicyCheckpoint } from './policy-training.js';
import type { SelfPlayResult } from './self-play.js';

function result(seed: number, candidateTeam: 'A' | 'B'): SelfPlayResult {
  return {
    seed,
    playerCount: 4,
    candidateTeam,
    winner: candidateTeam,
    rounds: 1,
    decisions: 20,
    truncated: false,
    levels: candidateTeam === 'A' ? { A: '4', B: '2' } : { A: '2', B: '4' },
    settlements: [
      {
        attackingTeam: candidateTeam,
        defenderScore: 0,
      },
    ] as SelfPlayResult['settlements'],
  };
}

describe('policy evaluation history', () => {
  it('promotes level improvements with bounded point uncertainty, but rejects meaningful point losses', () => {
    const evaluation = {
      games: 256,
      wins: 157,
      losses: 99,
      truncated: 0,
      winRate: 157 / 256,
      pairs: 128,
      marginLow: -0.0067586,
      levelMarginLow: 0.96875,
    };
    expect(policyPasses(evaluation)).toBe(true);
    expect(policyPasses({ ...evaluation, marginLow: -0.011 })).toBe(false);
    expect(policyPasses({ ...evaluation, levelMarginLow: 0 })).toBe(false);
    expect(policyPasses({ ...evaluation, marginLow: NaN })).toBe(false);
    expect(shouldRollbackLearner(Array(128).fill(1.68), true)).toBe(false);
    expect(shouldRollbackLearner(Array(128).fill(-0.51), true)).toBe(true);
  });

  it('keeps paired point and level samples separate and counts rounds descriptively', () => {
    const evaluation = summarizePaired(
      [result(1, 'A'), result(1, 'B')],
      1,
      true,
    );
    expect(evaluation.levelMarginSamples).toEqual([2]);
    expect(evaluation.roundWins).toBe(2);
    expect(evaluation.completedRounds).toBe(2);
    const checkpoint = newPolicyCheckpoint({
      seed: 1,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 32,
      maxRounds: 60,
    });
    checkpoint.championMarginSamples = Array(128).fill(-0.9);
    const loaded = parsePolicyCheckpoint(checkpoint);
    expect(loaded.championLevelMarginSamples).toEqual([]);
    expect(
      shouldRollbackLearner(loaded.championLevelMarginSamples!, true),
    ).toBe(false);
    checkpoint.championLevelMarginSamples = Array(64).fill(1.5);
    expect(
      parsePolicyCheckpoint(checkpoint).championLevelMarginSamples,
    ).toEqual(checkpoint.championLevelMarginSamples);
    checkpoint.championLevelMarginSamples = [NaN];
    expect(() => parsePolicyCheckpoint(checkpoint)).toThrow();
  });
  it('discards point-margin caches from before the role-swap fix', () => {
    const checkpoint = newPolicyCheckpoint({
      seed: 1,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 32,
      maxRounds: 60,
    });
    checkpoint.championMarginSamples = [0.5];
    expect(parsePolicyCheckpoint(checkpoint).championMarginSamples).toEqual([
      0.5,
    ]);
    delete checkpoint.pointMarginVersion;
    expect(parsePolicyCheckpoint(checkpoint).championMarginSamples).toEqual([]);
  });
  it.each([
    ['A', 'A', true, 120, 0.5],
    ['B', 'A', true, 120, -0.5],
    ['A', 'A', false, 60, 0.25],
    ['B', 'A', false, 60, -0.25],
  ] as const)(
    'credits the completed round to %s when next attackers are %s and swapped=%s',
    (candidateTeam, attackingTeam, rolesSwapped, defenderScore, expected) => {
      const game = result(42, candidateTeam);
      game.settlements[0] = {
        ...game.settlements[0]!,
        attackingTeam,
        rolesSwapped,
        defenderScore,
      };
      expect(pointMargin(game)).toBe(expected);
    },
  );
  it('reports paired point and level margin intervals separately', () => {
    const a = result(42, 'A');
    const b = result(42, 'B');
    const rows = [a, b].map((game) => ({
      file: 'run/games.jsonl',
      generation: 12,
      policyVersion: 'contextual-leads-v12-play-style',
      result: game,
    }));
    const summary = summarizePolicyHistory(rows).groups[0]!.evaluation;
    expect(summary).toMatchObject({
      pairs: 1,
      marginMean: 1,
      marginLow: 1,
      marginHigh: 1,
      levelMarginMean: 2,
      levelMarginLow: 2,
      levelMarginHigh: 2,
    });
  });

  it('keeps mirrored games paired within a run and generation in pooled history', () => {
    const entries: HistoricalPolicyGame[] = [
      {
        file: 'run-a/games.jsonl',
        generation: 2,
        policyVersion: 'v',
        result: result(10, 'A'),
      },
      {
        file: 'run-a/games.jsonl',
        generation: 2,
        policyVersion: 'v',
        result: result(10, 'B'),
      },
      {
        file: 'run-a/games.jsonl',
        generation: 3,
        policyVersion: 'v',
        result: result(10, 'A'),
      },
      {
        file: 'run-a/games.jsonl',
        generation: 3,
        policyVersion: 'v',
        result: result(10, 'B'),
      },
    ];
    const summary = summarizePolicyHistory(entries);
    expect(summary.groups).toHaveLength(2);
    expect(summary.pooled.pairs).toBe(2);
  });

  it('accepts only complete validation-baseline rows from games.jsonl', () => {
    const a = result(7, 'A');
    expect(
      parseHistoricalPolicyGame(
        {
          phase: 'validation-baseline',
          generation: 4,
          policyVersion: 'contextual-leads-v12-play-style',
          result: a,
        },
        'run/games.jsonl',
      ),
    ).toEqual({
      file: 'run/games.jsonl',
      generation: 4,
      policyVersion: 'contextual-leads-v12-play-style',
      result: a,
    });
    expect(
      parseHistoricalPolicyGame(
        { phase: 'practice', generation: 4, result: a },
        'run/games.jsonl',
      ),
    ).toBeNull();
    expect(
      parseHistoricalPolicyGame(
        {
          phase: 'validation-baseline',
          generation: 4,
          policyVersion: 'old',
          result: a,
        },
        'run/games.jsonl',
      ),
    ).toBeNull();
    expect(
      parseHistoricalPolicyGame(
        { phase: 'validation-baseline', generation: 4, result: a },
        'run/games.jsonl',
        'contextual-leads-v12-play-style',
      )?.generation,
    ).toBe(4);
  });

  it('rebuilds pooled champion evidence from paired log rows after the last reset', () => {
    const checkpoint = {
      generation: 2,
      reports: [
        {
          generation: 1,
          promoted: true,
          learnerReset: false,
          vsChampion: {},
        },
        {
          generation: 2,
          promoted: false,
          learnerReset: false,
          vsChampion: { marginSamples: [999] },
        },
      ],
    } as unknown as PolicyCheckpoint;
    const a = {
      ...result(99, 'A'),
      settlements: [{ attackingTeam: 'A' as const, defenderScore: 120 }],
    };
    const b = {
      ...result(99, 'B'),
      settlements: [{ attackingTeam: 'B' as const, defenderScore: 120 }],
    };
    const recovered = recoverChampionMarginSamples(checkpoint, [
      { generation: 1, phase: 'validation-champion', result: a },
      { generation: 1, phase: 'validation-champion', result: b },
      { generation: 2, phase: 'validation-champion', result: a },
      { generation: 2, phase: 'validation-champion', result: b },
    ]);
    expect(recovered).toEqual([-0.5]);
  });
});
