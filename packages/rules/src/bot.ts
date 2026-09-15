import { cardPoints, category, effectivePower, teamAt } from './cards.js';
import type { Card, Trump } from './cards.js';
import {
  availableComponents,
  identityGroups,
  matchComponents,
  withoutCards,
} from './components.js';
import type { Component } from './components.js';
import { validateFollow } from './follow.js';
import { winningComponents } from './gamble.js';

export interface BotPlayContext {
  seat: number;
  winnerSeat: number;
  winning: readonly Component[];
  lastToPlay: boolean;
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
