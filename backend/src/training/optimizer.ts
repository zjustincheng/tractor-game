import {
  DEFAULT_BOT_LEAD_WEIGHTS,
  PLAYER_COUNTS,
  RULES_VERSION,
} from '@tractor/rules';
import type { BotLeadWeights, PlayerCount, Team } from '@tractor/rules';
import {
  playTrainingMatch,
  seededRandom,
  TRAINING_POLICY_VERSION,
} from './self-play.js';
import type { SelfPlayResult, TrainingDecision } from './self-play.js';
import { scorePostGameTrajectories } from './post-game-scorer.js';
import type {
  PostGameAnalysis,
  PostGameTrajectory,
} from './post-game-scorer.js';

export const WEIGHT_KEYS = Object.keys(
  DEFAULT_BOT_LEAD_WEIGHTS,
) as (keyof BotLeadWeights)[];

export function parseWeights(value: unknown): BotLeadWeights {
  if (!value || typeof value !== 'object')
    throw new Error('Missing model weights');
  const weights = value as Record<string, unknown>;
  if (Object.keys(weights).length !== WEIGHT_KEYS.length)
    throw new Error('Unexpected weight keys');
  for (const key of WEIGHT_KEYS) {
    const weight = weights[key];
    if (
      typeof weight !== 'number' ||
      !Number.isFinite(weight) ||
      weight < 0 ||
      weight > DEFAULT_BOT_LEAD_WEIGHTS[key] * 4
    )
      throw new Error(`Invalid model weight: ${key}`);
  }
  return { ...weights } as unknown as BotLeadWeights;
}

export function mutateWeights(
  parent: BotLeadWeights,
  seed: number,
): BotLeadWeights {
  const pick = seededRandom(seed);
  const next = { ...parent };
  // Change a subset each generation, using absolute steps so zero weights can recover.
  const selected = new Set<keyof BotLeadWeights>();
  while (selected.size < 3)
    selected.add(WEIGHT_KEYS[pick(WEIGHT_KEYS.length)]!);
  for (const key of selected) {
    const step =
      (pick(2) ? 1 : -1) *
      DEFAULT_BOT_LEAD_WEIGHTS[key] *
      (0.15 + pick(36) / 100);
    next[key] = Number(
      Math.max(
        0,
        Math.min(DEFAULT_BOT_LEAD_WEIGHTS[key] * 4, parent[key] + step),
      ).toFixed(4),
    );
  }
  return next;
}

export interface TrainingConfig {
  seed: number;
  playerCounts: PlayerCount[];
  trainSeeds: number;
  validationSeeds: number;
  maxRounds: number;
  counterfactualWeight?: number;
}

export function parseConfig(value: unknown): TrainingConfig {
  if (!value || typeof value !== 'object')
    throw new Error('Missing training configuration');
  const config = value as TrainingConfig;
  if (
    config.counterfactualWeight !== undefined &&
    (!Number.isFinite(config.counterfactualWeight) ||
      config.counterfactualWeight < 0 ||
      config.counterfactualWeight > 1)
  )
    throw new Error('Invalid counterfactualWeight');
  for (const key of [
    'seed',
    'trainSeeds',
    'validationSeeds',
    'maxRounds',
  ] as const) {
    if (
      !Number.isSafeInteger(config[key]) ||
      config[key] < (key === 'seed' ? 0 : 1)
    )
      throw new Error(`Invalid ${key}`);
  }
  if (
    config.seed > 0xffffffff ||
    config.trainSeeds > 10000 ||
    config.validationSeeds > 10000 ||
    config.maxRounds > 200
  )
    throw new Error('Training limits exceeded');
  if (
    !Array.isArray(config.playerCounts) ||
    !config.playerCounts.length ||
    new Set(config.playerCounts).size !== config.playerCounts.length ||
    config.playerCounts.some((count) => !PLAYER_COUNTS.includes(count))
  )
    throw new Error('Players must be a unique list of 4, 6, 8, or 10');
  return {
    seed: config.seed,
    trainSeeds: config.trainSeeds,
    validationSeeds: config.validationSeeds,
    maxRounds: config.maxRounds,
    counterfactualWeight: config.counterfactualWeight ?? 0.1,
    playerCounts: [...config.playerCounts],
  };
}

export interface Evaluation {
  games: number;
  wins: number;
  losses: number;
  truncated: number;
  winRate: number;
  pairs?: number;
  marginMean?: number;
  marginLow?: number;
  marginHigh?: number;
  levelMarginMean?: number;
  levelMarginLow?: number;
  levelMarginHigh?: number;
  indistinguishable?: boolean;
  /** Candidate-normalized margins for pooling evidence across generations. */
  marginSamples?: number[];
  levelMarginSamples?: number[];
  roundWins?: number;
  completedRounds?: number;
}

export function summarize(results: readonly SelfPlayResult[]): Evaluation {
  const wins = results.filter(
    (result) => result.winner === result.candidateTeam,
  ).length;
  const truncated = results.filter((result) => result.truncated).length;
  return {
    games: results.length,
    wins,
    losses: results.length - wins - truncated,
    truncated,
    winRate: results.length ? wins / results.length : 0,
  };
}

export interface GenerationReport {
  generation: number;
  candidate: BotLeadWeights;
  postGameAnalysis: PostGameAnalysis;
  training: Evaluation;
  validationCandidate: Evaluation | null;
  validationIncumbent: Evaluation | null;
  accepted: boolean;
}

