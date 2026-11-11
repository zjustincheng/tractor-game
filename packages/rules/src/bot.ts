import { cardPoints, category, effectivePower, teamAt } from './cards.js';
import {
  estimatePartnerRuffProbability,
  samplePossibleHands,
} from './belief.js';
import type { Card, PlayerCount, Trump } from './cards.js';
import {
  availableComponents,
  decomposeLead,
  identityGroups,
  matchComponents,
  withoutCards,
} from './components.js';
import type { Component } from './components.js';
import { validateFollow } from './follow.js';
import { beatsPlay, winningComponents } from './gamble.js';
import { validateGamble } from './gamble.js';
import type { Declaration } from './declarations.js';

export interface BotPlayContext {
  /** Public points already on the table and opponents still to act. */
  trickPoints?: number;
  opponentsRemaining?: number;
  seat: number;
  winnerSeat: number;
  winning: readonly Component[];
  lastToPlay: boolean;
  dealerSeat?: number;
  /** Roblox (D16): throws are won or lost on their largest piece. */
  largestPatternWins?: boolean;
}

export interface BotLeadContext {
  role: 'attackers' | 'defenders';
  defenderScore: number;
  swapThreshold: number;
  seenCards?: readonly Card[];
  seat?: number;
  /** Seat that exchanged the kitty this round, when known to the caller. */
  dealerSeat?: number;
  playerCount?: number;
  cardsRemaining?: number;
  knownVoids?: readonly { seat: number; category: string }[];
  beliefSearch?: boolean;
  beliefSearchSamples?: number;
  weights?: Partial<BotLeadWeights>;
}

/** Tunable lead parameters used by self-play training and the default bot. */
export interface BotLeadWeights {
  structure: number;
  structurePerCard: number;
  trump: number;
  freshness: number;
  freshnessHigh: number;
  jokerSmall: number;
  jokerBig: number;
  opponentVoid: number;
  partnerVoidAttackers: number;
  partnerVoidDefenders: number;
  endgamePower: number;
  endgamePoints: number;
}

export const DEFAULT_BOT_LEAD_WEIGHTS: BotLeadWeights = {
  structure: 25,
  structurePerCard: 2,
  trump: 15,
  freshness: 1,
  freshnessHigh: 2,
  jokerSmall: 15,
  jokerBig: 45,
  opponentVoid: 20,
  partnerVoidAttackers: 18,
  partnerVoidDefenders: 12,
  endgamePower: 0.6,
  endgamePoints: 2,
};

function leadWeights(context: BotLeadContext): BotLeadWeights {
  return { ...DEFAULT_BOT_LEAD_WEIGHTS, ...context.weights };
}

/** Avoid drawing friendly trump when every opponent has publicly shown out. */
function preserveFriendlyTrump(context: BotLeadContext): boolean {
  if (context.seat === undefined || !context.playerCount) return false;
  const voidSeats = new Set(
    context.knownVoids
      ?.filter((item) => item.category === 'trump')
      .map((item) => item.seat),
  );
  const seats = Array.from({ length: context.playerCount }, (_, seat) => seat);
  return (
    seats
      .filter((seat) => teamAt(seat) !== teamAt(context.seat!))
      .every((seat) => voidSeats.has(seat)) &&
    seats.some(
      (seat) =>
        seat !== context.seat &&
        teamAt(seat) === teamAt(context.seat!) &&
        !voidSeats.has(seat),
    )
  );
}

export type BotDifficulty = 'relaxed' | 'standard' | 'sharp';

/** Choose an opening lead according to the configured bot risk appetite. */
export function chooseBotOpeningLead(
  hand: readonly Card[],
  otherHands: readonly (readonly Card[])[],
  trump: Trump,
  context: BotLeadContext,
  difficulty: BotDifficulty = 'standard',
): string[] {
  if (difficulty === 'sharp') {
    const gambleHand = preserveFriendlyTrump(context)
      ? hand.filter((card) => category(card, trump) !== 'trump')
      : hand;
    const gamble = chooseBotGambleLead(
      gambleHand,
      otherHands,
      trump,
      context.role,
    );
    if (gamble) return gamble;
  }
  return chooseBotLead(hand, trump, context);
}

