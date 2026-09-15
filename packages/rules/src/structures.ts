import { cardIdentity, category, effectivePower } from './cards.js';
import type { Card, Category, Trump } from './cards.js';

export interface Structure {
  readonly category: Category;
  readonly multiplicity: number;
  readonly rankCount: number;
  readonly cardCount: number;
  readonly highestPower: number;
}

/** Recognizes one whole homogeneous structure. Does not decompose gambles. */
export function homogeneousStructure(
  cards: readonly Card[],
  trump: Trump,
): Structure | null {
  const first = cards[0];
  if (!first || new Set(cards.map((card) => card.id)).size !== cards.length)
    return null;
  const groupCategory = category(first, trump);
  if (cards.some((card) => category(card, trump) !== groupCategory))
    return null;
  const groups = new Map<string, Card[]>();
  for (const card of cards) {
    const key = cardIdentity(card);
    const group = groups.get(key) ?? [];
    group.push(card);
    groups.set(key, group);
  }
  const sets = [...groups.values()];
  const multiplicity = sets[0]!.length;
  if (sets.some((set) => set.length !== multiplicity)) return null;
  // Runs of singles are separate gamble components, not tractors.
  if (sets.length > 1 && multiplicity < 2) return null;
  const powers = sets
    .map((set) => effectivePower(set[0]!, trump))
    .sort((a, b) => a - b);
  if (
    powers.some((power, index) => index > 0 && power !== powers[index - 1]! + 1)
  )
    return null;
  return {
    category: groupCategory,
    multiplicity,
    rankCount: sets.length,
    cardCount: cards.length,
    highestPower: powers.at(-1)!,
  };
}

export function beatsHomogeneous(
  challenger: Structure,
  current: Structure,
): boolean {
  if (
    challenger.multiplicity !== current.multiplicity ||
    challenger.rankCount !== current.rankCount
  )
    return false;
  if (challenger.category !== current.category)
    return challenger.category === 'trump';
  return challenger.highestPower > current.highestPower;
}
