import { DEFAULT_BOT_LEAD_WEIGHTS } from '@tractor/rules';
import type { PlayerCount, Team } from '@tractor/rules';
import { heuristicPolicy } from '../bot-policy.js';
import { learnedBotPolicy } from './bot-policy.js';
import {
  choosePolicyBurial,
  choosePolicyChaodi,
  choosePolicyDeclaration,
  choosePolicyLead,
  choosePolicyPlay,
  learnedLogitSpread,
} from './learned-policy.js';
import type { PolicyExperience, PolicyModel } from './learned-policy.js';
import { robloxBotPolicy } from './roblox-bot.js';
import { playTrainingMatch, seededRandom } from './self-play.js';
import { compareAlternatives } from './counterfactual.js';
import type { ComparisonCounts, RoundPosition } from './counterfactual.js';
import { roundReward } from './policy-reward.js';
import type { SelfPlayResult } from './self-play.js';

export type EvaluationOpponent =
  { lead: PolicyModel; follow: PolicyModel } | 'sharp' | 'roblox' | null;

/** One evaluation game, as plain data so a worker thread can play it. */
export interface EvaluationMatch {
  seed: number;
  playerCount: PlayerCount;
  candidateTeam: Team;
  maxRounds: number;
  robloxRules: boolean;
  lead: PolicyModel;
  follow: PolicyModel;
  opponent: EvaluationOpponent;
  /** Collect the behavior statistics reported for this phase. */
  recordBehavior: boolean;
}

export interface EvaluationOutcome {
  result: SelfPlayResult;
  logitSpreads: number[];
  choices: number;
  differentFromBaseline: number;
}

export function opponentPolicies(
  opponent: EvaluationOpponent,
  robloxRules: boolean,
): Partial<Parameters<typeof playTrainingMatch>[0]> {
  if (!opponent) return {};
  if (opponent === 'roblox') return { opponentPolicy: robloxBotPolicy };
  // Sharp plays with its own validated-throw information, exactly as a player
  // meets it in the app. Practice never faces it, which is the point.
  if (opponent === 'sharp') return { opponentPolicy: heuristicPolicy('sharp') };
  const policy = learnedBotPolicy(
    opponent.lead,
    opponent.follow,
    {},
    { robloxRules },
  );
  return {
    opponentLead: (hand, trump, context) =>
      policy.lead(hand, trump, context, []),
    opponentPlay: policy.follow,
    opponentDeclaration: policy.declare,
    opponentBurial: policy.bury,
  };
}

/** Deterministic: the same match gives the same outcome on any thread. */
export function playEvaluationMatch(match: EvaluationMatch): EvaluationOutcome {
  const outcome: EvaluationOutcome = {
    result: undefined as unknown as SelfPlayResult,
    logitSpreads: [],
    choices: 0,
    differentFromBaseline: 0,
  };
  const record = (model: PolicyModel) => (e: PolicyExperience) => {
    if (!match.recordBehavior || e.options.length < 2) return;
    outcome.logitSpreads.push(learnedLogitSpread(model, e.options));
    const baseline = e.options.findIndex((o) => o.prior > 0);
    if (baseline < 0) return;
    outcome.choices++;
    if (e.chosen !== baseline) outcome.differentFromBaseline++;
  };
  const policy = learnedBotPolicy(
    match.lead,
    match.follow,
    { lead: record(match.lead), follow: record(match.follow) },
    { robloxRules: match.robloxRules, robloxChaodi: match.robloxRules },
  );
  outcome.result = playTrainingMatch({
    seed: match.seed,
    playerCount: match.playerCount,
    candidateTeam: match.candidateTeam,
    candidate: DEFAULT_BOT_LEAD_WEIGHTS,
    opponent: DEFAULT_BOT_LEAD_WEIGHTS,
    maxRounds: match.maxRounds,
    robloxRules: match.robloxRules,
    candidateLead: (hand, trump, context) =>
      policy.lead(hand, trump, context, []),
    candidatePlay: policy.follow,
    candidateDeclaration: policy.declare,
    candidateBurial: policy.bury,
    ...(policy.chaodi ? { candidateChaodi: policy.chaodi } : {}),
    ...opponentPolicies(match.opponent, match.robloxRules),
  });
  return outcome;
}

/** One practice game for the learner, as plain data for a worker thread. */
export interface PracticeMatch {
  seed: number;
  playerCount: PlayerCount;
  candidateTeam: Team;
  maxRounds: number;
  robloxRules: boolean;
  /** Undefined keeps the counterfactual comparisons on, as in the config. */
  counterfactualWeight?: number | undefined;
  lead: PolicyModel;
  follow: PolicyModel;
  opponent: EvaluationOpponent;
}