export function shouldPromote(
  candidate: Evaluation,
  incumbent: Evaluation,
): boolean {
  return (
    candidate.games > 0 &&
    candidate.games === incumbent.games &&
    candidate.truncated === 0 &&
    incumbent.truncated === 0 &&
    candidate.winRate > 0.5 &&
    candidate.winRate > incumbent.winRate
  );
}

export interface Checkpoint {
  format: 1;
  rulesVersion: string;
  policyVersion: string;
  generation: number;
  config: TrainingConfig;
  weights: BotLeadWeights;
  reports: GenerationReport[];
}

export function newCheckpoint(config: TrainingConfig): Checkpoint {
  return {
    format: 1,
    rulesVersion: RULES_VERSION,
    policyVersion: TRAINING_POLICY_VERSION,
    generation: 0,
    config: parseConfig(config),
    weights: { ...DEFAULT_BOT_LEAD_WEIGHTS },
    reports: [],
  };
}

export function parseCheckpoint(value: unknown): Checkpoint {
  if (!value || typeof value !== 'object')
    throw new Error('Invalid checkpoint');
  const model = value as Checkpoint;
  if (
    model.format !== 1 ||
    model.rulesVersion !== RULES_VERSION ||
    model.policyVersion !== TRAINING_POLICY_VERSION ||
    !Number.isSafeInteger(model.generation) ||
    model.generation < 0 ||
    model.generation > 10000 ||
    !Array.isArray(model.reports) ||
    model.reports.length !== model.generation
  )
    throw new Error('Checkpoint version or generation is incompatible');
  return {
    ...model,
    weights: parseWeights(model.weights),
    config: parseConfig(model.config),
  };
}

export interface GameLog {
  generation: number;
  phase: 'training' | 'validation-candidate' | 'validation-incumbent';
  result: SelfPlayResult;
}

export function generationSeeds(
  config: TrainingConfig,
  generation: number,
  validation: boolean,
  count = validation ? config.validationSeeds : config.trainSeeds,
): number[] {
  // Disjoint seed ranges for every generation and phase (within the CLI's generation limits).
  const start = config.seed + generation * 20000 + (validation ? 10000 : 0);
  return Array.from({ length: count }, (_, index) => (start + index) >>> 0);
}

/** Evolutionary self-play: outcome feedback selects weight mutations, no human labels. */
export function trainGeneration(
  checkpoint: Checkpoint,
  hooks: {
    onGame?: (game: GameLog) => void;
    onDecision?: (
      game: Omit<GameLog, 'result'> & {
        seed: number;
        candidateTeam: Team;
        playerCount: PlayerCount;
      },
      decision: TrainingDecision,
    ) => void;
  } = {},
): Checkpoint {
  const generation = checkpoint.generation + 1;
  if (generation > 10000)
    throw new Error('Maximum checkpoint generation reached');
  const candidate = mutateWeights(
    checkpoint.weights,
    (checkpoint.config.seed + generation) >>> 0,
  );
  function evaluate(
    weights: BotLeadWeights,
    opponent: BotLeadWeights,
    phase: GameLog['phase'],
  ): { evaluation: Evaluation; trajectories: PostGameTrajectory[] } {
    const results: SelfPlayResult[] = [];
    const trajectories: PostGameTrajectory[] = [];
    for (const playerCount of checkpoint.config.playerCounts) {
      for (const seed of generationSeeds(
        checkpoint.config,
        generation,
        phase !== 'training',
      )) {
        for (const candidateTeam of ['A', 'B'] as const) {
          const identity = {
            generation,
            phase,
            seed,
            candidateTeam,
            playerCount,
          };
          const decisions: TrainingDecision[] = [];
          const result = playTrainingMatch({
            ...identity,
            candidate: weights,
            opponent,
            maxRounds: checkpoint.config.maxRounds,
            onDecision: (decision: TrainingDecision) => {
              if (decision.team === candidateTeam) decisions.push(decision);
              hooks.onDecision?.(identity, decision);
            },
          });
          results.push(result);
          trajectories.push({
            candidateTeam,
            winner: result.winner,
            decisions,
          });
          hooks.onGame?.({ generation, phase, result });
        }
      }
    }
    return { evaluation: summarize(results), trajectories };
  }
  const trainingResult = evaluate(candidate, checkpoint.weights, 'training');
  const scored = scorePostGameTrajectories(
    candidate,
    trainingResult.trajectories,
  );
  const training = trainingResult.evaluation;
  let validationCandidate: Evaluation | null = null;
  let validationIncumbent: Evaluation | null = null;
  if (!training.truncated && training.winRate > 0.5) {
    validationCandidate = evaluate(
      scored.weights,
      DEFAULT_BOT_LEAD_WEIGHTS,
      'validation-candidate',
    ).evaluation;
    validationIncumbent = evaluate(
      checkpoint.weights,
      DEFAULT_BOT_LEAD_WEIGHTS,
      'validation-incumbent',
    ).evaluation;
  }
  const accepted =
    validationCandidate !== null &&
    validationIncumbent !== null &&
    shouldPromote(validationCandidate, validationIncumbent);
  return {
    ...checkpoint,
    generation,
    weights: accepted ? scored.weights : checkpoint.weights,
    reports: [
      ...checkpoint.reports,
      {
        generation,
        candidate: scored.weights,
        postGameAnalysis: scored.analysis,
        training,
        validationCandidate,
        validationIncumbent,
        accepted,
      },
    ],
  };
}
