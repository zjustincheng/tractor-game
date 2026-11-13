import { RANKS, RULES_VERSION } from '@tractor/rules';
import type { Team } from '@tractor/rules';
import {
  newPolicy,
  parsePolicy,
  POLICY_VERSION,
  policyProbabilities,
} from './learned-policy.js';
import type { PolicyModel, PolicyExperience } from './learned-policy.js';
import { parseConfig, generationSeeds, summarize } from './optimizer.js';
import type { TrainingConfig, Evaluation } from './optimizer.js';
import { seededRandom } from './self-play.js';
import type { SelfPlayResult } from './self-play.js';
import type { EvaluationMatch, PracticeMatch } from './evaluation-match.js';
import { updateFromOutcomes, newOptimizer } from './policy-update.js';
import type { PolicyOptimizer } from './policy-update.js';
import {
  playEvaluationMatches,
  playPracticeMatches,
} from './evaluation-pool.js';
export { roundReward } from './policy-reward.js';
import type { ComparisonCounts } from './counterfactual.js';

export interface PolicyReport {
  pointMarginVersion?: 2;
  generation: number;
  training: Evaluation;
  decisions: number;
  learningRounds?: number;
  alternativeChoices?: number;
  comparisons?: ComparisonCounts;
  evaluationBehavior?: { choices: number; differentFromBaseline: number };
  explorationBehavior?: {
    sampledDecisions: number;
    differentFromGreedy: number;
    meanChosenProbability: number;
    meanGreedyProbability: number;
  };
  evaluationLogits?: {
    meanSpread: number;
    p90Spread: number;
    baselinePrior: number;
  };
  vsChampion: Evaluation;
  vsBaseline: Evaluation;
  vsArchive: Evaluation | null;
  /** Held-out live Sharp; null when the cheaper gates already failed. */
  vsSharp?: Evaluation | null;
  /** The Roblox game's built-in bots, which the champion will replace. */
  vsRoblox?: Evaluation | null;
  /** Set on Roblox-rules generations that have no champion to fall back on. */
  robloxGuard?: {
    recentWinRate: number | null;
    bestWinRate: number | null;
    bestGeneration: number | null;
    returnedToBest: boolean;
  };
  promoted: boolean;
  learnerReset?: boolean;
  /** Generations left before another rollback may fire, after this one. */
  rollbackCooldown?: number;
  nonPromotionStreak?: number;
  generationsSincePromotion?: number;
  championRegression?: Evaluation;
  confirmation?: {
    baseline: Evaluation;
    champion: Evaluation | null;
    sharp?: Evaluation | null;
    roblox?: Evaluation | null;
  };
  promotionRevalidation?: {
    validatedAt: string;
    baseline: Evaluation;
    champion: Evaluation;
    archive: Evaluation | null;
    sharp?: Evaluation | null;
    confirmation: {
      baseline: Evaluation;
      champion: Evaluation | null;
      archive: Evaluation | null;
      sharp?: Evaluation | null;
    };
  };
  update?: {
    leadKL: number;
    followKL: number;
    leadEpochs: number;
    followEpochs: number;
  };
}
export const MIN_POLICY_EVALUATION_GAMES = 64;
export const MAX_POLICY_TRUNCATION_RATE = 0.02;
export const MIN_POLICY_PAIR_COMPLETION_RATE = 0.95;
export const MIN_CHAMPION_REGRESSION_PAIRS = 64;
/** Use a wider sample only for the expensive champion promotion checks. */
export const PROMOTION_CHAMPION_SEEDS = 512;
/** Require evidence of losing more than half a level, using paired level
 * margins. Point-only regressions never reset a learner. */
export const MIN_CHAMPION_REGRESSION_MARGIN = 0.5;
/** Point loss must be bounded, but point superiority is not required. */
export const MAX_PROMOTION_POINT_REGRESSION = 0.01;
/** The Roblox re-test plays this many times the usual validation deals. */
export const ROBLOX_CONFIRMATION_FACTOR = 2;
/** Generations a reset learner is left alone. Improving on a champion means
 * being allowed to be slightly worse on the way, and a reset also clears both
 * Adam moment estimates: without this, evidence rebuilds in two generations
 * and the learner is thrown back before it can recover its step sizes. */
export const ROLLBACK_COOLDOWN_GENERATIONS = 4;
export function shouldRollbackLearner(
  championMargins: readonly number[],
  hasChampion: boolean,
  cooldownRemaining = 0,
): boolean {
  return (
    hasChampion &&
    cooldownRemaining <= 0 &&
    championMargins.length >= MIN_CHAMPION_REGRESSION_PAIRS &&
    bootstrapMarginInterval(championMargins, 0x51f15e).high <
      -MIN_CHAMPION_REGRESSION_MARGIN
  );
}
/** Roblox bot scores swing by about 20 wins in 256 from one generation to the
 * next, so the learner is judged on an average of this many generations. */
export const ROBLOX_GUARD_WINDOW = 4;
/** Average win rate lost against the best stretch before the learner returns
 * to it. Six points is about 15 wins in 256. */
export const ROBLOX_GUARD_DROP = 0.06;
export interface RobloxGuard {
  recent: number[];
  best: {
    generation: number;
    winRate: number;
    lead: PolicyModel;
    follow: PolicyModel;
  } | null;
}
/** A champion gives the learner something to roll back to. Until one exists,
 * this keeps the learner from the end of its best stretch against the Roblox
 * bots and returns to it after a sustained drop. Clearing the window also
 * leaves the restored learner a full window before it can be judged again. */
