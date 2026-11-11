import { botPlayContext } from '../bot-play-context.js';
import {
  category,
  chooseBotLead,
  chooseBotPlay,
  compareComponents,
  playCards,
  settleRound,
  samplePossibleDeal,
  startTrick,
  teamAt,
} from '@tractor/rules';
import type { Card, MatchState, Team, TrickState } from '@tractor/rules';
import type { PolicyExperience } from './learned-policy.js';
import type { BotPolicy } from '../bot-policy.js';
import { roundReward } from './policy-reward.js';

/** Privileged simulator state. Never put it in model features or checkpoints. */
export interface RoundPosition {
  trick: TrickState;
  levels: MatchState['levels'];
  kitty: readonly Card[];
  captured: number;
  penalties: number;
  seenCards: readonly Card[];
  knownVoids: { seat: number; category: string }[];
  dealerSeat?: number;
  exposedCards?: { cardId: string; seat: number; mayBeBuried: boolean }[];
}

interface BeliefWorld {
  hands: Card[][];
  kitty: Card[];
}

function visibleCards(position: RoundPosition): Card[] {
  return [
    ...position.seenCards,
    ...position.trick.plays.flatMap((play) => play.cards),
  ];
}

/** Build public-information-only deal samples for a counterfactual. */
export function sampleBeliefWorlds(
  position: RoundPosition,
  samples: number,
): BeliefWorld[] {
  const seat = position.trick.nextSeat!;
  const seen = visibleCards(position);
  const knownVoids = [...position.knownVoids];
  const opening = position.trick.plays[0];
  if (opening) {
    const led = category(opening.cards[0]!, position.trick.trump);
    for (const play of position.trick.plays)
      if (play.cards.some((c) => category(c, position.trick.trump) !== led))
        knownVoids.push({ seat: play.seat, category: led });
  }
  let seed = 2166136261;
  for (const card of [...position.trick.hands[seat]!, ...seen])
    for (const char of card.id)
      seed = Math.imul(seed ^ char.charCodeAt(0), 16777619);
  const pick = (max: number) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return Math.floor((seed / 0x100000000) * max);
  };
  const worlds: BeliefWorld[] = [];
  for (let i = 0; i < samples; i++) {
    const world = samplePossibleDeal(
      {
        playerCount: position.trick.playerCount,
        ownHand: position.trick.hands[seat]!,
        seat,
        trump: position.trick.trump,
        seenCards: seen,
        knownVoids,
        handSizes: position.trick.hands.map((hand) => hand.length),
        ...(seat === position.dealerSeat ? { knownKitty: position.kitty } : {}),
        ...(position.exposedCards
          ? { exposedCards: position.exposedCards }
          : {}),
      },
      pick,
    );
    if (!world) return [];
    worlds.push(world);
  }
  return worlds;
}

function rolloutRoundWithWorld(
  position: RoundPosition,
  cards: readonly string[],
  team: Team,
  world: BeliefWorld,
  continuation?: BotPolicy,
): number {
  return rolloutRoundInternal(
    position,
    cards,
    team,
    world.hands,
    world.kitty,
    continuation,
  );
}

/** Change exactly one action, then use identical deterministic continuation
 * policies in every branch. All actions still pass the normal rules engine. */
export function rolloutRound(
  position: RoundPosition,
  cards: readonly string[],
  team: Team,
): number {
  return rolloutRoundInternal(
    position,
    cards,
    team,
    position.trick.hands,
    position.kitty,
  );
}

