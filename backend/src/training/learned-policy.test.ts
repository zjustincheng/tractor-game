import { describe, expect, it } from 'vitest';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  availableComponents,
  chooseBotLead,
  chooseBotBurial,
  DEFAULT_BOT_LEAD_WEIGHTS,
  decomposeLead,
  PLAYER_COUNTS,
} from '@tractor/rules';
import type { Card } from '@tractor/rules';
import {
  accumulatePolicyGradient,
  accumulateTeacherGradient,
  applyPolicyGradient,
  choosePolicyLead,
  choosePolicyBurial,
  choosePolicyDeclaration,
  emptyGradient,
  leadOptions,
  EXPLORATION_TEMPERATURE,
  newPolicy,
  parsePolicy,
  POLICY_STEP_SIZE,
  policyProbabilities,
} from './learned-policy.js';
import {
  assertEvaluationSize,
  matchReward,
  MIN_POLICY_EVALUATION_GAMES,
  newPolicyCheckpoint,
  inferNonPromotionStreak,
  shouldRollbackLearner,
  MIN_CHAMPION_REGRESSION_MARGIN,
  ROLLBACK_COOLDOWN_GENERATIONS,
  resolveLearnerGenerationState,
  resolveGenerationModels,
  parsePolicyCheckpoint,
  policyPasses,
  bootstrapMarginInterval,
  summarizePaired,
  trainPolicyGeneration,
} from './policy-training.js';
import { playTrainingMatch, seededRandom } from './self-play.js';
import type { SelfPlayResult } from './self-play.js';
import { loadPolicyLead } from './load-policy.js';
import { newOptimizer } from './policy-update.js';

const trump = { level: '2', suit: 'spades' } as const;
const context = {
  role: 'attackers' as const,
  defenderScore: 0,
  swapThreshold: 80,
  seat: 0,
  playerCount: 4,
};
const hand: Card[] = [
  { id: 'c3a', kind: 'suited', suit: 'clubs', rank: '3' },
  { id: 'c3b', kind: 'suited', suit: 'clubs', rank: '3' },
  { id: 'c4a', kind: 'suited', suit: 'clubs', rank: '4' },
  { id: 'c4b', kind: 'suited', suit: 'clubs', rank: '4' },
  { id: 'sA', kind: 'suited', suit: 'spades', rank: 'A' },
];
const config = {
  seed: 42,
  playerCounts: [4] as (4 | 6 | 8 | 10)[],
  trainSeeds: 1,
  validationSeeds: 1,
  maxRounds: 1,
};