export function resolveRobloxGuard(options: {
  guard: RobloxGuard | undefined;
  winRate: number;
  generation: number;
  evaluated: PolicyModelPair;
}): { guard: RobloxGuard; returnTo: PolicyModelPair | null } {
  const best = options.guard?.best ?? null;
  const recent = [...(options.guard?.recent ?? []), options.winRate].slice(
    -ROBLOX_GUARD_WINDOW,
  );
  if (recent.length < ROBLOX_GUARD_WINDOW)
    return { guard: { recent, best }, returnTo: null };
  const average = recent.reduce((sum, value) => sum + value, 0) / recent.length;
  if (!best || average > best.winRate)
    return {
      guard: {
        recent,
        best: {
          generation: options.generation,
          winRate: average,
          lead: parsePolicy(options.evaluated.lead),
          follow: parsePolicy(options.evaluated.follow),
        },
      },
      returnTo: null,
    };
  if (average < best.winRate - ROBLOX_GUARD_DROP)
    return {
      guard: { recent: [], best },
      returnTo: {
        lead: parsePolicy(best.lead),
        follow: parsePolicy(best.follow),
      },
    };
  return { guard: { recent, best }, returnTo: null };
}
function parseRobloxGuard(guard: RobloxGuard): RobloxGuard {
  if (
    !Array.isArray(guard.recent) ||
    guard.recent.length > ROBLOX_GUARD_WINDOW ||
    guard.recent.some((value) => typeof value !== 'number') ||
    (guard.best !== null && typeof guard.best?.winRate !== 'number')
  )
    throw new Error('Invalid or incompatible policy checkpoint');
  return {
    recent: guard.recent,
    best: guard.best && {
      generation: guard.best.generation,
      winRate: guard.best.winRate,
      lead: parsePolicy(guard.best.lead),
      follow: parsePolicy(guard.best.follow),
    },
  };
}
export function inferNonPromotionStreak(
  reports: readonly Pick<PolicyReport, 'promoted'>[],
): number {
  const promotionsSince = [...reports]
    .reverse()
    .findIndex((report) => report.promoted);
  return promotionsSince < 0 ? reports.length : promotionsSince;
}
export const POLICY_ARCHIVE_LIMIT = 8;
/** Keep a spread of past champions instead of only the newest ones: an opponent
 * pool drawn from one recent stretch of a single lineage is the easiest kind to
 * overfit. Entries stay in promotion order, so dropping the second oldest thins
 * the old middle while keeping the oldest, most distinct policy and every
 * recent one. */
