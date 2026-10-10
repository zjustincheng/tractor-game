import { DEFAULT_BOT_LEAD_WEIGHTS } from '@tractor/rules';
import { learnedBotPolicy } from './bot-policy.js';
import type { BotPolicy } from '../bot-policy.js';
import { POLICY_VERSION } from './learned-policy.js';
import type { PolicyModel } from './learned-policy.js';
import type { TrainingConfig, Evaluation } from './optimizer.js';
import { summarizePaired } from './policy-training.js';
import type { SelfPlayResult } from './self-play.js';
import { playTrainingMatch } from './self-play.js';

export interface PolicyPair {
  lead: PolicyModel;
  follow: PolicyModel;
}

export interface HistoricalPolicyGame {
  file: string;
  generation: number;
  policyVersion: string;
  result: SelfPlayResult;
}

export interface HistoricalPolicySummary {
  file: string;
  generation: number;
  evaluation: Evaluation;
}

export function evaluatePolicyFresh(
  policy: PolicyPair,
  config: TrainingConfig,
  seedCount: number,
  seedStart: number,
  onProgress?: (completed: number, total: number, playerCount: number) => void,
  opposingPolicy: PolicyPair | null = null,
  opponentBot?: BotPolicy,
): Evaluation {
  const results: SelfPlayResult[] = [];
  const total = seedCount * config.playerCounts.length;
  for (const [playerCountIndex, playerCount] of config.playerCounts.entries()) {
    for (let index = 0; index < seedCount; index++) {
      const seed = (seedStart + index) >>> 0;
      for (const candidateTeam of ['A', 'B'] as const) {
        results.push(
          playTrainingMatch({
            seed,
            playerCount,
            candidateTeam,
            candidate: DEFAULT_BOT_LEAD_WEIGHTS,
            opponent: DEFAULT_BOT_LEAD_WEIGHTS,
            maxRounds: config.maxRounds,
            candidatePolicy: learnedBotPolicy(policy.lead, policy.follow),
            ...(opponentBot
              ? { opponentPolicy: opponentBot }
              : opposingPolicy
                ? {
                    opponentPolicy: learnedBotPolicy(
                      opposingPolicy.lead,
                      opposingPolicy.follow,
                    ),
                  }
                : {}),
          }),
        );
      }
      onProgress?.(
        playerCountIndex * seedCount + index + 1,
        total,
        playerCount,
      );
    }
  }
  return summarizePaired(results, seedStart ^ 0x63d83595);
}

export function parseHistoricalPolicyGame(
  value: unknown,
  file: string,
  fallbackPolicyVersion?: string,
): HistoricalPolicyGame | null {
  const row = value as {
    phase?: unknown;
    generation?: unknown;
    policyVersion?: unknown;
    result?: Partial<SelfPlayResult>;
  } | null;
  const policyVersion =
    typeof row?.policyVersion === 'string'
      ? row.policyVersion
      : fallbackPolicyVersion;
  const result = row?.result;
  if (
    row?.phase !== 'validation-baseline' ||
    policyVersion !== POLICY_VERSION ||
    !Number.isSafeInteger(row.generation) ||
    !result ||
    !Number.isSafeInteger(result.seed) ||
    ![4, 6, 8, 10].includes(result.playerCount as number) ||
    (result.candidateTeam !== 'A' && result.candidateTeam !== 'B') ||
    !result.levels ||
    !Array.isArray(result.settlements) ||
    typeof result.truncated !== 'boolean' ||
    !Number.isSafeInteger(result.rounds) ||
    !Number.isSafeInteger(result.decisions)
  )
    return null;
  return {
    file,
    generation: row.generation as number,
    policyVersion,
    result: result as SelfPlayResult,
  };
}

function stableHash(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export function summarizePolicyHistory(
  entries: readonly HistoricalPolicyGame[],
  seed = 193,
): { groups: HistoricalPolicySummary[]; pooled: Evaluation } {
  const groups = new Map<string, HistoricalPolicyGame[]>();
  for (const entry of entries) {
    const key = `${entry.file}:${entry.generation}`;
    const group = groups.get(key) ?? [];
    group.push(entry);
    groups.set(key, group);
  }
  const summaries: HistoricalPolicySummary[] = [];
  const pooledResults: SelfPlayResult[] = [];
  for (const [key, group] of groups) {
    const hash = stableHash(key);
    const results = group.map(({ result }) => ({
      ...result,
      // Keep A/B siblings paired while avoiding collisions across runs.
      seed: (result.seed ^ hash) >>> 0,
    }));
    const first = group[0]!;
    summaries.push({
      file: first.file,
      generation: first.generation,
      evaluation: summarizePaired(results, seed ^ hash),
    });
    pooledResults.push(...results);
  }
  return {
    groups: summaries,
    pooled: summarizePaired(pooledResults, seed ^ 0x9e3779b9),
  };
}

export function formatPolicyEvaluation(label: string, evaluation: Evaluation) {
  const fmt = (value: number | undefined) =>
    value === undefined ? 'n/a' : value.toFixed(3);
  return [
    `${label}: ${evaluation.wins}/${evaluation.games} wins; ${evaluation.pairs ?? 0} complete pairs; ${evaluation.truncated}/${evaluation.games} truncated`,
    `  point margin ${fmt(evaluation.marginMean)} [${fmt(evaluation.marginLow)}, ${fmt(evaluation.marginHigh)}]`,
    `  level margin ${fmt(evaluation.levelMarginMean)} [${fmt(evaluation.levelMarginLow)}, ${fmt(evaluation.levelMarginHigh)}]`,
    ...(evaluation.completedRounds === undefined
      ? []
      : [
          `  rounds won within these matches: ${evaluation.roundWins}/${evaluation.completedRounds} (descriptive; not a random-level quick-match evaluation)`,
        ]),
  ].join('\n');
}