/** Choose a deterministic lead using basic score and structure priorities. */
export function chooseBotLead(
  hand: readonly Card[],
  trump: Trump,
  context: BotLeadContext,
): string[] {
  const weights = leadWeights(context);
  const components = availableComponents(hand, trump);
  const sideSuits = components.filter(
    (component) => component.category !== 'trump',
  );
  const candidates =
    preserveFriendlyTrump(context) && sideSuits.length ? sideSuits : components;
  if (!candidates.length) throw new Error('A bot lead requires cards.');
  const nearThreshold = context.defenderScore >= context.swapThreshold - 20;
  const ranked = candidates.map((component, candidateIndex) => {
    const points = component.cards.reduce(
      (sum, card) => sum + cardPoints(card),
      0,
    );
    const jokerReserveCost = component.cards.reduce(
      (sum, card) =>
        sum +
        (card.kind === 'joker'
          ? card.joker === 'big'
            ? weights.jokerBig
            : weights.jokerSmall
          : 0),
      0,
    );
    const structureBonus =
      component.rankCount > 1
        ? weights.structure + component.cardCount * weights.structurePerCard
        : 0;
    const trumpBonus = component.category === 'trump' ? weights.trump : 0;
    const seenInCategory =
      context.seenCards?.filter(
        (card) => category(card, trump) === component.category,
      ).length ?? 0;
    const seenAtHighEnd =
      context.seenCards?.filter(
        (card) =>
          category(card, trump) === component.category &&
          effectivePower(card, trump) >= component.highestPower,
      ).length ?? 0;
    const freshness =
      Math.max(0, 12 - seenInCategory) * weights.freshness +
      Math.max(0, 6 - seenAtHighEnd) * weights.freshnessHigh;
    const voidCount = new Set(
      context.knownVoids
        ?.filter(
          (value) =>
            value.category === component.category &&
            (context.seat === undefined ||
              teamAt(value.seat) !== teamAt(context.seat)),
        )
        .map((value) => value.seat),
    ).size;
    const partnerVoidCount = new Set(
      context.knownVoids
        ?.filter(
          (value) =>
            value.category === component.category &&
            context.seat !== undefined &&
            teamAt(value.seat) === teamAt(context.seat) &&
            value.seat !== context.seat,
        )
        .map((value) => value.seat),
    ).size;
    const voidAdjustment =
      component.category === 'trump'
        ? 0
        : context.role === 'attackers'
          ? partnerVoidCount * weights.partnerVoidAttackers -
            voidCount * weights.opponentVoid
          : partnerVoidCount * weights.partnerVoidDefenders + voidCount * 5;
    const endgameBonus =
      context.cardsRemaining !== undefined && context.cardsRemaining <= 4
        ? component.highestPower * weights.endgamePower +
          points * weights.endgamePoints
        : 0;
    const score =
      context.role === 'attackers'
        ? structureBonus +
          trumpBonus +
          freshness +
          voidAdjustment -
          points -
          jokerReserveCost +
          endgameBonus
        : nearThreshold
          ? points * 10 +
            structureBonus +
            trumpBonus +
            freshness +
            voidAdjustment -
            jokerReserveCost +
            endgameBonus
          : structureBonus +
            trumpBonus +
            freshness +
            voidAdjustment -
            points -
            jokerReserveCost +
            endgameBonus;
    const beliefRuff =
      context.seat !== undefined && context.playerCount
        ? estimatePartnerRuffProbability(
            {
              playerCount: context.playerCount as PlayerCount,
              ownHand: hand,
              trump,
              seenCards: context.seenCards,
              knownVoids: context.knownVoids,
              cardsRemaining: context.cardsRemaining,
            },
            context.seat,
            component.category,
          ) * (context.role === 'attackers' ? 14 : 9)
        : 0;
    let searchBonus = 0;
    if (
      context.beliefSearch &&
      candidateIndex < 3 &&
      context.seat !== undefined &&
      context.playerCount
    ) {
      const samples = samplePossibleHands(
        {
          playerCount: context.playerCount as PlayerCount,
          ownHand: hand,
          trump,
          seat: context.seat,
          seenCards: context.seenCards,
          knownVoids: context.knownVoids,
          cardsRemaining: context.cardsRemaining,
        },
        context.beliefSearchSamples ?? 2,
      );
      const lead = decomposeLead(component.cards, trump);
      if (lead) {
        let teamWins = 0;
        for (const hands of samples) {
          let winner = context.seat;
          let winning = lead;
          for (let offset = 1; offset < context.playerCount; offset++) {
            const seat = (context.seat + offset) % context.playerCount;
            const response = chooseBotPlay(hands[seat] ?? [], lead, trump, {
              seat,
              winnerSeat: winner,
              winning,
              lastToPlay: offset === context.playerCount - 1,
            });
            const responseComponents = decomposeLead(
              (hands[seat] ?? []).filter((card) => response.includes(card.id)),
              trump,
            );
            if (responseComponents && beatsPlay(responseComponents, winning)) {
              winner = seat;
              winning = responseComponents;
            }
          }
          if (teamAt(winner) === teamAt(context.seat)) teamWins++;
        }
        searchBonus = ((teamWins / Math.max(1, samples.length)) * 2 - 1) * 12;
      }
    }
    return { component, score: score + beliefRuff + searchBonus };
  });
  ranked.sort(
    (a, b) =>
      b.score - a.score ||
      b.component.cardCount - a.component.cardCount ||
      b.component.multiplicity - a.component.multiplicity ||
      b.component.highestPower - a.component.highestPower ||
      a.component.cards
        .map((card) => card.id)
        .join('|')
        .localeCompare(b.component.cards.map((card) => card.id).join('|')),
  );
  return ranked[0]!.component.cards.map((card) => card.id);
}