export function retainArchive<T>(previous: readonly T[], added: T): T[] {
  const next = [...previous, added];
  while (next.length > POLICY_ARCHIVE_LIMIT) next.splice(1, 1);
  return next;
}
export interface PolicyModelPair {
  lead: PolicyModel;
  follow: PolicyModel;
}
// Save exactly the evaluated models, except for an explicitly reported rollback.
export function resolveGenerationModels(options: {
  promoted: boolean;
  evaluated: PolicyModelPair;
  learner: PolicyModelPair;
  champion: PolicyModelPair | null;
}): { learner: PolicyModelPair; champion: PolicyModelPair | null } {
  return {
    learner: options.promoted ? options.evaluated : options.learner,
    champion: options.promoted ? options.evaluated : options.champion,
  };
}
export function resolveLearnerGenerationState(options: {
  championMargins: readonly number[];
  rollbackCooldown?: number;
  nonPromotionStreak: number;
  promoted: boolean;
  candidate: { lead: PolicyModel; follow: PolicyModel };
  champion: { lead: PolicyModel; follow: PolicyModel } | null;
  leadOptimizer: PolicyOptimizer;
  followOptimizer: PolicyOptimizer;
}): {
  lead: PolicyModel;
  follow: PolicyModel;
  leadOptimizer: PolicyOptimizer;
  followOptimizer: PolicyOptimizer;
  nonPromotionStreak: number;
  learnerReset: boolean;
} {
  const learnerReset =
    !options.promoted &&
    shouldRollbackLearner(
      options.championMargins,
      options.champion !== null,
      options.rollbackCooldown ?? 0,
    );
  return {
    lead: parsePolicy(
      learnerReset ? options.champion!.lead : options.candidate.lead,
    ),
    follow: parsePolicy(
      learnerReset ? options.champion!.follow : options.candidate.follow,
    ),
    leadOptimizer: learnerReset ? newOptimizer() : options.leadOptimizer,
    followOptimizer: learnerReset ? newOptimizer() : options.followOptimizer,
    nonPromotionStreak:
      learnerReset || options.promoted ? 0 : options.nonPromotionStreak,
    learnerReset,
  };
}
const COMPATIBLE_POLICY_VERSIONS = new Set([
  POLICY_VERSION,
  'contextual-leads-v11-tactical-context',
  'contextual-leads-v10-adaptive-prior',
  'contextual-leads-v4-calibrated-exploration',
  'contextual-leads-v5-adaptive-prior',
  'contextual-leads-v6-round-credit',
  'contextual-leads-v7-counterfactual',
  'contextual-leads-v8-counterfactual-adaptive',
  'contextual-leads-v9-confident-counterfactual',
]);
export interface PolicyCheckpoint {
  format: 'tractor-policy-1';
  policyVersion: string;
  rulesVersion: string;
  generation: number;
  /** Promotion must also beat live Sharp, an opponent practice never faces.
   * Defaults to on; older checkpoints adopt it on their next generation. */
  sharpGate?: boolean;
  /** Train on the Roblox game's rules and practice more against its bots. */
  robloxRules?: boolean;
  /** Its bots make their own Chao Di calls; exported for the game. */
  robloxChaodi?: boolean;
  /** Best learner so far against the Roblox bots, while there is no champion. */
  robloxGuard?: RobloxGuard;
  nonPromotionStreak?: number;
  generationsSincePromotion?: number;
  /** Generations left before another learner rollback may fire. */
  rollbackCooldown?: number;
  championMarginSamples?: number[];
  championLevelMarginSamples?: number[];
  pointMarginVersion?: 2;
  config: TrainingConfig;
  learner: PolicyModel;
  champion: PolicyModel | null;
  leadLearner: PolicyModel;
  followLearner: PolicyModel;
  leadChampion: PolicyModel | null;
  followChampion: PolicyModel | null;
  archive: PolicyModel[];
  reports: PolicyReport[];
  policyArchive?: { lead: PolicyModel; follow: PolicyModel }[];
  leadOptimizer?: PolicyOptimizer;
  followOptimizer?: PolicyOptimizer;
  /** Content hashes of recorded rounds already used by learn:matches. */
  learnedMatchRounds?: string[];
}
export function newPolicyCheckpoint(config: TrainingConfig): PolicyCheckpoint {
  return {
    format: 'tractor-policy-1',
    policyVersion: POLICY_VERSION,
    rulesVersion: RULES_VERSION,
    generation: 0,
    sharpGate: true,
    nonPromotionStreak: 0,
    rollbackCooldown: 0,
    generationsSincePromotion: 0,
    championMarginSamples: [],
    pointMarginVersion: 2,
    config: parseConfig(config),
    learner: newPolicy(seededRandom(config.seed)),
    champion: null,
    leadLearner: newPolicy(seededRandom(config.seed)),
    followLearner: newPolicy(seededRandom(config.seed ^ 0x9e3779b9)),
    leadChampion: null,
    followChampion: null,
    archive: [],
    reports: [],
  };
}
export function parsePolicyCheckpoint(value: unknown): PolicyCheckpoint {
  const checkpoint = value as PolicyCheckpoint | null;
  if (
    !checkpoint ||
    checkpoint.format !== 'tractor-policy-1' ||
    !COMPATIBLE_POLICY_VERSIONS.has(checkpoint.policyVersion) ||
    checkpoint.rulesVersion !== RULES_VERSION ||
    !Number.isSafeInteger(checkpoint.generation) ||
    checkpoint.generation < 0 ||
    checkpoint.generation > 10000 ||
    (checkpoint.learnedMatchRounds !== undefined &&
      (!Array.isArray(checkpoint.learnedMatchRounds) ||
        checkpoint.learnedMatchRounds.some(
          (key) => typeof key !== 'string' || !/^[a-f0-9]{64}$/.test(key),
        ))) ||
    (checkpoint.nonPromotionStreak !== undefined &&
      (!Number.isSafeInteger(checkpoint.nonPromotionStreak) ||
        checkpoint.nonPromotionStreak < 0 ||
        checkpoint.nonPromotionStreak > 10000)) ||
    (checkpoint.generationsSincePromotion !== undefined &&
      (!Number.isSafeInteger(checkpoint.generationsSincePromotion) ||
        checkpoint.generationsSincePromotion < 0 ||
        checkpoint.generationsSincePromotion > 10000)) ||
    (checkpoint.championMarginSamples !== undefined &&
      (!Array.isArray(checkpoint.championMarginSamples) ||
        checkpoint.championMarginSamples.length > 2048 ||
        checkpoint.championMarginSamples.some(
          (margin) => typeof margin !== 'number' || !Number.isFinite(margin),
        ))) ||
    (checkpoint.championLevelMarginSamples !== undefined &&
      (!Array.isArray(checkpoint.championLevelMarginSamples) ||
        checkpoint.championLevelMarginSamples.length > 2048 ||
        checkpoint.championLevelMarginSamples.some(
          (value) => typeof value !== 'number' || !Number.isFinite(value),
        ))) ||
    !Array.isArray(checkpoint.archive) ||
    checkpoint.archive.length > POLICY_ARCHIVE_LIMIT ||
    (checkpoint.policyArchive !== undefined &&
      (!Array.isArray(checkpoint.policyArchive) ||
        checkpoint.policyArchive.length > POLICY_ARCHIVE_LIMIT)) ||
    (checkpoint.sharpGate !== undefined &&
      typeof checkpoint.sharpGate !== 'boolean') ||
    (checkpoint.rollbackCooldown !== undefined &&
      (!Number.isSafeInteger(checkpoint.rollbackCooldown) ||
        checkpoint.rollbackCooldown < 0 ||
        checkpoint.rollbackCooldown > 10000)) ||
    !Array.isArray(checkpoint.reports) ||
    checkpoint.reports.length !== checkpoint.generation
  )
    throw new Error('Invalid or incompatible policy checkpoint');
  const legacyLearner = parsePolicy(checkpoint.learner);
  const leadLearner = checkpoint.leadLearner
    ? parsePolicy(checkpoint.leadLearner)
    : legacyLearner;
  const followLearner = checkpoint.followLearner
    ? parsePolicy(checkpoint.followLearner)
    : legacyLearner;
  const legacyChampion =
    checkpoint.champion === null ? null : parsePolicy(checkpoint.champion);
  const leadChampion = checkpoint.leadChampion
    ? parsePolicy(checkpoint.leadChampion)
    : legacyChampion;
  const followChampion = checkpoint.followChampion
    ? parsePolicy(checkpoint.followChampion)
    : legacyChampion;
  const migrated = checkpoint.policyVersion !== POLICY_VERSION;
  const inferredStreak = inferNonPromotionStreak(checkpoint.reports);
  return {
    ...checkpoint,
    policyVersion: POLICY_VERSION,
    nonPromotionStreak: checkpoint.nonPromotionStreak ?? inferredStreak,
    generationsSincePromotion:
      checkpoint.generationsSincePromotion ?? inferredStreak,
    // Earlier point scores used the next round's attacking team, reversing
    // credit on role swaps. Do not mix those cached scores with corrected ones.
    championMarginSamples:
      !migrated && checkpoint.pointMarginVersion === 2
        ? (checkpoint.championMarginSamples ?? [])
        : [],
    pointMarginVersion: 2,
    championLevelMarginSamples: migrated
      ? []
      : (checkpoint.championLevelMarginSamples ?? []),
    ...(migrated ? { learnedMatchRounds: [] } : {}),
    config: parseConfig(checkpoint.config),
    learner: leadLearner,
    champion: migrated ? null : leadChampion,
    leadLearner,
    followLearner,
    leadChampion: migrated ? null : leadChampion,
    followChampion: migrated ? null : followChampion,
    archive: checkpoint.archive.map(parsePolicy),
    sharpGate: checkpoint.sharpGate ?? true,
    ...(checkpoint.robloxRules === true ? { robloxRules: true } : {}),
    ...(checkpoint.robloxChaodi === true ? { robloxChaodi: true } : {}),
    ...(checkpoint.robloxGuard
      ? { robloxGuard: parseRobloxGuard(checkpoint.robloxGuard) }
      : {}),
    rollbackCooldown: checkpoint.rollbackCooldown ?? 0,
    // A version migration retires the champion, which must re-earn its place,
    // but the archived opponents keep their value as sparring partners: their
    // networks parse under the current format, and discarding them is what
    // narrowed this pool to a single policy.
    policyArchive: (checkpoint.policyArchive ?? []).map((pair) => ({
      lead: parsePolicy(pair.lead),
      follow: parsePolicy(pair.follow),
    })),
    leadOptimizer: parseOptimizer(
      migrated ? undefined : checkpoint.leadOptimizer,
    ),
    followOptimizer: parseOptimizer(
      migrated ? undefined : checkpoint.followOptimizer,
    ),
  };
}

