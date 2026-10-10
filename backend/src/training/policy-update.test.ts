import { describe, expect, it } from 'vitest';
import { newPolicy, policyProbabilities } from './learned-policy.js';
import type { PolicyExperience } from './learned-policy.js';
import { newOptimizer, updateFromOutcomes } from './policy-update.js';
import { seededRandom } from './self-play.js';
import {
  discountedReturns,
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
  roundReward,
} from './policy-training.js';
import type { RoundSettlement } from '@tractor/rules';

const options = [0, 1].map((i) => ({
  cardIds: [String(i)],
  features: Array.from({ length: 22 }, (_, j) =>
    j === 0 ? (i === 0 ? -1 : 1) : 0,
  ),
  prior: i === 0 ? 0.75 : 0,
}));

describe('outcome learning', () => {
  it('deduplicates repeated experience references and can disable comparisons', () => {
    const model = newPolicy(seededRandom(42));
    const a: PolicyExperience = {
      options,
      chosen: 0,
      advantage: 0.3,
      comparisons: [{ better: 1, worse: 0, weight: 1 }],
    };
    const b: PolicyExperience = { options, chosen: 1, advantage: -0.2 };
    expect(updateFromOutcomes(model, [a, b, a])).toEqual(
      updateFromOutcomes(model, [a, b]),
    );
    expect(updateFromOutcomes(model, [a], newOptimizer(), 0)).toEqual(
      updateFromOutcomes(
        model,
        [{ options, chosen: 0, advantage: 0.3 }],
        newOptimizer(),
        0,
      ),
    );
  });

  it('uses counterfactual pairs only when the outcome agrees with them', () => {
    const model = newPolicy(seededRandom(42));
    const base = {
      options,
      chosen: 1,
      comparisons: [{ better: 1, worse: 0, weight: 1 }],
    } satisfies PolicyExperience;
    const agreeing = updateFromOutcomes(
      model,
      [{ ...base, advantage: 1 }],
      newOptimizer(),
      1,
    );
    const agreeingWithoutPair = updateFromOutcomes(
      model,
      [{ ...base, advantage: 1 }],
      newOptimizer(),
      0,
    );
    const neutral = updateFromOutcomes(
      model,
      [{ ...base, advantage: 0 }],
      newOptimizer(),
      1,
    );
    const neutralWithoutPair = updateFromOutcomes(
      model,
      [{ ...base, advantage: 0 }],
      newOptimizer(),
      0,
    );
    const conflicting = updateFromOutcomes(
      model,
      [{ ...base, advantage: -1 }],
      newOptimizer(),
      1,
    );
    const conflictingWithoutPair = updateFromOutcomes(
      model,
      [{ ...base, advantage: -1 }],
      newOptimizer(),
      0,
    );
    expect(agreeing.model).not.toEqual(agreeingWithoutPair.model);
    expect(neutral.model).toEqual(neutralWithoutPair.model);
    expect(conflicting.model).toEqual(conflictingWithoutPair.model);
  });
  it('follows an explicit teacher even when the baseline prefers another action', () => {
    const model = newPolicy(seededRandom(42));
    const before = policyProbabilities(model, options)[1]!;
    const explicit = updateFromOutcomes(model, [
      { options, chosen: 0, teacherIndex: 1, teacherWeight: 1 },
    ]);
    const baseline = updateFromOutcomes(model, [
      { options, chosen: 0, teacherWeight: 1 },
    ]);
    expect(policyProbabilities(explicit.model, options)[1]).toBeGreaterThan(
      before,
    );
    expect(policyProbabilities(baseline.model, options)[1]).toBeLessThan(
      before,
    );
  });
  it('learns a rewarded alternative, overriding the starting preference without labels', () => {
    let model = newPolicy(seededRandom(42));
    let optimizer = newOptimizer();
    const pick = seededRandom(81);
    expect(policyProbabilities(model, options)[0]).toBeGreaterThan(0.5);
    for (let generation = 0; generation < 35; generation++) {
      const p = policyProbabilities(model, options, 0.15);
      const experiences: PolicyExperience[] = Array.from(
        { length: 128 },
        () => {
          const chosen = pick(1000000) / 1000000 < p[0]! ? 0 : 1;
          return {
            options,
            chosen,
            temperature: 0.15,
            advantage: chosen === 1 ? 1 : -1,
          };
        },
      );
      const update = updateFromOutcomes(model, experiences, optimizer);
      expect(update.kl).toBeLessThanOrEqual(0.01);
      model = update.model;
      optimizer = update.optimizer;
    }
    expect(policyProbabilities(model, options)[1]).toBeGreaterThan(0.5);
  }, 20000);

  it('resumes optimizer state exactly and refuses corrupted variance', () => {
    const config = {
      seed: 42,
      playerCounts: [4] as const,
      trainSeeds: 1,
      validationSeeds: 1,
      maxRounds: 1,
    };
    const checkpoint = newPolicyCheckpoint({ ...config, playerCounts: [4] });
    const samples = [{ options, chosen: 1, advantage: 1 }];
    const first = updateFromOutcomes(checkpoint.leadLearner, samples);
    checkpoint.leadLearner = first.model;
    checkpoint.leadOptimizer = first.optimizer;
    const resumed = parsePolicyCheckpoint(
      JSON.parse(JSON.stringify(checkpoint)),
    );
    expect(
      updateFromOutcomes(resumed.leadLearner, samples, resumed.leadOptimizer),
    ).toEqual(updateFromOutcomes(first.model, samples, first.optimizer));
    resumed.leadOptimizer!.second.output[0] = -1;
    expect(() => parsePolicyCheckpoint(resumed)).toThrow(/variance/);
  });

  it('assigns delayed rewards only to earlier rounds and reverses team credit', () => {
    expect(discountedReturns([1, -1, 2])).toEqual([1, -1, 2]);
    expect(discountedReturns([1, -1, 2], 0.5)).toEqual([1, 0, 2]);
    const settlement = {
      levels: { A: '4', B: '2' },
      defenderScore: 0,
      winner: null,
    } as RoundSettlement;
    const a = roundReward({ A: '2', B: '2' }, settlement, 'A', 4, 'A');
    const b = roundReward({ A: '2', B: '2' }, settlement, 'B', 4, 'A');
    expect(a).toBeGreaterThan(0);
    expect(a).toBe(-b);
  });
});