function rolloutRoundInternal(
  position: RoundPosition,
  cards: readonly string[],
  team: Team,
  initialHands: readonly (readonly Card[])[],
  kitty: readonly Card[],
  continuation?: BotPolicy,
): number {
  let trick: TrickState = {
    ...position.trick,
    hands: initialHands.map((hand) => [...hand]),
  };
  let captured = position.captured;
  let penalties = position.penalties;
  const seen = [...position.seenCards];
  const voids = new Map(
    position.knownVoids.map((v) => [`${v.seat}:${v.category}`, v]),
  );
  let first = true;
  for (;;) {
    const seat = trick.nextSeat!;
    const hand = trick.hands[seat]!;
    const chosen = first
      ? cards
      : trick.plays.length === 0
        ? (continuation?.lead ?? chooseBotLead)(
            hand,
            trick.trump,
            {
              seat,
              ...(position.dealerSeat === undefined
                ? {}
                : { dealerSeat: position.dealerSeat }),
              playerCount: trick.playerCount,
              cardsRemaining: hand.length,
              role:
                teamAt(seat) === trick.attackingTeam
                  ? 'attackers'
                  : 'defenders',
              defenderScore: captured + penalties,
              swapThreshold: trick.playerCount * 20,
              seenCards: seen,
              knownVoids: [...voids.values()],
            },
            [],
          )
        : (continuation?.follow ?? chooseBotPlay)(
            hand,
            trick.plays[0]!.components!,
            trick.trump,
            botPlayContext(trick, position.dealerSeat),
          );
    first = false;
    const result = playCards(trick, seat, chosen);
    if (!result.ok)
      throw new Error(
        `Counterfactual produced an illegal move: ${result.message}`,
      );
    trick = result.state;
    if (trick.status !== 'complete') continue;
    captured += trick.capturedDefenderPoints;
    penalties += trick.penaltyPoints;
    const ledCategory = category(trick.plays[0]!.cards[0]!, trick.trump);
    for (const play of trick.plays) {
      seen.push(...play.cards);
      if (
        play.cards.some((card) => category(card, trick.trump) !== ledCategory)
      )
        voids.set(`${play.seat}:${ledCategory}`, {
          seat: play.seat,
          category: ledCategory,
        });
    }
    if (trick.hands.every((hand) => hand.length === 0)) break;
    trick = startTrick({
      playerCount: trick.playerCount,
      hands: trick.hands,
      trump: trick.trump,
      attackingTeam: trick.attackingTeam,
      leaderSeat: trick.winnerSeat!,
      ...(trick.largestPatternWins ? { largestPatternWins: true } : {}),
    });
  }
  const winning = trick.plays.find((p) => p.seat === trick.winnerSeat)!;
  const settlement = settleRound({
    playerCount: trick.playerCount,
    attackingTeam: trick.attackingTeam,
    levels: position.levels,
    trickPoints: captured,
    gamblePenaltyPoints: penalties,
    finalTrickWinnerTeam: teamAt(trick.winnerSeat!),
    finalWinningCards: winning.cards,
    finalWinningStructure: [...winning.components!].sort(compareComponents)[0]!,
    kitty,
  });
  return roundReward(
    position.levels,
    settlement,
    team,
    trick.playerCount,
    trick.attackingTeam,
  );
}

export interface ComparisonCounts {
  positions: number;
  rollouts: number;
  informativePairs: number;
  betterThanBaseline: number;
}
const MIN_COMPARISON_MARGIN = 0.15;

/** Include the baseline and played action, then sample untested alternatives.
 * Ties teach nothing. Untested moves are never treated as losing moves. */
export function compareAlternatives(
  position: RoundPosition,
  experience: PolicyExperience,
  pick: (max: number) => number,
  beliefSamples = 4,
  continuation?: BotPolicy,
): ComparisonCounts {
  const baseline = experience.options.findIndex((o) => o.prior > 0);
  // Without a known handcrafted reference, a rollout comparison can reward a
  // move against an arbitrary sampled action and drift the policy for no reason.
  if (baseline < 0)
    return {
      positions: 1,
      rollouts: 0,
      informativePairs: 0,
      betterThanBaseline: 0,
    };
  const reference = baseline;
  const indices = new Set([reference, experience.chosen]);
  const remaining = experience.options
    .map((_, i) => i)
    .filter((i) => !indices.has(i));
  while (indices.size < 3 && remaining.length)
    indices.add(remaining.splice(pick(remaining.length), 1)[0]!);
  const team = teamAt(position.trick.nextSeat!);
  if (!Number.isInteger(beliefSamples) || beliefSamples < 1)
    throw new Error('beliefSamples must be a positive integer');
  const worlds = sampleBeliefWorlds(position, beliefSamples);
  if (!worlds.length) {
    experience.comparisons = [];
    return {
      positions: 1,
      rollouts: 0,
      informativePairs: 0,
      betterThanBaseline: 0,
    };
  }
  const scores = new Map(
    [...indices].map((i) => {
      const rewards = worlds.map((world) =>
        rolloutRoundWithWorld(
          position,
          experience.options[i]!.cardIds,
          team,
          world,
          continuation,
        ),
      );
      return [
        i,
        rewards.reduce((sum, reward) => sum + reward, 0) / rewards.length,
      ];
    }),
  );
  const comparisons: NonNullable<PolicyExperience['comparisons']> = [];
  let betterThanBaseline = 0;
  for (const [index, score] of scores) {
    const difference = score - scores.get(reference)!;
    if (index === reference || Math.abs(difference) < MIN_COMPARISON_MARGIN)
      continue;
    comparisons.push({
      better: difference > 0 ? index : reference,
      worse: difference > 0 ? reference : index,
      weight: Math.min(1, Math.abs(difference) - MIN_COMPARISON_MARGIN),
    });
    if (baseline >= 0 && difference > 0) betterThanBaseline++;
  }
  experience.comparisons = comparisons;
  return {
    positions: 1,
    rollouts: scores.size * worlds.length,
    informativePairs: comparisons.length,
    betterThanBaseline,
  };
}
