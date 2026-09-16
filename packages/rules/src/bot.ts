import { cardPoints, category, effectivePower, teamAt } from './cards.js';
import type { Card, Trump } from './cards.js';
import {
  availableComponents,
  decomposeLead,
  identityGroups,
  matchComponents,
  withoutCards,
} from './components.js';
import type { Component } from './components.js';
import { validateFollow } from './follow.js';
import { winningComponents } from './gamble.js';
import { validateGamble } from './gamble.js';
import type { Declaration } from './declarations.js';

export interface BotPlayContext {
  seat: number;
  winnerSeat: number;
  winning: readonly Component[];
  lastToPlay: boolean;
}

export interface BotLeadContext {
  role: 'attackers' | 'defenders';
  defenderScore: number;
  swapThreshold: number;
  seenCards?: readonly Card[];
  knownVoids?: readonly string[];
}

/** Choose a deterministic lead using basic score and structure priorities. */
export function chooseBotLead(
  hand: readonly Card[],
  trump: Trump,
  context: BotLeadContext,
): string[] {
  const candidates = availableComponents(hand, trump);
  if (!candidates.length) throw new Error('A bot lead requires cards.');
  const nearThreshold = context.defenderScore >= context.swapThreshold - 20;
  const ranked = candidates.map((component) => {
    const points = component.cards.reduce(
      (sum, card) => sum + cardPoints(card),
      0,
    );
    const structureBonus =
      component.rankCount > 1 ? 25 + component.cardCount * 2 : 0;
    const trumpBonus = component.category === 'trump' ? 15 : 0;
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
      Math.max(0, 12 - seenInCategory) + Math.max(0, 6 - seenAtHighEnd) * 2;
    const voidCount =
      context.knownVoids?.filter((value) => value === component.category)
        .length ?? 0;
    const voidAdjustment =
      context.role === 'attackers' ? -voidCount * 20 : voidCount * 5;
    const score =
      context.role === 'attackers'
        ? structureBonus + trumpBonus + freshness + voidAdjustment - points
        : nearThreshold
          ? points * 10 +
            structureBonus +
            trumpBonus +
            freshness +
            voidAdjustment
          : structureBonus + trumpBonus + freshness + voidAdjustment - points;
    return { component, score };
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

/** Rank legal declarations by strength first, then by the amount of matching trump support. */
export function chooseBotDeclaration(
  options: readonly Declaration[],
  hand: readonly Card[],
  trumpLevel: Declaration['level'],
): Declaration | null {
  if (!options.length) return null;
  const ranked = options.map((option) => {
    const support =
      option.kind === 'suit'
        ? hand.filter(
            (card) =>
              card.kind === 'suited' &&
              card.suit === option.suit &&
              (card.rank === trumpLevel ||
                card.rank === 'A' ||
                card.rank === 'K' ||
                card.rank === 'Q'),
          ).length
        : hand.filter((card) => card.kind === 'joker').length;
    const jokerBonus = option.kind === 'joker' ? 1000 : 0;
    return {
      option,
      score: jokerBonus + option.multiplicity * 100 + support * 3,
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
      winningComponents(cards, lead, context.winning, trump) !== null;
    const points = cards.reduce((sum, card) => sum + cardPoints(card), 0);
    const strength = cards.reduce(
      (sum, card) =>
        sum +
        effectivePower(card, trump) +
        (category(card, trump) === 'trump' ? 30 : 0),
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