/** Return a gamble lead only when its component grouping passes server-side validation. */
export function chooseBotGambleLead(
  hand: readonly Card[],
  otherHands: readonly (readonly Card[])[],
  trump: Trump,
  role: 'attackers' | 'defenders',
): string[] | null {
  if (role !== 'attackers') return null;
  const categories = [...new Set(hand.map((card) => category(card, trump)))];
  const choices = categories
    .map((group) => {
      const cards = hand.filter((card) => category(card, trump) === group);
      const components = decomposeLead(cards, trump);
      if (!components || components.length < 2) return null;
      const result = validateGamble(components, otherHands, trump, 'attackers');
      return result.reduced ? null : { cards, size: cards.length, components };
    })
    .filter(
      (
        choice,
      ): choice is { cards: Card[]; size: number; components: Component[] } =>
        choice !== null,
    );
  choices.sort(
    (a, b) =>
      b.size - a.size ||
      b.components.length - a.components.length ||
      a.cards
        .map((card) => card.id)
        .join('|')
        .localeCompare(b.cards.map((card) => card.id).join('|')),
  );
  return choices[0]?.cards.map((card) => card.id) ?? null;
}

/** Rank legal declarations by call strength, then by the quality of the trump suit. */
export function chooseBotDeclaration(
  options: readonly Declaration[],
  hand: readonly Card[],
  trumpLevel: Declaration['level'],
): Declaration | null {
  if (!options.length) return null;
  const ranked = options.map((option) => {
    const suited =
      option.kind === 'suit'
        ? hand.filter(
            (card): card is Extract<Card, { kind: 'suited' }> =>
              card.kind === 'suited' && card.suit === option.suit,
          )
        : [];
    const byRank = new Map<string, number>();
    for (const card of suited)
      byRank.set(card.rank, (byRank.get(card.rank) ?? 0) + 1);
    const pairs = [...byRank.values()].reduce(
      (sum, count) => sum + Math.max(0, count - 1),
      0,
    );
    const rankOrder = [
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'J',
      'Q',
      'K',
      'A',
    ];
    const pairedRanks = new Set(
      [...byRank.entries()]
        .filter(([, count]) => count >= 2)
        .map(([rank]) => rank),
    );
    const tractors = rankOrder
      .slice(0, -1)
      .reduce(
        (sum, rank, index) =>
          sum +
          (pairedRanks.has(rank) && pairedRanks.has(rankOrder[index + 1]!)
            ? 1
            : 0),
        0,
      );
    const highCards = suited.filter(
      (card) =>
        card.rank === trumpLevel ||
        card.rank === 'A' ||
        card.rank === 'K' ||
        card.rank === 'Q',
    ).length;
    const suitPower =
      option.kind === 'suit'
        ? suited
            .map((card) =>
              effectivePower(card, { level: trumpLevel, suit: option.suit }),
            )
            .sort((a, b) => b - a)
            .slice(0, 5)
            .reduce((sum, power) => sum + power, 0)
        : 0;
    const voidSuits =
      option.kind === 'suit'
        ? (['clubs', 'diamonds', 'hearts', 'spades'] as const).filter(
            (suit) =>
              suit !== option.suit &&
              !hand.some(
                (card) => card.kind === 'suited' && card.suit === suit,
              ),
          ).length
        : 0;
    const suitQuality =
      suited.length * 8 +
      pairs * 14 +
      tractors * 12 +
      highCards * 3 +
      suitPower * 0.5 +
      voidSuits * 18;
    const jokerBonus = option.kind === 'joker' ? 1000 : 0;
    return {
      option,
      score: jokerBonus + option.multiplicity * 100 + suitQuality,
    };
  });
  ranked.sort(
    (a, b) =>
      b.score - a.score ||
      b.option.cardIds.length - a.option.cardIds.length ||
      a.option.cardIds.join('|').localeCompare(b.option.cardIds.join('|')),
  );
  return ranked[0]!.option;
}