function parseOptimizer(value: PolicyOptimizer | undefined): PolicyOptimizer {
  if (!value) return newOptimizer();
  if (!Number.isSafeInteger(value.step) || value.step < 0)
    throw new Error('Invalid optimizer step');
  const first = parsePolicy(value.first),
    second = parsePolicy(value.second);
  if (
    [...second.input.flat(), ...second.bias, ...second.output].some(
      (n) => n < 0,
    )
  )
    throw new Error('Invalid optimizer variance');
  return { step: value.step, first, second };
}

export function discountedReturns(rewards: number[], discount = 0): number[] {
  const returns = Array<number>(rewards.length);
  let value = 0;
  for (let i = rewards.length - 1; i >= 0; i--) {
    value = rewards[i]! + discount * value;
    returns[i] = value;
  }
  return returns;
}

/** Games one evaluate() call will play for a configuration. */
export function evaluationGames(config: TrainingConfig): number {
  return config.playerCounts.length * config.validationSeeds * 2;
}

/**
 * Fail fast on a configuration that can never promote. policyPasses requires
 * MIN_POLICY_EVALUATION_GAMES, so a smaller validation set makes every
 * generation silently non-promoting no matter how well the learner plays.
 */
export function assertEvaluationSize(config: TrainingConfig): void {
  const games = evaluationGames(config);
  if (games < MIN_POLICY_EVALUATION_GAMES)
    throw new Error(
      `Validation plays ${games} games but promotion requires at least ${MIN_POLICY_EVALUATION_GAMES}; ` +
        `raise --validation-seeds to ${Math.ceil(
          MIN_POLICY_EVALUATION_GAMES / (config.playerCounts.length * 2),
        )} or add table sizes.`,
    );
}

/**
 * Level margin rather than a bare win/loss. Both teams start at '2', so each
 * team's level index is the number of levels it gained. A rout and a one-level
 * win carry different information, and the denser signal survives being shared
 * across every decision of a match better than a ±1 does.
 */
export function matchReward(
  result: SelfPlayResult,
  candidateTeam: Team,
): number {
  const gained = (team: Team): number => RANKS.indexOf(result.levels[team]);
  const margin =
    gained(candidateTeam) - gained(candidateTeam === 'A' ? 'B' : 'A');
  return Math.max(-1, Math.min(1, margin / (RANKS.length - 1)));
}

/** Level margin for one candidate game, with positive meaning candidate team
 * advanced farther than its opponent. Validation pairs the A/B games sharing a
 * seed before estimating uncertainty, so a lucky deal is not counted twice. */
export function levelMargin(result: SelfPlayResult): number {
  const other: Team = result.candidateTeam === 'A' ? 'B' : 'A';
  return (
    RANKS.indexOf(result.levels[result.candidateTeam]) -
    RANKS.indexOf(result.levels[other])
  );
}

/** Dense per-round point signal, normalized around the defender target. */
export function pointMargin(result: SelfPlayResult): number {
  if (!result.settlements.length) return 0;
  const threshold = result.playerCount * 20;
  return (
    result.settlements.reduce((total, settlement) => {
      const attackingTeam = settlement.rolesSwapped
        ? settlement.attackingTeam === 'A'
          ? 'B'
          : 'A'
        : settlement.attackingTeam;
      const centered =
        (settlement.defenderScore - threshold) / Math.max(1, threshold);
      return (
        total + (attackingTeam === result.candidateTeam ? -centered : centered)
      );
    }, 0) / result.settlements.length
  );
}

export function bootstrapMarginInterval(
  margins: readonly number[],
  seed = 1,
  samples = 4000,
): { mean: number; low: number; high: number; indistinguishable: boolean } {
  if (!margins.length)
    return { mean: 0, low: 0, high: 0, indistinguishable: true };
  const mean = margins.reduce((sum, value) => sum + value, 0) / margins.length;
  const pick = seededRandom(seed);
  const estimates: number[] = [];
  for (let sample = 0; sample < samples; sample++) {
    let total = 0;
    for (let i = 0; i < margins.length; i++)
      total += margins[pick(margins.length)]!;
    estimates.push(total / margins.length);
  }
  estimates.sort((a, b) => a - b);
  const low = estimates[Math.floor(samples * 0.025)]!;
  const high = estimates[Math.floor(samples * 0.975)]!;
  return { mean, low, high, indistinguishable: low <= 0 && high >= 0 };
}

