import {
  availableComponents,
  cardIdentity,
  cardPoints,
  category,
  chooseBotPlay,
  effectivePower,
  matchComponents,
  teamAt,
  validateFollow,
  winningComponents,
} from '@tractor/rules';
import type {
  BotPlayContext,
  Card,
  Component,
  Declaration,
  Trump,
} from '@tractor/rules';
import type { BotPolicy } from '../bot-policy.js';

/** The Roblox game's built-in bot (roblox/src/shared/PlayRules.luau), as a
 * training opponent. roblox/tests/parity.mjs checks it against the Luau. */
const ids = (cards: readonly Card[]) => cards.map((card) => card.id);
const sortedKey = (cards: readonly Card[]) => ids(cards).sort().join('|');

export function robloxBurial(
  cards: readonly Card[],
  size: number,
  trump: Trump,
): string[] {
  const counts = new Map<string, number>();
  const groups = new Map<string, number>();
  for (const card of cards) {
    const group = category(card, trump);
    counts.set(group, (counts.get(group) ?? 0) + 1);
    groups.set(cardIdentity(card), (groups.get(cardIdentity(card)) ?? 0) + 1);
  }
  const scored = cards.map((card) => {
    const group = category(card, trump);
    const points = cardPoints(card);
    const power = effectivePower(card, trump);
    const suitCount = counts.get(group)!;
    let score = 0;
    if (group === 'trump') {
      score += 50000 + (card.kind === 'joker' ? 100000 : 0);
    } else {
      score += suitCount <= 2 ? -4000 : suitCount <= 4 ? -1500 : 500;
      if (groups.get(cardIdentity(card))! >= 2 && suitCount > 2) score += 3000;
      if (points > 0) score += suitCount <= 2 ? 200 : 1800;
      score += power * 50;
    }
    return { card, score };
  });
  scored.sort((a, b) => a.score - b.score || (a.card.id < b.card.id ? -1 : 1));
  return scored.slice(0, size).map((entry) => entry.card.id);
}

export function robloxLead(hand: readonly Card[], trump: Trump): string[] {
  const scored = availableComponents(hand, trump).map((component) => {
    const isTrump = component.category === 'trump';
    const points = component.cards.reduce((n, c) => n + cardPoints(c), 0);
    const power = component.highestPower;
    let score = 0;
    if (component.rankCount > 1 && component.multiplicity >= 2)
      score += 2500 + component.cardCount * 200 + power * 20;
    else if (component.multiplicity >= 2) {
      if (!isTrump) score += power >= 10 ? 1500 + power * 30 : 600 + power * 15;
      else score += 800 + power * 20;
    } else if (!isTrump) {
      if (power >= 12) score += 1800;
      else if (points > 0 && power < 10) score -= 800;
      else score += power * 15;
    } else if (component.cards[0]?.kind === 'joker') score += 700;
    else score -= 400;
    return { component, score, key: sortedKey(component.cards) };
  });
  scored.sort((a, b) => b.score - a.score || (a.key < b.key ? -1 : 1));
  return ids(scored[0]!.component.cards);
}

export function robloxFollow(
  hand: readonly Card[],
  lead: readonly Component[],
  trump: Trump,
  context: BotPlayContext,
): string[] {
  const baselineIds = chooseBotPlay(hand, lead, trump);
  const baseline = baselineIds.map((id) => hand.find((c) => c.id === id)!);
  const candidates: Card[][] = [baseline];
  const count = lead.reduce((sum, item) => sum + item.cardCount, 0);
  const matching = hand.filter(
    (card) => category(card, trump) === lead[0]!.category,
  );
  if (!matching.length) {
    if (count === 1) candidates.push(...hand.map((card) => [card]));
    else {
      const trumps = hand.filter((c) => category(c, trump) === 'trump');
      const ruff =
        trumps.length >= count &&
        matchComponents(trumps, lead, trump, { protectLargerSets: true });
      if (ruff) candidates.push(ruff.flatMap((item) => [...item.cards]));
    }
  } else if (count === 1) candidates.push(...matching.map((card) => [card]));
  else {
    const full = matchComponents(matching, lead, trump, {
      protectLargerSets: false,
    });
    if (full) candidates.push(full.flatMap((item) => [...item.cards]));
  }
  const partner = teamAt(context.winnerSeat) === teamAt(context.seat);
  const score = (cards: readonly Card[]): number[] => {
    const follow = validateFollow(hand, cards, lead, trump);
    if (!follow.legal) return [999999, 999999, 999999];
    const wins =
      follow.matchesLead &&
      winningComponents(cards, lead, context.winning, trump) !== null;
    const points = cards.reduce((n, c) => n + cardPoints(c), 0);
    const strength = cards.reduce(
      (n, c) =>
        n +
        effectivePower(c, trump) +
        (category(c, trump) === 'trump' ? 30 : 0) +
        (c.kind === 'joker' ? (c.joker === 'big' ? 200 : 100) : 0),
      0,
    );
    if (partner)
      return [
        context.lastToPlay ? -points : -points * 2,
        Number(wins),
        strength,
      ];
    return wins
      ? [0, strength, -points]
      : [1, points * 100 + strength, strength];
  };
  const ordered = candidates
    .map((cards) => ({ cards, score: score(cards), key: sortedKey(cards) }))
    .sort((a, b) => {
      for (let i = 0; i < 3; i++) {
        const difference = a.score[i]! - b.score[i]!;
        if (difference) return difference;
      }
      return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
    });
  return ids(ordered[0]!.cards);
}

export function robloxDeclaration(
  options: readonly Declaration[],
): Declaration | null {
  const suit = (o: Declaration) => (o.kind === 'suit' ? o.suit : undefined);
  let chosen: Declaration | null = null;
  for (const option of options)
    if (
      !chosen ||
      (option.kind !== 'suit' && chosen.kind === 'suit') ||
      (suit(option) === suit(chosen) &&
        option.multiplicity > chosen.multiplicity)
    )
      chosen = option;
  return chosen;
}

export const robloxBotPolicy: BotPolicy = {
  lead: (hand, trump) => robloxLead(hand, trump),
  follow: (hand, lead, trump, context) =>
    context && lead
      ? robloxFollow(hand, lead, trump, context)
      : chooseBotPlay(hand, lead, trump, context),
  declare: (options) => robloxDeclaration(options),
  bury: robloxBurial,
};