export interface PracticeRound {
  leadExperiences: PolicyExperience[];
  followExperiences: PolicyExperience[];
  /** This round's own reward; the caller discounts across rounds. */
  reward: number;
}

export interface PracticeOutcome {
  result: SelfPlayResult;
  rounds: PracticeRound[];
  comparisons: ComparisonCounts;
}

/** Deterministic: exploration and comparison use streams seeded per game. */
export function playPracticeMatch(match: PracticeMatch): PracticeOutcome {
  const { seed, playerCount, candidateTeam } = match;
  const leadBase = match.lead;
  const followBase = match.follow;
  const continuation = learnedBotPolicy(leadBase, followBase);
  const comparisons: ComparisonCounts = {
    positions: 0,
    rollouts: 0,
    informativePairs: 0,
    betterThanBaseline: 0,
  };
  let leadExperiences: PolicyExperience[] = [];
  let followExperiences: PolicyExperience[] = [];
  const rounds: PracticeRound[] = [];
  // Exploration uses a separate stream and cannot change the shuffled cards.
  const pick = seededRandom(
    (seed ^
      Math.imul(playerCount, 7919) ^
      (candidateTeam === 'A' ? 0x9e3779b9 : 0x85ebca6b)) >>>
      0,
  );
  // Reservoir sampling covers the whole match with eight bounded positions.
  // Its random stream cannot change deals or the acting policy's exploration.
  const comparePick = seededRandom(
    (seed ^
      Math.imul(playerCount, 15485863) ^
      (candidateTeam === 'A' ? 0x51ed270b : 0x41c64e6d)) >>>
      0,
  );
  const positions: {
    position: RoundPosition;
    experience: PolicyExperience;
  }[] = [];
  let eligible = 0;
  let lastExperience: PolicyExperience | undefined;
  const result = playTrainingMatch({
    seed,
    playerCount,
    candidateTeam,
    candidate: DEFAULT_BOT_LEAD_WEIGHTS,
    opponent: DEFAULT_BOT_LEAD_WEIGHTS,
    maxRounds: match.maxRounds,
    robloxRules: match.robloxRules,
    candidateLead: (hand, trump, context) =>
      choosePolicyLead(leadBase, hand, trump, context, pick, (experience) => {
        leadExperiences.push(experience);
        lastExperience = experience;
      }),
    candidatePlay: (hand, lead, trump, context) =>
      choosePolicyPlay(
        followBase,
        hand,
        lead,
        trump,
        context,
        pick,
        (experience) => {
          followExperiences.push(experience);
          lastExperience = experience;
        },
      ),
    candidateDeclaration: (options, hand, level) =>
      choosePolicyDeclaration(followBase, options, hand, level, pick, (e) =>
        followExperiences.push(e),
      ),
    ...(match.robloxRules
      ? {
          candidateChaodi: (calls, hand, trump, sameTeam) =>
            choosePolicyChaodi(
              followBase,
              calls,
              hand,
              trump,
              sameTeam,
              pick,
              (experience) => followExperiences.push(experience),
            ),
        }
      : {}),
    candidateBurial: (cards, size, trump) =>
      choosePolicyBurial(
        followBase,
        cards,
        size,
        trump,
        pick,
        (experience) => followExperiences.push(experience),
        match.robloxRules,
      ),
    ...opponentPolicies(match.opponent, match.robloxRules),
    onPosition: (position) => {
      const seat = position.trick.nextSeat!;
      if (seat % 2 !== (candidateTeam === 'A' ? 0 : 1)) return;
      const experience = lastExperience;
      lastExperience = undefined;
      if (!experience || experience.options.length < 2) return;
      const index = comparePick(++eligible);
      if (positions.length < 8) positions.push({ position, experience });
      else if (index < 8) positions[index] = { position, experience };
    },
    onRound: (settlement, { levels, attackingTeam }) => {
      rounds.push({
        leadExperiences,
        followExperiences,
        reward: roundReward(
          levels,
          settlement,
          candidateTeam,
          playerCount,
          attackingTeam,
        ),
      });
      leadExperiences = [];
      followExperiences = [];
    },
  });
  for (const { position, experience } of match.counterfactualWeight === 0
    ? []
    : positions) {
    const counts = compareAlternatives(
      position,
      experience,
      comparePick,
      4,
      continuation,
    );
    for (const key of [
      'positions',
      'rollouts',
      'informativePairs',
      'betterThanBaseline',
    ] as const)
      comparisons[key] += counts[key];
  }
  return { result, rounds, comparisons };
}