export function summarizePaired(
  results: readonly SelfPlayResult[],
  seed = 1,
  includeMarginSamples = false,
): Evaluation {
  const basic = summarize(results);
  const bySeed = new Map<string, SelfPlayResult[]>();
  for (const result of results) {
    const key = `${result.playerCount}:${result.seed}`;
    const pair = bySeed.get(key) ?? [];
    pair.push(result);
    bySeed.set(key, pair);
  }
  const margins: number[] = [];
  const levelMargins: number[] = [];
  for (const pair of bySeed.values()) {
    const a = pair.find((result) => result.candidateTeam === 'A');
    const b = pair.find((result) => result.candidateTeam === 'B');
    if (a && b && !a.truncated && !b.truncated) {
      margins.push((pointMargin(a) + pointMargin(b)) / 2);
      levelMargins.push((levelMargin(a) + levelMargin(b)) / 2);
    }
  }
  const interval = bootstrapMarginInterval(margins, seed);
  const levelInterval = bootstrapMarginInterval(levelMargins, seed ^ 0x45d9f3b);
  return {
    ...basic,
    roundWins: results.reduce(
      (n, result) =>
        n +
        result.settlements.filter(
          (s) => s.attackingTeam === result.candidateTeam,
        ).length,
      0,
    ),
    completedRounds: results.reduce(
      (n, result) => n + result.settlements.length,
      0,
    ),
    pairs: margins.length,
    marginMean: interval.mean,
    marginLow: interval.low,
    marginHigh: interval.high,
    levelMarginMean: levelMargins.length
      ? levelMargins.reduce((sum, value) => sum + value, 0) /
        levelMargins.length
      : 0,
    levelMarginLow: levelInterval.low,
    levelMarginHigh: levelInterval.high,
    indistinguishable: levelInterval.indistinguishable,
    ...(includeMarginSamples
      ? { marginSamples: margins, levelMarginSamples: levelMargins }
      : {}),
  };
}

/** Rebuild the current champion-comparison window from a resumed run's match log. */
export function recoverChampionMarginSamples(
  checkpoint: PolicyCheckpoint,
  rows: readonly unknown[],
): number[] {
  let firstGeneration = 1;
  for (const [index, report] of checkpoint.reports.entries())
    if (report.promoted || report.learnerReset) firstGeneration = index + 2;

  const byGeneration = new Map<number, SelfPlayResult[]>();
  for (const value of rows) {
    if (!value || typeof value !== 'object') continue;
    const row = value as {
      phase?: unknown;
      generation?: unknown;
      policyVersion?: unknown;
      result?: SelfPlayResult;
    };
    if (
      row.phase !== 'validation-champion' ||
      !Number.isSafeInteger(row.generation) ||
      (row.policyVersion !== undefined &&
        row.policyVersion !== POLICY_VERSION) ||
      (row.generation as number) < firstGeneration ||
      (row.generation as number) > checkpoint.generation ||
      !row.result ||
      !Number.isSafeInteger(row.result.seed) ||
      ![4, 6, 8, 10].includes(row.result.playerCount) ||
      (row.result.candidateTeam !== 'A' && row.result.candidateTeam !== 'B') ||
      !row.result.levels ||
      !Array.isArray(row.result.settlements) ||
      typeof row.result.truncated !== 'boolean'
    )
      continue;
    const generation = row.generation as number;
    const matches = byGeneration.get(generation) ?? [];
    matches.push(row.result);
    byGeneration.set(generation, matches);
  }

  const margins = checkpoint.reports
    .filter(
      (report) =>
        report.generation >= firstGeneration &&
        !report.promoted &&
        !report.learnerReset,
    )
    .flatMap((report) => {
      const saved = report.vsChampion.marginSamples;
      if (saved && report.pointMarginVersion === 2) return saved;
      const results = byGeneration.get(report.generation) ?? [];
      return (
        summarizePaired(results, report.generation ^ 0x51f15e, true)
          .marginSamples ?? []
      );
    });
  return margins.slice(-2048);
}

export function policyPasses(evaluation: Evaluation): boolean {
  // This is a screening gate, not a claim of statistically established strength.
  return (
    evaluation.games >= MIN_POLICY_EVALUATION_GAMES &&
    evaluation.pairs !== undefined &&
    evaluation.pairs >=
      (evaluation.games / 2) * MIN_POLICY_PAIR_COMPLETION_RATE &&
    evaluation.truncated / evaluation.games <= MAX_POLICY_TRUNCATION_RATE &&
    evaluation.marginLow !== undefined &&
    Number.isFinite(evaluation.marginLow) &&
    evaluation.marginLow >= -MAX_PROMOTION_POINT_REGRESSION &&
    evaluation.levelMarginLow !== undefined &&
    Number.isFinite(evaluation.levelMarginLow) &&
    evaluation.levelMarginLow > 0
  );
}

