import {
  accumulatePolicyGradient,
  accumulateTeacherGradient,
  emptyGradient,
  parsePolicy,
  policyProbabilities,
} from './learned-policy.js';
import type { PolicyExperience, PolicyModel } from './learned-policy.js';

export interface PolicyOptimizer {
  step: number;
  first: PolicyModel;
  second: PolicyModel;
}
export const newOptimizer = (): PolicyOptimizer => ({
  step: 0,
  first: emptyGradient(),
  second: emptyGradient(),
});

/** Clipped on-policy updates, with Adam and an empirical KL trust limit.
 * Old action probabilities stay fixed across epochs; no stale replay rewards. */
export function updateFromOutcomes(
  model: PolicyModel,
  experiences: PolicyExperience[],
  optimizer: PolicyOptimizer = newOptimizer(),
  comparisonStrength = 0.1,
): {
  model: PolicyModel;
  optimizer: PolicyOptimizer;
  kl: number;
  epochs: number;
} {
  if (
    !Number.isFinite(comparisonStrength) ||
    comparisonStrength < 0 ||
    comparisonStrength > 1
  )
    throw new Error('Invalid comparison strength');
  const samples = [...new Set(experiences)].filter((e) => e.options.length > 1);
  if (!samples.length) return { model, optimizer, kl: 0, epochs: 0 };
  // A rollout target and a realized round outcome are two noisy teachers. Use
  // a comparison only when the sampled action's outcome agrees with its pair
  // direction; contradictory or neutral outcomes must not pull the policy in
  // opposite directions on the same observation.
  const usableComparisons = samples.map((experience) => ({
    experience,
    pairs: (experience.comparisons ?? []).filter((pair) => {
      const advantage = experience.advantage ?? 0;
      if (!advantage) return false;
      if (experience.chosen === pair.better) return advantage > 0;
      if (experience.chosen === pair.worse) return advantage < 0;
      return false;
    }),
  }));
  const comparisonWeight = usableComparisons.reduce(
    (n, entry) => n + entry.pairs.reduce((sum, pair) => sum + pair.weight, 0),
    0,
  );
  const old = samples.map((e) =>
    policyProbabilities(model, e.options, e.temperature ?? 1),
  );
  let current = parsePolicy(model);
  let state = optimizer;
  let kl = 0;
  let epochs = 0;
  for (let epoch = 0; epoch < 4; epoch++) {
    const gradient = emptyGradient();
    samples.forEach((e, i) => {
      const probabilities = policyProbabilities(
        current,
        e.options,
        e.temperature ?? 1,
      );
      const ratio =
        probabilities[e.chosen]! / Math.max(1e-12, old[i]![e.chosen]!);
      const advantage = e.advantage ?? 0;
      if (!((advantage > 0 && ratio > 1.2) || (advantage < 0 && ratio < 0.8)))
        accumulatePolicyGradient(
          current,
          [{ ...e, advantage: advantage * ratio }],
          0,
          gradient,
        );
      // Honor explicit teaching targets; otherwise use a weak baseline anchor.
      const teacherIndex =
        e.teacherIndex ?? e.options.findIndex((option) => option.prior > 0);
      if (teacherIndex >= 0)
        accumulateTeacherGradient(
          current,
          [{ ...e, teacherIndex }],
          gradient,
          e.teacherWeight ?? 0.01,
        );
    });
    // Normalize the comparison objective separately: a bounded set of expensive
    // rollouts must not be diluted by thousands of unrelated sampled actions.
    if (comparisonWeight > 0 && comparisonStrength > 0)
      for (const { experience, pairs } of usableComparisons) {
        for (const pair of pairs) {
          accumulatePolicyGradient(
            current,
            [
              {
                options: [
                  experience.options[pair.better]!,
                  experience.options[pair.worse]!,
                ],
                chosen: 0,
                temperature: 1,
                advantage:
                  (comparisonStrength * (pair.weight * samples.length)) /
                  comparisonWeight,
              },
            ],
            0,
            gradient,
          );
        }
      }
    const next = {
      step: state.step + 1,
      first: emptyGradient(),
      second: emptyGradient(),
    };
    const proposed = emptyGradient();
    // The prior is model state, not a trainable gradient coordinate. Preserve
    // it across Adam proposals so the trust-region comparison does not see an
    // accidental jump to the gradient's zero marker.
    proposed.priorScale = current.priorScale;
    const update = (
      value: number,
      g: number,
      m: number,
      v: number,
    ): [number, number, number] => {
      g /= samples.length;
      const first = 0.9 * m + 0.1 * g;
      const second = 0.999 * v + 0.001 * g * g;
      const delta =
        (0.01 * (first / (1 - 0.9 ** next.step))) /
        (Math.sqrt(second / (1 - 0.999 ** next.step)) + 1e-8);
      return [Math.max(-20, Math.min(20, value + delta)), first, second];
    };
    for (const key of ['bias', 'output'] as const)
      current[key].forEach((v, i) => {
        [proposed[key][i], next.first[key][i], next.second[key][i]] = update(
          v,
          gradient[key][i]!,
          state.first[key][i]!,
          state.second[key][i]!,
        );
      });
    current.input.forEach((row, h) =>
      row.forEach((v, f) => {
        [
          proposed.input[h]![f],
          next.first.input[h]![f],
          next.second.input[h]![f],
        ] = update(
          v,
          gradient.input[h]![f]!,
          state.first.input[h]![f]!,
          state.second.input[h]![f]!,
        );
      }),
    );
    const divergenceOf = (candidate: PolicyModel) =>
      samples.reduce((total, e, i) => {
        const p = policyProbabilities(candidate, e.options, e.temperature ?? 1);
        return (
          total +
          old[i]!.reduce(
            (sum, q, j) =>
              sum + q * Math.log(Math.max(q, 1e-12) / Math.max(p[j]!, 1e-12)),
            0,
          )
        );
      }, 0) / samples.length;
    let divergence = divergenceOf(proposed);
    // Shrink an oversized step instead of getting stuck rejecting the same
    // Adam proposal every generation. Moments commit only with accepted weights.
    for (let attempt = 0; divergence > 0.01 && attempt < 12; attempt++) {
      for (const key of ['bias', 'output'] as const)
        proposed[key] = proposed[key].map((v, i) => (v + current[key][i]!) / 2);
      proposed.input = proposed.input.map((row, h) =>
        row.map((v, f) => (v + current.input[h]![f]!) / 2),
      );
      divergence = divergenceOf(proposed);
    }
    if (!Number.isFinite(divergence) || divergence > 0.01) break;
    current = proposed;
    state = next;
    kl = Math.max(0, divergence);
    epochs++;
  }
  return { model: current, optimizer: state, kl, epochs };
}