/** Uses only the bot's hand, public lead, and trump; never opponents' hands. */
export function chooseBotPlay(
  hand: readonly Card[],
  lead: readonly Component[] | null,
  trump: Trump,
  context?: BotPlayContext,
): string[] {
  const ordered = [...hand].sort(
    (a, b) =>
      Number(category(a, trump) === 'trump') -
        Number(category(b, trump) === 'trump') ||
      effectivePower(a, trump) - effectivePower(b, trump) ||
      a.id.localeCompare(b.id),
  );
  if (!lead) {
    const choices = availableComponents(ordered, trump);
    return choices[0]!.cards.map((card) => card.id);
  }
  const count = lead.reduce((sum, item) => sum + item.cardCount, 0);
  const suited = ordered.filter(
    (card) => category(card, trump) === lead[0]!.category,
  );
  let chosen: Card[];
  if (suited.length <= count) {
    chosen = [
      ...suited,
      ...withoutCards(ordered, suited).slice(0, count - suited.length),
    ];
  } else {
    const full = matchComponents(suited, lead, trump, {
      protectLargerSets: true,
    });
    if (full) chosen = full.flatMap((item) => [...item.cards]);
    else {
      chosen = [];
      const groups = identityGroups(suited).map((cards) => ({
        cards,
        initial: cards.length,
      }));
      const max = Math.max(...lead.map((item) => item.multiplicity));
      for (let tier = max; tier >= 2; tier--) {
        const budget =
          lead
            .filter((item) => item.multiplicity >= tier)
            .reduce((sum, item) => sum + item.cardCount, 0) - chosen.length;
        let capacity = Math.floor(budget / tier);
        for (const group of groups) {
          if (group.initial > tier) continue;
          const take = Math.min(
            capacity,
            Math.floor(group.cards.length / tier),
          );
          chosen.push(...group.cards.splice(0, take * tier));
          capacity -= take;
        }
      }
      // Prefer spare singles before cutting a protected larger set.
      const rest = groups
        .sort((a, b) => a.initial - b.initial)
        .flatMap((group) => group.cards);
      chosen.push(...rest.slice(0, count - chosen.length));
    }
  }
  const validation = validateFollow(hand, chosen, lead, trump);
  if (!validation.legal)
    throw new Error(`Bot generated an illegal follow: ${validation.code}`);
  if (context) chosen = tacticalFollow(hand, chosen, lead, trump, context);
  return chosen.map((card) => card.id);
}

