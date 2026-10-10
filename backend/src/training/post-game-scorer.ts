import {
  cardPoints,
  category,
  decomposeLead,
  effectivePower,
  teamAt,
} from '@tractor/rules';
import type { BotLeadWeights, Team } from '@tractor/rules';
import { DEFAULT_BOT_LEAD_WEIGHTS } from '@tractor/rules';
import type { TrainingDecision } from './self-play.js';

const WEIGHT_KEYS = Object.keys(
  DEFAULT_BOT_LEAD_WEIGHTS,
) as (keyof BotLeadWeights)[];

export interface PostGameTrajectory {
  candidateTeam: Team;
  winner: Team | null;
  decisions: readonly TrainingDecision[];
}

export interface FeatureAssociation {
  winnerMean: number;
  loserMean: number;
  correlation: number;
  adjustment: number;
}

export interface PostGameAnalysis {
  matches: number;
  wins: number;
  losses: number;
  leadDecisions: number;
  applied: boolean;
  associations: Record<keyof BotLeadWeights, FeatureAssociation>;
}

type Features = Record<keyof BotLeadWeights, number>;

function blankFeatures(): Features {
  return Object.fromEntries(WEIGHT_KEYS.map((key) => [key, 0])) as Features;
}

function meanFeatures(decisions: readonly TrainingDecision[]): {
  features: Features;
  leads: number;
} {
  const total = blankFeatures();
  let leads = 0;
  for (const decision of decisions) {
    if (decision.publicPlays.length) continue;
    const selected = decision.hand.filter((card) =>
      decision.chosenCards.includes(card.id),
    );
    const lead = decomposeLead(selected, decision.trump);
    if (!lead) continue;
    leads++;
    const selectedCategory = category(selected[0]!, decision.trump);
    const points = selected.reduce((sum, card) => sum + cardPoints(card), 0);
    const highest = Math.max(
      ...selected.map((card) => effectivePower(card, decision.trump)),
    );
    const seenInCategory = decision.seenCards.filter(
      (card) => category(card, decision.trump) === selectedCategory,
    ).length;
    const seenAtHighEnd = decision.seenCards.filter(
      (card) =>
        category(card, decision.trump) === selectedCategory &&
        effectivePower(card, decision.trump) >= highest,
    ).length;
    const opponentVoids = new Set(
      decision.knownVoids
        .filter(
          (voidInfo) =>
            voidInfo.category === selectedCategory &&
            teamAt(voidInfo.seat) !== decision.team,
        )
        .map((voidInfo) => voidInfo.seat),
    ).size;
    const partnerVoids = new Set(
      decision.knownVoids
        .filter(
          (voidInfo) =>
            voidInfo.category === selectedCategory &&
            voidInfo.seat !== decision.seat &&
            teamAt(voidInfo.seat) === decision.team,
        )
        .map((voidInfo) => voidInfo.seat),
    ).size;
    const hasStructure = lead.some((component) => component.rankCount > 1);
    total.structure += Number(hasStructure);
    total.structurePerCard += hasStructure ? selected.length : 0;
    total.trump += Number(selectedCategory === 'trump');
    total.freshness += Math.max(0, 12 - seenInCategory) / 12;
    total.freshnessHigh += Math.max(0, 6 - seenAtHighEnd) / 6;
    // These signs match the corresponding term in chooseBotLead's score.
    total.jokerSmall -= selected.filter(
      (card) => card.kind === 'joker' && card.joker === 'small',
    ).length;
    total.jokerBig -= selected.filter(
      (card) => card.kind === 'joker' && card.joker === 'big',
    ).length;
    total.opponentVoid -= opponentVoids;
    if (decision.role === 'attackers')
      total.partnerVoidAttackers += partnerVoids;
    else total.partnerVoidDefenders += partnerVoids;
    if (decision.hand.length <= 4) {
      total.endgamePower += highest / 30;
      total.endgamePoints += points / 20;
    }
  }
  if (!leads) return { features: total, leads };
  for (const key of WEIGHT_KEYS) total[key] /= leads;
  return { features: total, leads };
}

function association(
  observations: readonly { reward: number; features: Features }[],
  key: keyof BotLeadWeights,
): FeatureAssociation {
  const winners = observations.filter((item) => item.reward > 0);
  const losers = observations.filter((item) => item.reward < 0);
  const winnerMean = winners.length
    ? winners.reduce((sum, item) => sum + item.features[key], 0) /
      winners.length
    : 0;
  const loserMean = losers.length
    ? losers.reduce((sum, item) => sum + item.features[key], 0) / losers.length
    : 0;
  const mean =
    observations.reduce((sum, item) => sum + item.features[key], 0) /
    observations.length;
  const variance = observations.reduce(
    (sum, item) => sum + (item.features[key] - mean) ** 2,
    0,
  );
  const covariance = observations.reduce(
    (sum, item) => sum + (item.features[key] - mean) * item.reward,
    0,
  );
  const rewardVariance = observations.reduce(
    (sum, item) => sum + item.reward ** 2,
    0,
  );
  const correlation =
    variance && rewardVariance
      ? covariance / Math.sqrt(variance * rewardVariance)
      : 0;
  return { winnerMean, loserMean, correlation, adjustment: 0 };
}

/**
 * Analyse finished self-play games after their outcome is known. It uses the
 * association between public-state lead features and match result, never a
 * hand-written label such as "good ruff". The update is deliberately small:
 * held-out matches still decide whether it is allowed into the checkpoint.
 */
export function scorePostGameTrajectories(
  weights: BotLeadWeights,
  trajectories: readonly PostGameTrajectory[],
): { weights: BotLeadWeights; analysis: PostGameAnalysis } {
  const observations = trajectories
    .filter((trajectory) => trajectory.winner !== null)
    .map((trajectory) => {
      const summary = meanFeatures(trajectory.decisions);
      return {
        reward: trajectory.winner === trajectory.candidateTeam ? 1 : -1,
        ...summary,
      };
    })
    .filter((observation) => observation.leads > 0);
  const wins = observations.filter((item) => item.reward > 0).length;
  const losses = observations.length - wins;
  const evidence = Math.min(1, observations.length / 40);
  const applied = observations.length >= 12 && wins > 0 && losses > 0;
  const next = { ...weights };
  const associations = blankFeatures() as unknown as Record<
    keyof BotLeadWeights,
    FeatureAssociation
  >;
  for (const key of WEIGHT_KEYS) {
    const result = observations.length
      ? association(observations, key)
      : { winnerMean: 0, loserMean: 0, correlation: 0, adjustment: 0 };
    const adjustment = applied
      ? Math.max(
          -DEFAULT_BOT_LEAD_WEIGHTS[key] * 0.3,
          Math.min(
            DEFAULT_BOT_LEAD_WEIGHTS[key] * 0.3,
            DEFAULT_BOT_LEAD_WEIGHTS[key] * 0.2 * result.correlation * evidence,
          ),
        )
      : 0;
    result.adjustment = Number(adjustment.toFixed(4));
    associations[key] = result;
    if (applied)
      next[key] = Number(
        Math.max(
          0,
          Math.min(
            DEFAULT_BOT_LEAD_WEIGHTS[key] * 4,
            weights[key] + result.adjustment,
          ),
        ).toFixed(4),
      );
  }
  return {
    weights: next,
    analysis: {
      matches: observations.length,
      wins,
      losses,
      leadDecisions: observations.reduce((sum, item) => sum + item.leads, 0),
      applied,
      associations,
    },
  };
}