export function trainPolicyGeneration(
  checkpoint: PolicyCheckpoint,
  onGame?: (phase: string, result: SelfPlayResult) => void,
  // Timings stay out of the checkpoint: a generation must stay reproducible.
  onPhase?: (phase: string, milliseconds: number, matches: number) => void,
): PolicyCheckpoint {
  const generationStarted = performance.now();
  const generation = checkpoint.generation + 1;
  if (generation > 10000) throw new Error('Maximum generation reached');
  type Pair = { lead: PolicyModel; follow: PolicyModel };
  const champion: Pair | null =
    checkpoint.leadChampion && checkpoint.followChampion
      ? { lead: checkpoint.leadChampion, follow: checkpoint.followChampion }
      : null;
  const startingStreak =
    checkpoint.nonPromotionStreak ??
    inferNonPromotionStreak(checkpoint.reports);
  // Rollback resets the learner streak; generations since promotion keeps
  // counting until a candidate actually becomes champion.
  const startingSincePromotion =
    checkpoint.generationsSincePromotion ??
    inferNonPromotionStreak(checkpoint.reports);
  const startingChampionMargins = checkpoint.championMarginSamples ?? [];
  // Old point evidence must never be interpreted as level evidence.
  const startingLevelMargins = checkpoint.championLevelMarginSamples ?? [];
  const startingCooldown = checkpoint.rollbackCooldown ?? 0;
  const preflightRollback = shouldRollbackLearner(
    startingLevelMargins,
    champion !== null,
    startingCooldown,
  );
  // A preflight rollback starts the cooldown immediately, so the same evidence
  // cannot reset the learner twice in one generation.
  const activeCooldown = preflightRollback
    ? ROLLBACK_COOLDOWN_GENERATIONS
    : Math.max(0, startingCooldown - 1);
  const activeStreak = preflightRollback ? 0 : startingStreak;
  const leadBase = preflightRollback
    ? champion!.lead
    : (checkpoint.leadLearner ?? checkpoint.learner);
  const followBase = preflightRollback
    ? champion!.follow
    : (checkpoint.followLearner ?? checkpoint.learner);
  const results: SelfPlayResult[] = [];
  const pending: {
    leadExperiences: PolicyExperience[];
    followExperiences: PolicyExperience[];
    reward: number;
  }[] = [];
  const comparisons: ComparisonCounts = {
    positions: 0,
    rollouts: 0,
    informativePairs: 0,
    betterThanBaseline: 0,
  };
  const evaluationBehavior = { choices: 0, differentFromBaseline: 0 };
  const evaluationLogits = {
    meanSpread: 0,
    p90Spread: 0,
    baselinePrior: leadBase.priorScale ?? 0.35,
  };
  let decisions = 0;
  let completed = 0;
  let evaluationMatches = 0;
  const archive = checkpoint.policyArchive ?? [];
  // Keep one quarter of practice against the handcrafted baseline. Once the
  // learner is far ahead of it, the remaining practice is more useful against
  // champion/archive opponents.
  const opponents = [champion, ...archive].filter((p): p is Pair => p !== null);
  const practiceStarted = performance.now();
  const practice: PracticeMatch[] = [];
  for (const playerCount of checkpoint.config.playerCounts) {
    for (const [index, seed] of generationSeeds(
      checkpoint.config,
      generation,
      false,
    ).entries()) {
      // Half of practice is the handcrafted baseline and the Roblox bots; a
      // Roblox-rules run spends half on the Roblox bots alone.
      const playsRoblox = checkpoint.robloxRules
        ? index % 2 === 1
        : index % 4 === 1;
      const opponent =
        index % 4 === 0
          ? null
          : playsRoblox
            ? ('roblox' as const)
            : (opponents[
                (generation + Math.floor(index / 2)) % opponents.length
              ] ?? null);
      for (const candidateTeam of ['A', 'B'] as const)
        practice.push({
          seed,
          playerCount,
          candidateTeam,
          maxRounds: checkpoint.config.maxRounds,
          robloxRules: checkpoint.robloxRules === true,
          counterfactualWeight: checkpoint.config.counterfactualWeight,
          lead: leadBase,
          follow: followBase,
          opponent,
        });
    }
  }
  for (const outcome of playPracticeMatches(practice)) {
    for (const key of [
      'positions',
      'rollouts',
      'informativePairs',
      'betterThanBaseline',
    ] as const)
      comparisons[key] += outcome.comparisons[key];
    const { rounds, result } = outcome;
    // Completed rounds provide valid local feedback even if a match hits its cap.
    const returns = discountedReturns(rounds.map((r) => r.reward));
    rounds.forEach((r, i) => pending.push({ ...r, reward: returns[i]! }));
    completed += rounds.length;
    decisions += rounds.reduce(
      (n, r) => n + r.leadExperiences.length + r.followExperiences.length,
      0,
    );
    results.push(result);
    onGame?.('practice', result);
  }
  onPhase?.('practice', performance.now() - practiceStarted, results.length);
  const updateStarted = performance.now();
  // Leave-one-round-out centering avoids including a sample in its own baseline.
  const rewardSum = pending.reduce((sum, r) => sum + r.reward, 0);
  for (const item of pending) {
    const baseline =
      pending.length > 1 ? (rewardSum - item.reward) / (pending.length - 1) : 0;
    const advantage = Math.max(-3, Math.min(3, item.reward - baseline));
    for (const e of [...item.leadExperiences, ...item.followExperiences])
      e.advantage = advantage;
  }
  // Exploration diagnostic: how often temperature sampling moved practice off
  // the greedy action evaluation would have played, and how much probability
  // the sampling distribution actually put on each. Probabilities use the
  // temperature the action was sampled at, not the evaluation temperature, so
  // they describe the distribution practice drew from. Argmax is temperature
  // invariant, so the greedy action is the same one evaluation would pick.
  // Measured offline; it plays no extra matches.
  const exploration = {
    sampled: 0,
    differentFromGreedy: 0,
    chosenProbability: 0,
    greedyProbability: 0,
  };
  for (const [model, experiences] of [
    [leadBase, pending.flatMap((r) => r.leadExperiences)],
    [followBase, pending.flatMap((r) => r.followExperiences)],
  ] as const)
    for (const experience of experiences) {
      if (experience.options.length < 2) continue;
      const sampling = policyProbabilities(
        model,
        experience.options,
        experience.temperature ?? 1,
      );
      const best = sampling.indexOf(Math.max(...sampling));
      exploration.sampled++;
      exploration.chosenProbability += sampling[experience.chosen]!;
      exploration.greedyProbability += sampling[best]!;
      if (experience.chosen !== best) exploration.differentFromGreedy++;
    }
  const explorationBehavior = {
    sampledDecisions: exploration.sampled,
    differentFromGreedy: exploration.differentFromGreedy,
    meanChosenProbability: exploration.sampled
      ? exploration.chosenProbability / exploration.sampled
      : 0,
    meanGreedyProbability: exploration.sampled
      ? exploration.greedyProbability / exploration.sampled
      : 0,
  };
  const alternativeChoices = pending.reduce(
    (sum, r) =>
      sum +
      [...r.leadExperiences, ...r.followExperiences].filter(
        (e) => e.options[e.chosen]!.prior === 0,
      ).length,
    0,
  );
  const leadUpdate = updateFromOutcomes(
    leadBase,
    pending.flatMap((r) => r.leadExperiences),
    preflightRollback ? newOptimizer() : checkpoint.leadOptimizer,
    checkpoint.config.counterfactualWeight ?? 0.1,
  );
  const followUpdate = updateFromOutcomes(
    followBase,
    pending.flatMap((r) => r.followExperiences),
    preflightRollback ? newOptimizer() : checkpoint.followOptimizer,
    checkpoint.config.counterfactualWeight ?? 0.1,
  );
  const leadLearner = leadUpdate.model;
  const followLearner = followUpdate.model;
  if (
    checkpoint.config.maxRounds > 1 &&
    (completed > 0 || decisions > 0) &&
    leadUpdate.epochs === 0 &&
    followUpdate.epochs === 0
  )
    throw new Error(
      `Policy generation ${generation} produced zero update epochs; refusing to save an untrained generation`,
    );
  // Epoch counts are reported separately; this phase plays no matches.
  onPhase?.('update', performance.now() - updateStarted, 0);
  pending.length = 0;
  // Whichever validation always runs supplies the behavior statistics.
  const behaviorPhase =
    checkpoint.robloxRules === true
      ? 'validation-roblox'
      : 'validation-baseline';
  function evaluate(
    opponent: Pair | 'sharp' | 'roblox' | null,
    phase: string,
    confirmation = false,
  ): Evaluation {
    const started = performance.now();
    const specs: EvaluationMatch[] = [];
    for (const playerCount of checkpoint.config.playerCounts) {
      // The Roblox re-test runs on twice as many fresh deals: a candidate is
      // only re-tested after a lucky first score, so a real but small edge
      // (about 55%) needs the larger sample to show above the noise.
      // A Roblox run plays its champion every generation (for rollback), so
      // that screen uses the usual deals; the promotion re-test stays large.
      const seedCount =
        phase === 'confirmation-roblox'
          ? checkpoint.config.validationSeeds * ROBLOX_CONFIRMATION_FACTOR
          : checkpoint.robloxRules === true && phase === 'validation-champion'
            ? checkpoint.config.validationSeeds
            : phase.includes('champion')
              ? checkpoint.config.validationSeeds >= 128
                ? Math.max(
                    checkpoint.config.validationSeeds,
                    PROMOTION_CHAMPION_SEEDS,
                  )
                : checkpoint.config.validationSeeds
              : checkpoint.config.validationSeeds;
      for (const baseSeed of generationSeeds(
        checkpoint.config,
        generation,
        true,
        seedCount,
      )) {
        const seed = confirmation ? (baseSeed + 1000000000) >>> 0 : baseSeed;
        for (const candidateTeam of ['A', 'B'] as const)
          specs.push({
            seed,
            playerCount,
            candidateTeam,
            maxRounds: checkpoint.config.maxRounds,
            robloxRules: checkpoint.robloxRules === true,
            lead: leadLearner,
            follow: followLearner,
            opponent,
            recordBehavior: phase === behaviorPhase,
          });
      }
    }
    const outcomes = playEvaluationMatches(specs);
    const matches = outcomes.map((outcome) => outcome.result);
    const logitSpreads = outcomes.flatMap((outcome) => outcome.logitSpreads);
    for (const outcome of outcomes) {
      evaluationBehavior.choices += outcome.choices;
      evaluationBehavior.differentFromBaseline += outcome.differentFromBaseline;
      onGame?.(phase, outcome.result);
    }
    const evaluation = summarizePaired(
      matches,
      generation * 7919 + (confirmation ? 17 : 0),
      phase === 'validation-champion' && !confirmation,
    );
    if (phase === behaviorPhase) {
      const sorted = [...logitSpreads].sort((a, b) => a - b);
      evaluationLogits.meanSpread = logitSpreads.length
        ? logitSpreads.reduce((sum, value) => sum + value, 0) /
          logitSpreads.length
        : 0;
      evaluationLogits.p90Spread = sorted.length
        ? sorted[Math.floor(sorted.length * 0.9)]!
        : 0;
    }
    evaluationMatches += matches.length;
    onPhase?.(phase, performance.now() - started, matches.length);
    return evaluation;
  }
  // A Roblox-rules run plays the Roblox bots first. Baseline and Sharp can only
  // refuse a promotion, so they wait until this score could earn one.
  const robloxFirst =
    checkpoint.robloxRules === true
      ? evaluate('roblox', 'validation-roblox')
      : null;
  const robloxPromising = !robloxFirst || policyPasses(robloxFirst);
  const vsBaseline = robloxPromising
    ? evaluate(null, 'validation-baseline')
    : summarize([]);
  const vsChampion = champion
    ? evaluate(champion, 'validation-champion')
    : vsBaseline;
  // The archive gate can only refuse a promotion the earlier gates already
  // refused, so a failed baseline or champion gate skips those matches.
  const gatesPassed =
    robloxPromising &&
    completed > 0 &&
    policyPasses(vsBaseline) &&
    policyPasses(vsChampion);
  // Held out: beating Sharp cannot come from having learned this pool's habits,
  // because practice never plays it. Measured only once the cheaper gates pass,
  // so a failing generation pays nothing for it.
  const sharpGate = checkpoint.sharpGate ?? true;
  const vsSharp = gatesPassed ? evaluate('sharp', 'validation-sharp') : null;
  const sharpPassed = !vsSharp || !sharpGate || policyPasses(vsSharp);
  const vsRoblox =
    robloxFirst ??
    (gatesPassed && sharpPassed
      ? evaluate('roblox', 'validation-roblox')
      : null);
  const robloxPassed = !vsRoblox || policyPasses(vsRoblox);
  const archived =
    gatesPassed && sharpPassed && robloxPassed
      ? archive[(generation - 1) % Math.max(1, archive.length)]
      : undefined;
  const vsArchive = archived ? evaluate(archived, 'validation-archive') : null;
  const screened =
    gatesPassed &&
    sharpPassed &&
    robloxPassed &&
    (!vsArchive || policyPasses(vsArchive));
  const confirmation = screened
    ? {
        baseline: evaluate(null, 'confirmation-baseline', true),
        champion: champion
          ? evaluate(champion, 'confirmation-champion', true)
          : null,
        sharp: sharpGate ? evaluate('sharp', 'confirmation-sharp', true) : null,
        roblox: evaluate('roblox', 'confirmation-roblox', true),
      }
    : null;
  const promoted =
    !!confirmation &&
    policyPasses(confirmation.baseline) &&
    (!confirmation.champion || policyPasses(confirmation.champion)) &&
    (!confirmation.sharp || policyPasses(confirmation.sharp)) &&
    policyPasses(confirmation.roblox);
  // Keep the exact evaluated prior. Changing it after KL validation silently
  // changes the saved policy and bypasses the update trust limit.
  const nextLeadLearner = parsePolicy(leadLearner);
  const nextFollowLearner = parsePolicy(followLearner);
  const evaluatedPair = {
    lead: parsePolicy(leadLearner),
    follow: parsePolicy(followLearner),
  };
  const nonPromotionStreak = promoted ? 0 : activeStreak + 1;
  const generationsSincePromotion = promoted ? 0 : startingSincePromotion + 1;
  const championMarginSamples = champion
    ? [...startingChampionMargins, ...(vsChampion.marginSamples ?? [])].slice(
        -2048,
      )
    : [];
  const championRegression: Evaluation | undefined = champion
    ? (() => {
        const interval = bootstrapMarginInterval(
          championMarginSamples,
          0x51f15e,
        );
        return {
          ...summarize([]),
          pairs: championMarginSamples.length,
          marginMean: interval.mean,
          marginLow: interval.low,
          marginHigh: interval.high,
          indistinguishable: interval.indistinguishable,
        };
      })()
    : undefined;
  const championLevelMarginSamples = champion
    ? [
        ...(preflightRollback ? [] : startingLevelMargins),
        ...(vsChampion.levelMarginSamples ?? []),
      ].slice(-2048)
    : [];
  if (championRegression) {
    const levelInterval = bootstrapMarginInterval(
      championLevelMarginSamples,
      0x51f15e,
    );
    championRegression.levelMarginMean = levelInterval.mean;
    championRegression.levelMarginLow = levelInterval.low;
    championRegression.levelMarginHigh = levelInterval.high;
    championRegression.pairs = championLevelMarginSamples.length;
    championRegression.indistinguishable = levelInterval.indistinguishable;
  }
  const learnerState = resolveLearnerGenerationState({
    championMargins: championLevelMarginSamples,
    rollbackCooldown: activeCooldown,
    nonPromotionStreak,
    promoted,
    candidate: { lead: nextLeadLearner, follow: nextFollowLearner },
    champion,
    leadOptimizer: leadUpdate.optimizer,
    followOptimizer: followUpdate.optimizer,
  });
  const robloxGuard =
    checkpoint.robloxRules === true && !champion && !promoted && vsRoblox
      ? resolveRobloxGuard({
          guard: checkpoint.robloxGuard,
          winRate: vsRoblox.wins / vsRoblox.games,
          generation,
          evaluated: evaluatedPair,
        })
      : null;
  const returnedToBest = robloxGuard?.returnTo ?? null;
  const streakAfterGuard = returnedToBest ? 0 : learnerState.nonPromotionStreak;
  onPhase?.(
    'generation',
    performance.now() - generationStarted,
    results.length + evaluationMatches,
  );
  // A promoted learner becomes the champion, so nothing needs protecting.
  const rollbackCooldown = promoted
    ? 0
    : learnerState.learnerReset
      ? ROLLBACK_COOLDOWN_GENERATIONS
      : activeCooldown;
  const models = resolveGenerationModels({
    promoted,
    evaluated: evaluatedPair,
    learner: returnedToBest ?? {
      lead: learnerState.lead,
      follow: learnerState.follow,
    },
    champion,
  });
  return {
    ...checkpoint,
    ...(robloxGuard ? { robloxGuard: robloxGuard.guard } : {}),
    ...(checkpoint.robloxRules === true ? { robloxChaodi: true } : {}),
    generation,
    nonPromotionStreak: streakAfterGuard,
    generationsSincePromotion,
    rollbackCooldown,
    championMarginSamples:
      promoted || learnerState.learnerReset ? [] : championMarginSamples,
    championLevelMarginSamples:
      promoted || learnerState.learnerReset ? [] : championLevelMarginSamples,
    leadOptimizer: returnedToBest ? newOptimizer() : learnerState.leadOptimizer,
    followOptimizer: returnedToBest
      ? newOptimizer()
      : learnerState.followOptimizer,
    policyArchive:
      promoted && champion ? retainArchive(archive, champion) : archive,
    learner: models.learner.lead,
    champion: models.champion?.lead ?? null,
    leadLearner: models.learner.lead,
    followLearner: models.learner.follow,
    leadChampion: models.champion?.lead ?? null,
    followChampion: models.champion?.follow ?? null,
    archive:
      promoted && checkpoint.champion
        ? retainArchive(checkpoint.archive, checkpoint.champion)
        : checkpoint.archive,
    reports: [
      ...checkpoint.reports,
      {
        pointMarginVersion: 2,
        generation,
        training: summarize(results),
        decisions,
        learningRounds: completed,
        alternativeChoices,
        comparisons,
        evaluationBehavior,
        explorationBehavior,
        evaluationLogits,
        vsChampion,
        vsBaseline,
        vsArchive,
        vsSharp,
        vsRoblox,
        promoted,
        learnerReset: preflightRollback || learnerState.learnerReset,
        rollbackCooldown,
        nonPromotionStreak: streakAfterGuard,
        generationsSincePromotion,
        ...(robloxGuard
          ? {
              robloxGuard: {
                recentWinRate:
                  robloxGuard.guard.recent.length === ROBLOX_GUARD_WINDOW
                    ? robloxGuard.guard.recent.reduce((a, b) => a + b, 0) /
                      ROBLOX_GUARD_WINDOW
                    : null,
                bestWinRate: robloxGuard.guard.best?.winRate ?? null,
                bestGeneration: robloxGuard.guard.best?.generation ?? null,
                returnedToBest: returnedToBest !== null,
              },
            }
          : {}),
        ...(championRegression ? { championRegression } : {}),
        ...(confirmation
          ? {
              confirmation: {
                baseline: confirmation.baseline,
                champion: confirmation.champion,
                sharp: confirmation.sharp,
                roblox: confirmation.roblox,
              },
            }
          : {}),
        update: {
          leadKL: leadUpdate.kl,
          followKL: followUpdate.kl,
          leadEpochs: leadUpdate.epochs,
          followEpochs: followUpdate.epochs,
        },
      },
    ],
  };
}