describe('contextual lead learner', () => {
  it('rolls back only after pooled comparisons prove a material regression', () => {
    const worse = Array(64).fill(-1) as number[];
    expect(shouldRollbackLearner(Array(128).fill(0), true)).toBe(false);
    expect(shouldRollbackLearner(worse.slice(0, 63), true)).toBe(false);
    expect(shouldRollbackLearner(worse, false)).toBe(false);
    expect(shouldRollbackLearner(worse, true)).toBe(true);
    // A regression inside the indistinguishable band is not worth a reset.
    expect(
      shouldRollbackLearner(
        Array(256).fill(-MIN_CHAMPION_REGRESSION_MARGIN / 2),
        true,
      ),
    ).toBe(false);
    expect(
      shouldRollbackLearner(
        Array(256).fill(-MIN_CHAMPION_REGRESSION_MARGIN * 2),
        true,
      ),
    ).toBe(true);
    // A learner still recovering from a reset is left alone.
    expect(shouldRollbackLearner(worse, true, 1)).toBe(false);
    expect(shouldRollbackLearner(worse, true, 0)).toBe(true);
    expect(
      inferNonPromotionStreak([
        { promoted: false },
        { promoted: true },
        { promoted: false },
        { promoted: false },
      ]),
    ).toBe(2);
  });

  it('restores both champion networks and resets Adam moments on rollback', () => {
    const champion = newPolicy(seededRandom(51));
    const candidate = newPolicy(seededRandom(52));
    const followChampion = newPolicy(seededRandom(53));
    const followCandidate = newPolicy(seededRandom(54));
    const optimizer = newOptimizer();
    optimizer.step = 19;
    expect(
      resolveLearnerGenerationState({
        championMargins: Array(64).fill(-1),
        rollbackCooldown: 2,
        nonPromotionStreak: 100,
        promoted: false,
        candidate: { lead: candidate, follow: followCandidate },
        champion: { lead: champion, follow: followChampion },
        leadOptimizer: optimizer,
        followOptimizer: optimizer,
      }).learnerReset,
    ).toBe(false);
    const state = resolveLearnerGenerationState({
      championMargins: Array(64).fill(-1),
      nonPromotionStreak: 100,
      promoted: false,
      candidate: { lead: candidate, follow: followCandidate },
      champion: { lead: champion, follow: followChampion },
      leadOptimizer: optimizer,
      followOptimizer: optimizer,
    });
    expect(state.learnerReset).toBe(true);
    expect(state.lead).toEqual(champion);
    expect(state.follow).toEqual(followChampion);
    expect(state.leadOptimizer.step).toBe(0);
    expect(state.followOptimizer.step).toBe(0);
    expect(state.nonPromotionStreak).toBe(0);
  });

  it('promotes the models evaluation measured, not the adaptive-prior copies', () => {
    const evaluated = {
      lead: { ...parsePolicy(newPolicy(seededRandom(61))), priorScale: 0.2 },
      follow: { ...parsePolicy(newPolicy(seededRandom(62))), priorScale: 0.2 },
    };
    const adapted = {
      lead: { ...evaluated.lead, priorScale: 0.31 },
      follow: { ...evaluated.follow, priorScale: 0.31 },
    };
    const promotedModels = resolveGenerationModels({
      promoted: true,
      evaluated,
      learner: adapted,
      champion: null,
    });
    expect(promotedModels.champion).toEqual(evaluated);
    expect(promotedModels.learner).toEqual(evaluated);
    const heldModels = resolveGenerationModels({
      promoted: false,
      evaluated,
      learner: adapted,
      champion: evaluated,
    });
    expect(heldModels.champion).toEqual(evaluated);
    expect(heldModels.learner).toEqual(adapted);
  });

  it('counts generations since promotion across a learner rollback', () => {
    const champion = parsePolicy(newPolicy(seededRandom(71)));
    const start = {
      ...newPolicyCheckpoint(config),
      champion,
      leadChampion: champion,
      followChampion: parsePolicy(newPolicy(seededRandom(72))),
      // Enough pooled regression evidence to force the preflight rollback.
      championLevelMarginSamples: Array(64).fill(-1) as number[],
      nonPromotionStreak: 31,
      generationsSincePromotion: 31,
    };
    const next = trainPolicyGeneration(start);
    const report = next.reports[0]!;
    expect(report.promoted).toBe(false);
    expect(report.learnerReset).toBe(true);
    // Rollback restarts the learner streak but not the promotion counter.
    expect(next.nonPromotionStreak).toBe(1);
    expect(report.nonPromotionStreak).toBe(1);
    // The same evidence cannot reset the learner twice, and the next few
    // generations are left alone.
    expect(next.rollbackCooldown).toBe(ROLLBACK_COOLDOWN_GENERATIONS);
    expect(next.generationsSincePromotion).toBe(32);
    expect(report.generationsSincePromotion).toBe(32);
  }, 60000);

  it('leaves a recovering learner alone until the cooldown expires', () => {
    const champion = parsePolicy(newPolicy(seededRandom(73)));
    const start = {
      ...newPolicyCheckpoint(config),
      champion,
      leadChampion: champion,
      followChampion: parsePolicy(newPolicy(seededRandom(74))),
      championLevelMarginSamples: Array(64).fill(-1) as number[],
      rollbackCooldown: 2,
    };
    const next = trainPolicyGeneration(start);
    expect(next.reports[0]!.learnerReset).toBe(false);
    expect(next.rollbackCooldown).toBe(1);
    // The evidence is kept, so the rollback can still fire once the cooldown ends.
    expect(
      (next.championLevelMarginSamples ?? []).length,
    ).toBeGreaterThanOrEqual(64);
  }, 60000);

  it('offers every generated structure, including splitting a tractor, and explores reproducibly', () => {
    const options = leadOptions(hand, trump, context);
    expect(options).toHaveLength(availableComponents(hand, trump).length);
    expect(new Set(options.map((option) => option.cardIds.length))).toEqual(
      new Set([1, 2, 4]),
    );
    for (const option of options)
      expect(
        decomposeLead(
          hand.filter((card) => option.cardIds.includes(card.id)),
          trump,
        ),
      ).not.toBeNull();
    const model = newPolicy(seededRandom(42));
    expect(choosePolicyLead(model, hand, trump, context)).toEqual(
      chooseBotLead(hand, trump, context),
    );
    const sequence = () => {
      const pick = seededRandom(19);
      return Array.from({ length: 100 }, () =>
        choosePolicyLead(model, hand, trump, context, pick).join('|'),
      );
    };
    expect(sequence()).toEqual(sequence());
    expect(new Set(sequence()).size).toBeGreaterThan(1);
  });

  it.each([1, 0.5])(
    'computes numerical gradients at temperature %s through both layers',
    (temperature) => {
      const model = newPolicy(seededRandom(42));
      model.output.fill(0.2);
      const options = leadOptions(hand, trump, context);
      const chosen = 1;
      const gradient = emptyGradient();
      accumulatePolicyGradient(
        model,
        [{ options, chosen, temperature }],
        1,
        gradient,
      );
      const epsilon = 1e-5;
      const finite = (change: (m: typeof model, amount: number) => void) => {
        const plus = parsePolicy(model),
          minus = parsePolicy(model);
        change(plus, epsilon);
        change(minus, -epsilon);
        return (
          (Math.log(policyProbabilities(plus, options, temperature)[chosen]!) -
            Math.log(
              policyProbabilities(minus, options, temperature)[chosen]!,
            )) /
          (2 * epsilon)
        );
      };
      expect(gradient.output[0]).toBeCloseTo(
        finite((m, e) => {
          m.output[0]! += e;
        }),
        6,
      );
      expect(gradient.input[0]![9]).toBeCloseTo(
        finite((m, e) => {
          m.input[0]![9]! += e;
        }),
        6,
      );
      expect(gradient.bias[0]).toBeCloseTo(
        finite((m, e) => {
          m.bias[0]! += e;
        }),
        6,
      );
    },
  );

  it('keeps the same scoring rule at every exploration temperature', () => {
    const model = emptyGradient();
    for (const count of [2, 10, 100, 500]) {
      const options = Array.from({ length: count }, (_, index) => ({
        cardIds: [String(index)],
        features: Array(22).fill(0),
        prior: index === 0 ? 0.75 : 0,
      }));
      const probabilities = policyProbabilities(model, options, 0.5);
      expect(probabilities[0]! / probabilities[1]!).toBeCloseTo(
        Math.exp(0.75 / 0.5),
      );
      expect(probabilities.slice(1).every((value) => value > 0)).toBe(true);
      expect(probabilities.reduce((sum, value) => sum + value, 0)).toBeCloseTo(
        1,
        12,
      );
    }
  });

  it('can pass a legal declaration instead of being forced to call', () => {
    const options = [
      {
        kind: 'suit' as const,
        playerSeat: 0,
        suit: 'spades' as const,
        level: '2' as const,
        multiplicity: 1,
        cardIds: ['s2'],
      },
    ];
    const cards: Card[] = [
      { id: 's2', kind: 'suited', suit: 'spades', rank: '2' },
    ];
    let sawPass = false;
    choosePolicyDeclaration(
      emptyGradient(),
      options,
      cards,
      '2',
      () => 0xffffffff,
      (e) => {
        sawPass = e.options.some((option) => option.cardIds.length === 0);
      },
    );
    expect(sawPass).toBe(true);
    expect(
      choosePolicyDeclaration(
        emptyGradient(),
        options,
        cards,
        '2',
        () => 0xffffffff,
      ),
    ).toBeNull();
  });

  it('starts burial from the actual bot baseline and retains legal alternatives', () => {
    const cards: Card[] = [
      { id: 'trump', kind: 'suited', suit: 'spades', rank: '3' },
      { id: 'points', kind: 'suited', suit: 'hearts', rank: 'K' },
      { id: 'low', kind: 'suited', suit: 'clubs', rank: '4' },
    ];
    const model = newPolicy(seededRandom(42));
    expect(choosePolicyBurial(model, cards, 2, trump)).toEqual(
      chooseBotBurial(cards, 2, trump),
    );
    choosePolicyBurial(model, cards, 2, trump, undefined, (experience) => {
      expect(experience.options.length).toBeGreaterThan(1);
      for (const option of experience.options) {
        expect(new Set(option.cardIds).size).toBe(2);
        expect(
          option.cardIds.every((id) => cards.some((card) => card.id === id)),
        ).toBe(true);
      }
    });
  });

  it('can learn a different legal lead from outcome feedback without changing handcrafted weights', () => {
    let model = newPolicy(seededRandom(17));
    const options = leadOptions(hand, trump, context);
    const chosen = options.findIndex(
      (option) => option.cardIds.length === 1 && option.cardIds[0] === 'c3a',
    );
    const before = policyProbabilities(model, options)[chosen]!;
    const negative = emptyGradient();
    accumulatePolicyGradient(model, [{ options, chosen }], -1, negative);
    expect(
      policyProbabilities(applyPolicyGradient(model, negative, 1), options)[
        chosen
      ]!,
    ).toBeLessThan(before);
    for (let i = 0; i < 500; i++) {
      const gradient = emptyGradient();
      accumulatePolicyGradient(model, [{ options, chosen }], 1, gradient);
      model = applyPolicyGradient(model, gradient, 1);
    }
    expect(choosePolicyLead(model, hand, trump, context)).toEqual(['c3a']);
    expect(chooseBotLead(hand, trump, context)).not.toEqual(['c3a']);
    expect(parsePolicy(model)).toEqual(model);
  });

  it('distills a public-belief teacher choice into the policy', () => {
    const model = newPolicy(seededRandom(31));
    const experiences: Parameters<typeof accumulateTeacherGradient>[1] = [];
    choosePolicyLead(
      model,
      hand,
      trump,
      { ...context, beliefSearch: true },
      undefined,
      (experience) => experiences.push(experience),
    );
    const teacherIndex = experiences[0]!.teacherIndex;
    if (teacherIndex === undefined) throw new Error('teacher choice missing');
    expect(teacherIndex).toBeGreaterThanOrEqual(0);
    const before = policyProbabilities(model, experiences[0]!.options)[
      teacherIndex
    ]!;
    const gradient = emptyGradient();
    accumulateTeacherGradient(model, experiences, gradient, 1);
    const after = policyProbabilities(
      applyPolicyGradient(model, gradient, 1),
      experiences[0]!.options,
    )[teacherIndex]!;
    expect(after).toBeGreaterThan(before);
  });

  it('trains the hidden layer, not just the output layer', () => {
    // Every input and bias gradient is scaled by model.output[h]. An all-zero
    // output layer therefore froze input and bias at their initialisation.
    const model = newPolicy(seededRandom(17));
    expect(model.output.some((weight) => weight !== 0)).toBe(true);
    const options = leadOptions(hand, trump, context);
    const gradient = emptyGradient();
    accumulatePolicyGradient(model, [{ options, chosen: 0 }], 1, gradient);
    expect(gradient.bias.some((value) => value !== 0)).toBe(true);
    expect(gradient.input.flat().some((value) => value !== 0)).toBe(true);
    const next = applyPolicyGradient(model, gradient, 1);
    expect(next.bias).not.toEqual(model.bias);
    expect(next.input).not.toEqual(model.input);
  });

  it('takes a step of consistent size however small the raw gradient is', () => {
    // The old cap divided by Math.max(1, norm), so a gradient far below unit
    // norm — always, once coefficients are averaged over thousands of
    // decisions — produced a step too small to ever overcome LeadOption.prior.
    const model = newPolicy(seededRandom(23));
    const options = leadOptions(hand, trump, context);
    const distance = (matches: number): number => {
      const gradient = emptyGradient();
      for (let i = 0; i < matches; i++)
        accumulatePolicyGradient(model, [{ options, chosen: 0 }], 1, gradient);
      const next = applyPolicyGradient(model, gradient, matches);
      return Math.hypot(
        ...next.output.map((n, h) => n - model.output[h]!),
        ...next.bias.map((n, h) => n - model.bias[h]!),
        ...next.input.flatMap((row, h) =>
          row.map((n, f) => n - model.input[h]![f]!),
        ),
      );
    };
    expect(distance(1)).toBeCloseTo(POLICY_STEP_SIZE, 6);
    // Averaging over more matches must not shrink the step towards zero.
    expect(distance(64)).toBeCloseTo(POLICY_STEP_SIZE, 6);
  });

  it('explores around the heuristic instead of replacing it', () => {
    // At temperature 1 the heuristic prior still leaves alternatives available,
    // the mass, so practice play was mostly random and its result taught little.
    const model = newPolicy(seededRandom(31));
    const options = leadOptions(hand, trump, context);
    const baseline = chooseBotLead(hand, trump, context);
    const index = options.findIndex(
      (option) =>
        option.cardIds.length === baseline.length &&
        option.cardIds.every((id) => baseline.includes(id)),
    );
    expect(index).toBeGreaterThanOrEqual(0);
    const hot = policyProbabilities(model, options)[index]!;
    const cool = policyProbabilities(model, options, EXPLORATION_TEMPERATURE)[
      index
    ]!;
    expect(EXPLORATION_TEMPERATURE).toBeLessThan(1);
    expect(cool).toBeGreaterThan(hot);
    // Greedy evaluation is an argmax, so temperature must not change its move.
    expect(choosePolicyLead(model, hand, trump, context)).toEqual(
      options[
        policyProbabilities(model, options, EXPLORATION_TEMPERATURE).indexOf(
          Math.max(
            ...policyProbabilities(model, options, EXPLORATION_TEMPERATURE),
          ),
        )
      ]!.cardIds,
    );
  });

  it('centres rewards so an average result teaches nothing', () => {
    // Uncentred, a learner losing most practice games pushed down nearly every
    // move it made. Equal rewards must now cancel to a zero-size update.
    const model = newPolicy(seededRandom(11));
    const options = leadOptions(hand, trump, context);
    const gradient = emptyGradient();
    for (const chosen of [0, 1, 2])
      accumulatePolicyGradient(model, [{ options, chosen }], 0, gradient);
    expect(gradient.output.every((value) => value === 0)).toBe(true);
    expect(gradient.input.flat().every((value) => value === 0)).toBe(true);
    expect(applyPolicyGradient(model, gradient, 3)).toEqual(parsePolicy(model));
  });

  it('rewards the level margin, not just the win', () => {
    const result = (a: string, b: string) =>
      ({ levels: { A: a, B: b } }) as unknown as Parameters<
        typeof matchReward
      >[0];
    expect(matchReward(result('A', '2'), 'A')).toBeGreaterThan(
      matchReward(result('5', '2'), 'A'),
    );
    expect(matchReward(result('5', '2'), 'A')).toBe(
      -matchReward(result('5', '2'), 'B'),
    );
    expect(matchReward(result('2', '2'), 'A')).toBe(0);
    for (const reward of [
      matchReward(result('A', '2'), 'A'),
      matchReward(result('2', 'A'), 'A'),
    ])
      expect(Math.abs(reward)).toBeLessThanOrEqual(1);
  });

  it('rejects a validation size that could never promote', () => {
    // policyPasses needs MIN_POLICY_EVALUATION_GAMES, so a smaller validation
    // set made every generation silently non-promoting however well it played.
    expect(() => assertEvaluationSize(config)).toThrow(/never|at least/i);
    const sufficient = {
      ...config,
      validationSeeds: MIN_POLICY_EVALUATION_GAMES / 2,
    };
    expect(() => assertEvaluationSize(sufficient)).not.toThrow();
  });

  it.each(PLAYER_COUNTS)(
    'plays legal learned-policy matches through a winner for %i seats',
    (playerCount) => {
      const model = newPolicy(seededRandom(6));
      const pick = seededRandom(7);
      const result = playTrainingMatch({
        seed: 20042,
        playerCount,
        candidateTeam: 'A',
        candidate: DEFAULT_BOT_LEAD_WEIGHTS,
        opponent: DEFAULT_BOT_LEAD_WEIGHTS,
        maxRounds: 100,
        candidateLead: (cards, t, c) =>
          choosePolicyLead(model, cards, t, c, pick),
      });
      expect(result.winner).not.toBeNull();
      expect(result.truncated).toBe(false);
    },
    60000,
  );

  it('learns from completed rounds of capped matches and resumes deterministically', () => {
    const start = newPolicyCheckpoint(config);
    const first = trainPolicyGeneration(start);
    expect(first.learner).not.toEqual(start.learner);
    expect(first.reports[0]!.decisions).toBeGreaterThan(0);
    expect(first.champion).toBeNull();
    expect(first.reports[0]).toMatchObject({
      promoted: false,
      training: { truncated: 2 },
    });
    expect(
      trainPolicyGeneration(
        parsePolicyCheckpoint(JSON.parse(JSON.stringify(first))),
      ),
    ).toEqual(trainPolicyGeneration(first));
  }, 60000);

  it('requires enough complete evaluation matches and keeps model files explicit', () => {
    expect(
      policyPasses({ games: 2, wins: 2, losses: 0, truncated: 0, winRate: 1 }),
    ).toBe(false);
    expect(bootstrapMarginInterval([0, 0, 0, 0])).toEqual({
      mean: 0,
      low: 0,
      high: 0,
      indistinguishable: true,
    });
    expect(
      policyPasses({
        games: 64,
        wins: 40,
        losses: 24,
        truncated: 0,
        winRate: 0.625,
        pairs: 32,
        marginMean: 1,
        marginLow: 0.5,
        marginHigh: 1.5,
        levelMarginMean: 1,
        levelMarginLow: 0.5,
        levelMarginHigh: 1.5,
        indistinguishable: false,
      }),
    ).toBe(true);
    expect(
      policyPasses({
        games: 64,
        wins: 40,
        losses: 24,
        truncated: 0,
        winRate: 0.625,
        pairs: 32,
        marginMean: 0.01,
        marginLow: 0.005,
        marginHigh: 0.02,
        levelMarginMean: 1,
        levelMarginLow: -0.1,
        levelMarginHigh: 1.2,
      }),
    ).toBe(false);
    expect(
      policyPasses({
        games: 64,
        wins: 39,
        losses: 23,
        truncated: 2,
        winRate: 0.75,
        pairs: 30,
        marginMean: 1,
        marginLow: 0.5,
        marginHigh: 1.5,
        levelMarginMean: 1,
        levelMarginLow: 0.5,
        levelMarginHigh: 1.5,
      }),
    ).toBe(false);
    expect(
      policyPasses({
        games: 64,
        wins: 39,
        losses: 24,
        truncated: 1,
        winRate: 0.75,
        pairs: 31,
        marginMean: 1,
        marginLow: 0.5,
        marginHigh: 1.5,
        levelMarginMean: 1,
        levelMarginLow: 0.5,
        levelMarginHigh: 1.5,
      }),
    ).toBe(true);
    expect(
      policyPasses({
        games: 100,
        wins: 60,
        losses: 40,
        truncated: 0,
        winRate: 0.6,
        pairs: 47,
        marginMean: 1,
        marginLow: 0.5,
        marginHigh: 1.5,
        levelMarginMean: 1,
        levelMarginLow: 0.5,
        levelMarginHigh: 1.5,
      }),
    ).toBe(false);
    const checkpoint = newPolicyCheckpoint(config);
    const file = join(
      mkdtempSync(join(tmpdir(), 'tractor-policy-test-')),
      'checkpoint.json',
    );
    writeFileSync(file, JSON.stringify(checkpoint));
    expect(() => loadPolicyLead(file)).toThrow(/no validated champion/);
    expect(loadPolicyLead(file, true)(hand, trump, context)).toEqual(
      choosePolicyLead(checkpoint.learner, hand, trump, context),
    );
    writeFileSync(
      file,
      JSON.stringify({ ...checkpoint, champion: checkpoint.learner }),
    );
    expect(loadPolicyLead(file)(hand, trump, context)).toEqual(
      choosePolicyLead(checkpoint.learner, hand, trump, context),
    );
    expect(() =>
      parsePolicyCheckpoint({ ...checkpoint, policyVersion: 'wrong' }),
    ).toThrow(/incompatible/);
    expect(
      parsePolicyCheckpoint({
        ...checkpoint,
        policyVersion: 'contextual-leads-v4-calibrated-exploration',
      }).policyVersion,
    ).toBe('contextual-leads-v12-play-style');
    expect(() => parsePolicy({ ...checkpoint.learner, output: [NaN] })).toThrow(
      /Invalid/,
    );
  });

  it('marks a baseline-identical paired evaluation indistinguishable', () => {
    const result = (candidateTeam: 'A' | 'B') =>
      ({
        seed: 7,
        playerCount: 4,
        candidateTeam,
        winner: null,
        rounds: 1,
        decisions: 0,
        truncated: false,
        // Mirrored candidate-team games have opposite nonzero margins. A
        // broken sign normalization would report a false positive here.
        levels: { A: '9', B: '4' },
        settlements: [{ attackingTeam: 'A', defenderScore: 100 }],
      }) as SelfPlayResult;
    const evaluation = summarizePaired([result('A'), result('B')]);
    expect(evaluation).toMatchObject({
      pairs: 1,
      marginMean: 0,
      marginLow: 0,
      marginHigh: 0,
      indistinguishable: true,
    });
    expect(policyPasses(evaluation)).toBe(false);
    expect(
      policyPasses({
        games: 64,
        wins: 32,
        losses: 32,
        truncated: 0,
        winRate: 0.5,
        pairs: 32,
        marginMean: 0,
        marginLow: 0,
        marginHigh: 0,
        indistinguishable: true,
      }),
    ).toBe(false);
    expect(
      policyPasses({
        games: 64,
        wins: 40,
        losses: 24,
        truncated: 0,
        winRate: 0.625,
        pairs: 31,
        marginMean: 1,
        marginLow: 0.5,
        marginHigh: 1.5,
      }),
    ).toBe(false);
  });
});