/** Compare only legal candidates; the baseline always remains available. */
function tacticalFollow(
  hand: readonly Card[],
  baseline: Card[],
  lead: readonly Component[],
  trump: Trump,
  context: BotPlayContext,
): Card[] {
  const candidates = [baseline];
  const led = hand.filter(
    (card) => category(card, trump) === lead[0]!.category,
  );
  const pool = led.length
    ? led
    : hand.filter((card) => category(card, trump) === 'trump');
  if (lead.length === 1) {
    candidates.push(
      ...availableComponents(pool, trump, lead[0]).map((item) => [
        ...item.cards,
      ]),
    );
  } else {
    const winning = matchComponents(pool, lead, trump, {
      mustBeat: context.winning,
    });
    if (winning) candidates.push(winning.flatMap((item) => [...item.cards]));
  }
  // A void player can discard point cards to a partner or avoid donating them to opponents.
  if (lead.length === 1 && lead[0]!.cardCount === 1 && !led.length) {
    candidates.push(...hand.map((card) => [card]));
  }
  const partnerWinning = teamAt(context.seat) === teamAt(context.winnerSeat);
  const score = (cards: Card[]) => {
    const follow = validateFollow(hand, cards, lead, trump);
    const wins =
      follow.legal &&
      follow.matchesLead &&
      winningComponents(cards, lead, context.winning, trump, {
        largestPatternWins: context.largestPatternWins === true,
      }) !== null;
    const points = cards.reduce((sum, card) => sum + cardPoints(card), 0);
    const strength = cards.reduce(
      (sum, card) =>
        sum +
        effectivePower(card, trump) +
        (category(card, trump) === 'trump' ? 30 : 0) +
        (card.kind === 'joker' ? (card.joker === 'big' ? 220 : 90) : 0),
      0,
    );
    // Preserve a partner's winning cards; when last, safely feed them points.
    if (partnerWinning)
      return [context.lastToPlay ? -points : points, Number(wins), strength];
    // Take the trick using the least strength; otherwise shed as few points as possible.
    return [wins ? 0 : 1, wins ? strength : points, strength];
  };
  return candidates
    .filter((cards) => validateFollow(hand, cards, lead, trump).legal)
    .sort((a, b) => {
      const left = score(a),
        right = score(b);
      for (let index = 0; index < left.length; index++) {
        const difference = left[index]! - right[index]!;
        if (difference) return difference;
      }
      return a
        .map((card) => card.id)
        .join('|')
        .localeCompare(b.map((card) => card.id).join('|'));
    })[0]!;
}

export function chooseBotBurial(
  cards: readonly Card[],
  size: number,
  trump: Trump,
): string[] {
  return [...cards]
    .sort(
      (a, b) =>
        Number(category(a, trump) === 'trump') -
          Number(category(b, trump) === 'trump') ||
        cardPoints(a) - cardPoints(b) ||
        effectivePower(a, trump) - effectivePower(b, trump) ||
        a.id.localeCompare(b.id),
    )
    .slice(0, size)
    .map((card) => card.id);
}
